import 'package:app_util/app_util.dart';

import 'json_utils.dart';

/// Why a group of duplicate archives is not merged, as the server spells it
/// (`services/archive_merge.py`, `SKIPPED_*`, plus `not_a_group` from the merge
/// itself). Kept raw on the group: a reason this build does not know still
/// leaves the group out, it only has no sentence.
enum ArchiveMergeSkip {
  busy('busy'),
  conflictingFiles('conflicting_files'),
  failed('failed'),
  notAGroup('not_a_group');

  const ArchiveMergeSkip(this.wire);

  final String wire;

  static ArchiveMergeSkip? fromWire(Object? value) =>
      enumByWire(values, value, (v) => v.wire);
}

/// One archive of a duplicate group (`merge-preview`'s `brief`).
class ArchiveMergeMember {
  const ArchiveMergeMember({
    required this.id,
    required this.name,
    this.createdAt,
    this.runCount = 0,
  });

  static ArchiveMergeMember? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = toIntOrNull(json['id']);
    if (id == null) return null;
    return ArchiveMergeMember(
      id: id,
      name:
          toStringOrNull(json['print_name']) ??
          toStringOrNull(json['filename']) ??
          '#$id',
      createdAt: dateTimeFromJson(json['created_at']),
      runCount: toIntOrNull(json['run_count']) ?? 0,
    );
  }

  final int id;
  final String name;
  final DateTime? createdAt;
  final int runCount;
}

/// Archives that hold the same file, owner and project: [survivor] is the
/// oldest and stays, [merged] go into it. [skipped] non-null is a group the
/// server leaves out for now, with why ([skipReason] when this build knows it).
class ArchiveMergeGroup {
  const ArchiveMergeGroup({
    required this.survivor,
    this.merged = const [],
    this.skipped,
  });

  static ArchiveMergeGroup? tryParse(Object? json) {
    if (json is! Map) return null;
    final survivor = ArchiveMergeMember.tryParse(json['survivor']);
    if (survivor == null) return null;
    return ArchiveMergeGroup(
      survivor: survivor,
      merged: [
        if (json['merged'] case final List rows)
          for (final row in rows) ?ArchiveMergeMember.tryParse(row),
      ],
      skipped: toStringOrNull(json['skipped']),
    );
  }

  final ArchiveMergeMember survivor;
  final List<ArchiveMergeMember> merged;
  final String? skipped;

  bool get mergeable => skipped == null;
  ArchiveMergeSkip? get skipReason => ArchiveMergeSkip.fromWire(skipped);
}

/// What `POST /archives/merge` did: the groups merged, and those it left out
/// with why. One group failing leaves the others merged.
class ArchiveMergeResult {
  const ArchiveMergeResult({this.merged = const [], this.skipped = const []});

  factory ArchiveMergeResult.fromJson(Map<String, dynamic> json) =>
      ArchiveMergeResult(
        merged: [
          if (json['merged'] case final List rows)
            for (final row in rows.whereType<Map>())
              ?toIntOrNull(row['survivor_id']),
        ],
        skipped: [
          if (json['skipped'] case final List rows)
            for (final row in rows.whereType<Map>())
              if (toIntOrNull(row['survivor_id']) case final id?)
                (survivorId: id, reason: toStringOrNull(row['reason'])),
        ],
      );

  /// The survivor of each group merged.
  final List<int> merged;
  final List<({int survivorId, String? reason})> skipped;
}
