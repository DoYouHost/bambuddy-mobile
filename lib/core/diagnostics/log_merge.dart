import 'dart:convert';

/// Merges the UI and foreground-service streams onto one timeline.
///
/// The two isolates have separate heaps and separate clocks-from-zero, so each
/// file's `t` counts from its own header `ts`. Sorting on raw `t` would
/// interleave them wrongly; everything is rebased onto the earliest of the two
/// headers, which is also the only origin that keeps every offset positive.
///
/// Anything unparseable makes this return [primary] unchanged: a broken
/// secondary stream must not cost the user the log they actually recorded.
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

  final origin = primaryTs.isBefore(secondaryTs) ? primaryTs : secondaryTs;
  final rebased = [
    ..._rebase(primaryLines.skip(1), primaryTs.difference(origin).inMilliseconds),
    ..._rebase(
      secondaryLines.skip(1),
      secondaryTs.difference(origin).inMilliseconds,
    ),
  ];

  // Sequence assigned across both streams at once, so a tie resolves to
  // primary-then-secondary. Dart's sort is not stable on its own, and without
  // the tiebreak records sharing a millisecond would shuffle.
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

List<String> _lines(String jsonl) =>
    const LineSplitter().convert(jsonl).where((l) => l.trim().isNotEmpty).toList();

Map<String, Object?>? _decode(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Iterable<(int, String)> _rebase(Iterable<String> lines, int shiftMs) sync* {
  for (final line in lines) {
    final record = _decode(line);
    if (record == null) continue;
    final t = ((record['t'] as num?) ?? 0).toInt() + shiftMs;
    // Re-encode only when the offset actually moved, so an unshifted stream's
    // lines come through byte-identical.
    yield (t, shiftMs == 0 ? line : jsonEncode(record..['t'] = t));
  }
}

class _Timed {
  const _Timed(this.t, this.seq, this.line);

  final int t;
  final int seq;
  final String line;
}
