import 'dart:collection';

import 'log_event.dart';
import 'log_redactor.dart';

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
    DateTime Function()? clock,
    this.onLine,
  })  : redactor = redactor ?? LogRedactor(),
        _clock = clock ?? DateTime.now;

  final LogHeader header;
  final LogRedactor redactor;
  final int maxRecords;

  /// Cap in characters, not bytes. Records are ASCII-dominant so the two are
  /// close; the hard byte limit lives at the relay, this one only has to keep
  /// a runaway loop from filling the heap.
  final int maxChars;

  final DateTime Function() _clock;

  /// Mirrors each encoded line to a durable sink. The FGS isolate needs it —
  /// its heap dies with the service, so memory alone would lose the records.
  final void Function(String line)? onLine;

  final ListQueue<_Record> _records = ListQueue<_Record>();
  int _chars = 0;
  int _dropped = 0;
  int _gapT = 0;

  int get recordCount => _records.length;
  int get droppedCount => _dropped;
  int get approximateChars => _chars;

  /// Milliseconds since the session header's `ts`. Clamped at zero so a clock
  /// jump backwards can't produce negative offsets that break ordering.
  int get elapsedMs {
    final ms = _clock().difference(header.ts).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  void add(
    LogSource src,
    String evt, {
    LogLevel lvl = LogLevel.info,
    Map<String, Object?> fields = const {},
  }) {
    final event = LogEvent(
      t: elapsedMs,
      src: src,
      evt: evt,
      lvl: lvl,
      fields: redactor.scrubFields(fields),
    );
    _append(_Record(event.toJsonLine(), event.t));
  }

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
  /// records were dropped, then the surviving records in order.
  String export() {
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
    for (final r in _records) {
      buf.writeln(r.line);
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
