import 'dart:convert';

/// Merges the UI stream with a background one onto a single timeline, rebasing
/// and stamping `iso` as described in `docs/diagnostics-log.md`. The UI's own
/// records stay unstamped, being the majority.
///
/// Call it twice to fold in a third stream: the result keeps the earliest `ts`,
/// so the second pass shifts nothing already placed.
///
/// Anything unusable returns [primary] unchanged — a broken secondary stream
/// must not cost the user the log they actually recorded. That promise is why
/// the decoding below is defensive: these files are written by isolates the
/// system may kill mid-write.
String mergeSessions(String primary, String secondary) {
  final primaryLines = _lines(primary);
  final secondaryLines = _lines(secondary);
  if (primaryLines.isEmpty) return primary;
  // A header with no records carries nothing worth merging.
  if (secondaryLines.length < 2) return primary;

  final primaryHeader = _decode(primaryLines.first);
  final secondaryHeader = _decode(secondaryLines.first);
  if (primaryHeader == null || secondaryHeader == null) return primary;

  final primaryTs = DateTime.tryParse('${primaryHeader['ts']}');
  final secondaryTs = DateTime.tryParse('${secondaryHeader['ts']}');
  if (primaryTs == null || secondaryTs == null) return primary;

  // Whatever the secondary file calls itself. A missing or unrecognised name
  // leaves records unstamped rather than claiming an origin we cannot back up.
  final secondaryIso = switch (secondaryHeader['stream']) {
    final String stream when stream.isNotEmpty && stream != 'ui' => stream,
    _ => null,
  };

  final origin = primaryTs.isBefore(secondaryTs) ? primaryTs : secondaryTs;
  final rebased = [
    ..._rebase(
      primaryLines.skip(1),
      primaryTs.difference(origin).inMilliseconds,
      null,
    ),
    ..._rebase(
      secondaryLines.skip(1),
      secondaryTs.difference(origin).inMilliseconds,
      secondaryIso,
    ),
  ];

  // Sequence assigned across both streams at once, so a tie resolves to
  // primary-then-secondary. Dart's sort is not stable on its own.
  final records = [
    for (var i = 0; i < rebased.length; i++)
      _Timed(rebased[i].$1, i, rebased[i].$2),
  ]..sort((a, b) => a.t != b.t ? a.t.compareTo(b.t) : a.seq.compareTo(b.seq));

  final header = Map<String, Object?>.from(primaryHeader)
    ..['ts'] = origin.toUtc().toIso8601String()
    ..['stream'] = 'merged';

  final buf = StringBuffer()..writeln(jsonEncode(header));
  for (final record in records) {
    buf.writeln(record.line);
  }
  return buf.toString();
}

/// Puts one stream's records in the order things happened, header line first.
/// A file is in arrival order, which is not the same — `LogStore.export` sorts
/// its ring for this reason, so a session read back from its file must too, or
/// the report says a route change preceded the tap that caused it.
///
/// Lines carrying no `t` are dropped, headers and torn last lines included.
/// Input comes back unchanged when there is nothing to order; a file whose
/// records are all unusable yields its header alone, which callers read as
/// "nothing here".
String orderSession(String jsonl) {
  final lines = _lines(jsonl);
  if (lines.length < 2) return jsonl;
  if (_decode(lines.first) == null) return jsonl;

  final records = <_Timed>[];
  for (final line in lines.skip(1)) {
    final t = _decode(line)?['t'];
    if (t is! num) continue;
    records.add(_Timed(t.toInt(), records.length, line));
  }
  records.sort((a, b) => a.t != b.t ? a.t.compareTo(b.t) : a.seq.compareTo(b.seq));

  final buf = StringBuffer()..writeln(lines.first);
  for (final record in records) {
    buf.writeln(record.line);
  }
  return buf.toString();
}

List<String> _lines(String jsonl) =>
    const LineSplitter().convert(jsonl).where((l) => l.trim().isNotEmpty).toList();

Map<String, Object?>? _decode(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    // Not only `FormatException`: a line that decodes to a map with unexpected
    // key types throws on the cast, and one odd line must not cost the log.
    return null;
  }
}

Iterable<(int, String)> _rebase(
  Iterable<String> lines,
  int shiftMs,
  String? iso,
) sync* {
  for (final line in lines) {
    final record = _decode(line);
    if (record == null) continue;
    // Every event carries `t` and no header does, so this also skips the stray
    // header a restarted background isolate can leave mid-file — taken for a
    // record it would sort to the front with no source and no event name.
    final t = record['t'];
    if (t is! num) continue;
    // An unshifted, unstamped stream comes through byte-identical.
    if (shiftMs == 0 && iso == null) {
      yield (t.toInt(), line);
      continue;
    }
    final shifted = t.toInt() + shiftMs;
    record['t'] = shifted;
    if (iso != null) record['iso'] = iso;
    yield (shifted, jsonEncode(record));
  }
}

class _Timed {
  const _Timed(this.t, this.seq, this.line);

  final int t;
  final int seq;
  final String line;
}
