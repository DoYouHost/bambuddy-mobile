import 'dart:collection';

import 'log_event.dart';
import 'log_redactor.dart';

/// How long one recording may run before it cuts itself off.
///
/// The ring buffer bounds memory, but the mirror on disk gets every line and
/// nothing ever takes one back out, so length is the only thing that bounds the
/// file. Five minutes is enough to reproduce almost anything a user can
/// reproduce on purpose; the rare bug that needs longer has to be reported some
/// other way. In exchange, a recording forgotten overnight cannot exist.
const recordingLimit = Duration(minutes: 5);

/// In-memory ring buffer for one recording session, plus its JSONL export.
///
/// Records are encoded (and redacted) on the way in, so the cost is paid once
/// and memory stays bounded by what will actually be uploaded. When a cap is
/// hit the oldest records go and the gap is reported as a single `truncated`
/// marker at export — losing the start of a long session is fine, losing the
/// moment the user reproduced the bug is not.
class LogStore {
  LogStore({
    required this.header,
    LogRedactor? redactor,
    this.maxRecords = 4000,
    this.maxChars = 512 * 1024,
    this.maxDuration = recordingLimit,
    DateTime Function()? clock,
    this.onLine,
  })  : redactor = redactor ?? LogRedactor(),
        _clock = clock ?? DateTime.now;

  final LogHeader header;
  final LogRedactor redactor;
  final int maxRecords;

  /// The session's hard ceiling. Enforced here rather than only by whoever
  /// started the recording: a timer in a backgrounded app fires late or not at
  /// all, and the foreground-service isolate keeps logging into its own store
  /// the whole time. Past the ceiling the store takes nothing at all, so the
  /// file it mirrors to stops growing whatever anybody else does.
  final Duration maxDuration;

  /// Cap in characters, not bytes. Records are ASCII-dominant so the two are
  /// close; the hard byte limit lives at the relay, this one only has to keep
  /// a runaway loop from filling the heap.
  final int maxChars;

  final DateTime Function() _clock;

  /// Mirrors each encoded line to a durable sink. The FGS isolate needs it —
  /// its heap dies with the service, so memory alone would lose the records.
  ///
  /// Lines go out as they arrive; [export] is what puts them in order.
  final void Function(String line)? onLine;

  final ListQueue<_Record> _records = ListQueue<_Record>();
  int _chars = 0;
  int _dropped = 0;
  int _gapT = 0;
  bool _closed = false;

  int get recordCount => _records.length;
  int get droppedCount => _dropped;
  int get approximateChars => _chars;

  /// Whether the session ran into [maxDuration] and stopped taking records.
  bool get isClosed => _closed;

  /// Milliseconds since the session header's `ts`. Clamped at zero so a clock
  /// jump backwards can't produce negative offsets that break ordering.
  int get elapsedMs {
    final ms = _clock().difference(header.ts).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  /// When this store took its first record. [maxDuration] is measured from
  /// here and not from the header's `ts`, which is a label for the session and
  /// is whatever its author says it is; the ceiling is about how long *this*
  /// buffer has been filling. In a real session the two are the same moment.
  late final DateTime _openedAt = _clock();

  int get _openMs {
    final ms = _clock().difference(_openedAt).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  /// Adds a record, stamped with [at] milliseconds when the moment being
  /// recorded is not "now".
  ///
  /// Interactions need it: a button's handler runs before the probe sees the
  /// pointer go up, so a tap stamped at write time lands *after* the route
  /// change, the request and everything else it caused. With HTTP, WebSocket and
  /// the background service on the same timeline that inversion stops being a
  /// curiosity and starts costing time, so a touch is stamped with the moment
  /// the finger went down.
  void add(
    LogSource src,
    String evt, {
    LogLevel lvl = LogLevel.info,
    Map<String, Object?> fields = const {},
    int? at,
  }) {
    if (_closed) return;
    if (_openMs >= maxDuration.inMilliseconds) {
      _closed = true;
      // The session ends on this line instead of on `recording_stopped`, which
      // is the truth: nobody stopped it, it ran out.
      _write(
        LogEvent(
          t: elapsedMs,
          src: LogSource.app,
          evt: 'limit_reached',
          lvl: LogLevel.warn,
          fields: {'minutes': maxDuration.inMinutes},
        ),
      );
      return;
    }
    _write(
      LogEvent(
        // A touch is stamped with the moment the finger went down, which may be
        // before now — never after, so the ceiling above still holds.
        t: at ?? elapsedMs,
        src: src,
        evt: evt,
        lvl: lvl,
        fields: redactor.scrubFields(fields),
      ),
    );
  }

  void _write(LogEvent event) =>
      _append(_Record(event.toJsonLine(), event.t));

  /// "The bug just happened" marker the user presses while recording. Cheapest
  /// possible thing that cuts the search through a few thousand records.
  void mark() => add(LogSource.app, 'user_marker');

  void _append(_Record record) {
    _records.addLast(record);
    _chars += record.line.length + 1; // + newline

    // Keep at least one record: a single oversized line must not empty the
    // queue and spin here forever.
    while (_records.length > 1 &&
        (_records.length > maxRecords || _chars > maxChars)) {
      final dropped = _records.removeFirst();
      _chars -= dropped.line.length + 1;
      _dropped++;
      _gapT = dropped.t;
    }

    onLine?.call(record.line);
  }

  /// Full JSONL for this stream: header line, the truncation marker if any
  /// records were dropped, then the records in the order things happened.
  ///
  /// Sorted by `t` rather than by arrival, because a record stamped with [add]'s
  /// `at` can arrive after something that happened later than it. Ties keep
  /// arrival order — Dart's sort is not stable on its own, hence the sequence
  /// number in the comparison (same trick as `mergeSessions`).
  String export() {
    final ordered = [
      for (var i = 0; i < _records.length; i++) (i, _records.elementAt(i)),
    ]..sort((a, b) =>
        a.$2.t != b.$2.t ? a.$2.t.compareTo(b.$2.t) : a.$1.compareTo(b.$1));

    final buf = StringBuffer()..writeln(header.toJsonLine());
    if (_dropped > 0) {
      buf.writeln(
        LogEvent(
          t: _gapT,
          src: LogSource.app,
          evt: 'truncated',
          lvl: LogLevel.warn,
          fields: {'dropped': _dropped},
        ).toJsonLine(),
      );
    }
    for (final r in ordered) {
      buf.writeln(r.$2.line);
    }
    return buf.toString();
  }

  void clear() {
    _records.clear();
    _chars = 0;
    _dropped = 0;
    _gapT = 0;
  }
}

/// `t` is kept alongside the encoded line so the truncation marker can point at
/// where the gap is without re-parsing JSON.
class _Record {
  const _Record(this.line, this.t);

  final String line;
  final int t;
}
