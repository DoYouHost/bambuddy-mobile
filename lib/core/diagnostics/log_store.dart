import 'dart:collection';

import 'package:clock/clock.dart' as ambient;

import 'log_event.dart';
import 'report_config.dart';
import 'package:app_report_client/app_report_client.dart';

/// The session's two hard ceilings; `docs/diagnostics-log.md` has the reasoning
/// behind both numbers.
const recordingLimit = Duration(minutes: 30);
const recordingSizeLimit = 20 * 1024 * 1024;

/// Runaway guards on the ring, not on the session — see [LogStore.maxRecords]
/// and [LogStore.maxChars].
const ringRecordLimit = 20000;
const ringCharLimit = 4 * 1024 * 1024;

/// In-memory ring buffer for one recording session, plus its JSONL export.
/// Records are encoded and redacted on the way in, so the cost is paid once.
/// When a cap is hit the oldest go and the gap becomes a `truncated` marker at
/// export — seen only when there was no file to read the session back from, the
/// ring being the fallback for a device that cannot write one.
class LogStore {
  LogStore({
    required this.header,
    LogRedactor? redactor,
    this.maxRecords = ringRecordLimit,
    this.maxChars = ringCharLimit,
    this.maxDuration = recordingLimit,
    this.maxBytes = recordingSizeLimit,
    DateTime Function()? clock,
    DateTime? openedAt,
    this.onLine,
    this.onClosed,
  }) : redactor = redactor ?? bambuddyRedactor(),
       _openedAtOverride = openedAt,
       _clock = clock ?? (() => ambient.clock.now());

  final LogHeader header;
  final LogRedactor redactor;

  /// A **runaway guard, not a budget** — a session is bounded by [maxDuration]
  /// and [maxBytes], and reaching this costs the report nothing: the session is
  /// read back from its file, which nothing evicts from.
  final int maxRecords;

  /// Enforced here rather than only by whoever started the recording: a timer
  /// in a backgrounded app fires late or not at all, and the FGS isolate keeps
  /// logging into its own store the whole time.
  final Duration maxDuration;

  /// Characters, not bytes — records are ASCII-dominant so the two are close.
  /// Same runaway-guard reasoning as [maxRecords].
  final int maxChars;

  /// Counted over **everything accepted**, not over what the ring still holds.
  final int maxBytes;

  final DateTime Function() _clock;

  /// Called once when the store closes itself on a ceiling, with that ceiling's
  /// wire name (`time` or `size`). The app has to take its countdown down —
  /// leaving it running is the app claiming to record what it is throwing away.
  final void Function(String limit)? onClosed;

  /// Mirrors each encoded line to a durable sink. The FGS isolate needs it —
  /// its heap dies with the service. Lines go out as they arrive; [export] is
  /// what puts them in order.
  final void Function(String line)? onLine;

  final ListQueue<_Record> _records = ListQueue<_Record>();
  int _chars = 0;

  /// Everything ever accepted, which is what the file holds; [_chars] shrinks
  /// when the ring evicts and the file never does.
  int _written = 0;
  int _dropped = 0;
  int _gapT = 0;
  bool _closed = false;

  int get recordCount => _records.length;
  int get droppedCount => _dropped;
  int get approximateChars => _chars;

  /// Whether the session ran into [maxDuration] and stopped taking records.
  bool get isClosed => _closed;

  /// Clamped at zero so a clock jump backwards cannot produce negative offsets
  /// that break ordering.
  int get elapsedMs {
    final ms = _clock().difference(header.ts).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  /// Moment the [maxDuration] deadline counts from, when the caller knows
  /// better than this store does — the background isolate does, being the
  /// *second or fifth* store of one recording after Android restarts the
  /// service. Each fresh store would otherwise start the clock over, so a
  /// crash-looping service could record for an hour.
  final DateTime? _openedAtOverride;

  /// Not the header's `ts`, which is a label whatever its author says it is:
  /// the ceiling is about how long *this* buffer has been filling. In a real
  /// session the two are the same moment.
  late final DateTime _openedAt = _openedAtOverride ?? _clock();

  int get _openMs {
    final ms = _clock().difference(_openedAt).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  /// Adds a record, stamped with [at] milliseconds when the moment being
  /// recorded is not "now" — a button's handler runs before the probe sees the
  /// pointer go up, so a tap stamped at write time would land *after* the route
  /// change and the request it caused.
  void add(
    LogSource src,
    String evt, {
    LogLevel lvl = LogLevel.info,
    Map<String, Object?> fields = const {},
    int? at,
  }) {
    if (_closed) return;
    // Whichever ceiling comes first ends the session and the record says which.
    // The size one catches a stalled clock, where `_openMs` stays at zero and
    // the duration check never fires at all.
    if (_openMs >= maxDuration.inMilliseconds) {
      _close('time', {'minutes': maxDuration.inMinutes});
      return;
    }
    if (_written >= maxBytes) {
      _close('size', {'mb': maxBytes ~/ (1024 * 1024)});
      return;
    }
    _write(
      LogEvent(
        // [at] may be before now — never after, so the ceiling above holds.
        t: at ?? elapsedMs,
        src: src,
        evt: evt,
        lvl: lvl,
        fields: redactor.scrubFields(fields),
      ),
    );
  }

  /// Ends the session on one of its own ceilings. `limit_reached`, not
  /// `recording_stopped`: nobody stopped it, it ran out.
  void _close(String limit, Map<String, Object?> fields) {
    _closed = true;
    _write(
      LogEvent(
        t: elapsedMs,
        src: LogSource.app,
        evt: 'limit_reached',
        lvl: LogLevel.warn,
        fields: {'limit': limit, ...fields},
      ),
    );
    onClosed?.call(limit);
  }

  void _write(LogEvent event) => _append(_Record(event.toJsonLine(), event.t));

  /// "The bug just happened" marker the user presses while recording.
  void mark() => add(LogSource.app, 'user_marker');

  void _append(_Record record) {
    _records.addLast(record);
    _chars += record.line.length + 1; // + newline
    _written += record.line.length + 1;

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
  /// Sorted by `t` rather than by arrival, since [add]'s `at` can back-date a
  /// record. Ties keep arrival order — Dart's sort is not stable on its own,
  /// hence the sequence number (same trick as `mergeSessions`).
  String export() {
    final ordered =
        [for (var i = 0; i < _records.length; i++) (i, _records.elementAt(i))]
          ..sort(
            (a, b) => a.$2.t != b.$2.t
                ? a.$2.t.compareTo(b.$2.t)
                : a.$1.compareTo(b.$1),
          );

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
