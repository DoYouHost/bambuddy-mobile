import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'variant_group.g.dart';

/// One candidate in a cross-model set (server #671): a library file already
/// sliced for a particular printer model, at a priority position.
///
/// The server declares this shape twice under two names —
/// `VariantGroupMemberResponse` (a member of a library variant group) and
/// `QueueVariantSummary` (a candidate on a queue item) — with the same four
/// fields and the same meaning. Parsed here once: a group's members become a
/// queue item's candidates verbatim when the group is queued, so a divergence
/// between the two would be a server bug, not a shape we need to model twice.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrintVariant {
  const PrintVariant({
    required this.libraryFileId,
    required this.filename,
    required this.targetModel,
    required this.position,
  });

  factory PrintVariant.fromJson(Map<String, dynamic> json) =>
      _$PrintVariantFromJson(json);

  final int libraryFileId;
  final String filename;

  /// Printer model this candidate is sliced for, normalised server-side
  /// (`P1S`, `X1C`, `H2C`…). Read from the file's own `sliced_for_model` unless
  /// the caller supplied one for a legacy 3MF that declares none.
  final String targetModel;

  /// Priority order within the set. Decides which candidate wins when more than
  /// one printer is idle at the same moment.
  final int position;
}

/// A library variant group: the same job sliced for different printers
/// (`VariantGroupResponse`).
///
/// Two members minimum — the server refuses a group of one, since it expresses
/// no choice.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class VariantGroup {
  const VariantGroup({
    required this.id,
    required this.name,
    this.members = const [],
  });

  factory VariantGroup.fromJson(Map<String, dynamic> json) =>
      _$VariantGroupFromJson(json);

  final int id;
  final String name;

  /// In priority order, as the server returned them.
  @JsonKey(fromJson: _membersFromJson)
  final List<PrintVariant> members;

  /// Models this group can reach, in priority order, for the one-line summary
  /// under a file row.
  List<String> get targetModels => [for (final m in members) m.targetModel];
}

List<PrintVariant> _membersFromJson(dynamic value) =>
    parseJsonList(value, PrintVariant.fromJson);
