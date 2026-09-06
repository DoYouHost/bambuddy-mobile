import 'dart:convert';

import 'log_event.dart';

/// A parsed session, ready for the review screen.
///
/// The review is mandatory before anything is sent, and nobody reviews raw
/// JSONL honestly — so the screen renders this instead: what the session
/// contains, in what order, with the raw text one tap away.
class LogSummary {
  const LogSummary({
    required this.header,
    required this.lines,
    required this.bySource,
    required this.warnings,
    required this.errors,
    required this.markers,
    required this.truncated,
  });

  factory LogSummary.parse(String jsonl) {
    final rows = <Map<String, Object?>>[];
    for (final raw in const LineSplitter().convert(jsonl)) {
      if (raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) rows.add(decoded);
      } on FormatException {
        // A half-written last line is expected when a session is read off disk
        // after a kill; drop it rather than failing the whole review.
        continue;
      }
    }
    if (rows.isEmpty) return LogSummary.empty;

    // The header is the only row without `t`.
    final header = rows.first.containsKey('t')
        ? const <String, Object?>{}
        : rows.first;
    final body = rows.first.containsKey('t') ? rows : rows.skip(1);

    final lines = <LogLine>[];
    final bySource = <String, int>{};
    var warnings = 0;
    var errors = 0;
    var markers = 0;
    var truncated = false;

    for (final row in body) {
      final line = LogLine.fromJson(row);
      lines.add(line);
      bySource.update(line.src, (n) => n + 1, ifAbsent: () => 1);
      switch (line.lvl) {
        case 'warn':
          warnings++;
        case 'error':
          errors++;
      }
      if (line.evt == 'user_marker') markers++;
      if (line.evt == 'truncated') truncated = true;
    }

    return LogSummary(
      header: header,
      lines: lines,
      bySource: bySource,
      warnings: warnings,
      errors: errors,
      markers: markers,
      truncated: truncated,
    );
  }

  static const empty = LogSummary(
    header: {},
    lines: [],
    bySource: {},
    warnings: 0,
    errors: 0,
    markers: 0,
    truncated: false,
  );

  final Map<String, Object?> header;
  final List<LogLine> lines;

  /// Record count per `src`, ordered by the enum so the chips do not reshuffle
  /// between sessions.
  final Map<String, int> bySource;

  final int warnings;
  final int errors;
  final int markers;

  /// Whether records were dropped to stay inside the buffer caps.
  final bool truncated;

  bool get isEmpty => lines.isEmpty;

  /// Sources in [LogSource] order, skipping the ones this session never used.
  List<MapEntry<String, int>> get sourceCounts => [
    for (final source in LogSource.values)
      if (bySource[source.name] != null)
        MapEntry(source.name, bySource[source.name]!),
  ];
}

/// One record, with the record's own keys split from the extra fields so the
/// screen can lay them out differently.
class LogLine {
  const LogLine({
    required this.t,
    required this.src,
    required this.evt,
    this.lvl,
    this.iso,
    this.fields = const {},
  });

  factory LogLine.fromJson(Map<String, Object?> row) => LogLine(
    t: ((row['t'] as num?) ?? 0).toInt(),
    src: '${row['src'] ?? '?'}',
    evt: '${row['evt'] ?? '?'}',
    lvl: row['lvl'] as String?,
    iso: row['iso'] as String?,
    fields: {
      for (final e in row.entries)
        if (!LogEvent.reservedKeys.contains(e.key)) e.key: e.value,
    },
  );

  final int t;
  final String src;
  final String evt;
  final String? lvl;

  /// Which isolate wrote this, for records that did not come from the UI —
  /// `fgs` or `action`, stamped by `mergeSessions`, null for the UI's own.
  ///
  /// A field of its own rather than one of [fields]: `iso` is a reserved key, so
  /// it is excluded there, and it is the only thing that tells an HTTP call made
  /// by the background service from the identical-looking one made by the UI.
  final String? iso;

  final Map<String, Object?> fields;

  bool get isError => lvl == 'error';
  bool get isWarning => lvl == 'warn';
  bool get isMarker => evt == 'user_marker';

  /// `status=502 · ms=1204`, for the second line of a row.
  String get detail =>
      [for (final e in fields.entries) '${e.key}=${e.value}'].join(' · ');

  /// `m:ss.d` since the session started.
  String get offset {
    final seconds = t / 1000;
    final minutes = seconds ~/ 60;
    final rest = (seconds - minutes * 60).toStringAsFixed(1).padLeft(4, '0');
    return '$minutes:$rest';
  }
}
