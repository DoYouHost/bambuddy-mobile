import 'dart:convert';

/// Merges the UI stream with a background one onto a single timeline.
///
/// Each isolate has its own heap and its own clock-from-zero, so each file's `t`
/// counts from its own header `ts`. Sorting on raw `t` would interleave them
/// wrongly; everything is rebased onto the earliest of the two headers, which is
/// also the only origin that keeps every offset positive.
///
/// Records from [secondary] are stamped with `iso`, naming the stream they came
/// from. Without it the merge would erase the distinction it just created: the
/// merged header says `stream:"merged"`, and a `GET /printers/` from the service
/// is otherwise indistinguishable from one made by the UI — which is exactly the
/// bug this log has already caught once, both isolates polling at the same time.
/// The value comes from the secondary file's own header, so a third stream needs
/// no change here; the UI's records stay unstamped, being the majority.
///
/// Call it twice to fold in a third stream: the result keeps the earliest `ts`, so
/// the second pass shifts nothing that was already placed, and records already
/// stamped pass through untouched.
///
/// Anything unusable makes this return [primary] unchanged: a broken secondary
/// stream must not cost the user the log they actually recorded. That promise is
/// why the decoding below is defensive — these files are written by isolates the
/// system may kill mid-write, and a throw here would reach the user as an empty
/// report after five minutes of recording.
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

/// Puts one stream's records in the order things happened, header line first.
///
/// A file is in arrival order, and that is not the same order: a record stamped
/// with `LogStore.add`'s `at` — a tap, stamped with the moment the finger went
/// down — is written after events that happened later than it. `LogStore.export`
/// sorts its ring for exactly this reason, so a session read back from its file
/// has to do it too, or the report says a route change preceded the tap that
/// caused it. Ties keep arrival order, same sequence-number trick as
/// [mergeSessions].
///
/// Lines carrying no `t` are dropped, headers and torn last lines included —
/// same defensiveness, same reason. Input comes back unchanged when there is
/// nothing to order: no second line, or a first line that is not a header. A
/// file whose records are all unusable yields its header alone, which callers
/// read as "nothing here".
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
    // Every event carries `t` and no header does, so this is also what skips a
    // stray header — which is what a restarted background isolate can leave in
    // the middle of its own file. Taken for a record it would sort to the front
    // of the timeline with no source and no event name. Keyed on `t` rather than
    // on the presence of `session`, because every record must have a `t`, so this
    // test can never swallow a real one.
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
