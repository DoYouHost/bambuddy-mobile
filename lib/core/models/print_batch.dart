import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'print_batch.g.dart';

/// `PrintBatch.status` — tolerant of values a newer server may add.
enum PrintBatchStatus { active, completed, cancelled, unknown }

/// One plate's share of an order (`PrintBatchPlateProgress`, server #342,
/// 1.2.5.3+). Only a batch with [PrintBatch.hasTargets] has any.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrintBatchPlate {
  const PrintBatchPlate({
    this.plateId,
    this.plateName,
    this.quantityTarget = 0,
    this.dispatched = 0,
    this.remaining = 0,
    this.pendingCount = 0,
    this.printingCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.actualCost,
    this.estimatedRemainingCost,
    this.printTimeSeconds = 0,
    this.canDispatch,
  });

  factory PrintBatchPlate.fromJson(Map<String, dynamic> json) =>
      _$PrintBatchPlateFromJson(json);

  /// Plate index inside the 3MF; null is a single-plate file ("whole file"),
  /// and a legitimate target of its own — not "no plate".
  final int? plateId;
  final String? plateName;

  @JsonKey(defaultValue: 0)
  final int quantityTarget;
  @JsonKey(defaultValue: 0)
  final int dispatched;

  /// Runs still owed: a failed run counts as owed again.
  @JsonKey(defaultValue: 0)
  final int remaining;
  @JsonKey(defaultValue: 0)
  final int pendingCount;
  @JsonKey(defaultValue: 0)
  final int printingCount;
  @JsonKey(defaultValue: 0)
  final int completedCount;
  @JsonKey(defaultValue: 0)
  final int failedCount;

  /// Measured from finished runs; null until one has produced a cost.
  final double? actualCost;
  final double? estimatedRemainingCost;
  @JsonKey(defaultValue: 0)
  final int printTimeSeconds;

  /// False when the plate owes runs but its last queue item is gone, so there
  /// is nothing to clone a new run from (#2960). Absent before 1.2.5.4 — null
  /// here, read by [dispatchable] as "try it".
  final bool? canDispatch;

  bool get dispatchable => remaining > 0 && (canDispatch ?? true);
}

/// `PrintBatchResponse` from `/queue/batches`.
///
/// Two generations share the route. A plain grouping (every server since
/// v0.2.3, and `POST /queue/` with `quantity > 1` still makes one) carries only
/// the per-status counts. An order (#342, 1.2.5.3+) adds targets, remaining
/// runs, costs and [plates]; [hasTargets] tells them apart, and an older
/// server simply omits every field of the second kind.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrintBatch {
  const PrintBatch({
    required this.id,
    required this.name,
    required this.status,
    this.archiveId,
    this.libraryFileId,
    this.quantity = 1,
    this.createdAt,
    this.completedAt,
    this.createdByUsername,
    this.projectId,
    this.dueDate,
    this.notes,
    this.externalSource,
    this.externalRef,
    this.pendingCount = 0,
    this.printingCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.cancelledCount = 0,
    this.skippedCount = 0,
    this.hasTargets = false,
    this.targetCount = 0,
    this.remainingCount = 0,
    this.dispatchableCount,
    this.actualCost,
    this.estimatedRemainingCost,
    this.filamentUsedGrams,
    this.printTimeSeconds = 0,
    this.plates = const [],
  });

  factory PrintBatch.fromJson(Map<String, dynamic> json) =>
      _$PrintBatchFromJson(json);

  final int id;
  final String name;

  @JsonKey(unknownEnumValue: PrintBatchStatus.unknown)
  final PrintBatchStatus status;

  final int? archiveId;
  final int? libraryFileId;

  /// Legacy display count: the copies of a grouping, or an order's target sum.
  @JsonKey(defaultValue: 1)
  final int quantity;

  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? createdAt;
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? completedAt;
  final String? createdByUsername;

  final int? projectId;

  /// An instant, not a calendar date: the column is a datetime, and the app
  /// writes the end of the picked day (see `BatchRepository.update`).
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? dueDate;
  final String? notes;

  /// The integration that created the batch and its record there (a shop
  /// order number), 1.2.6+. Always both or neither — the server refuses one
  /// without the other.
  final String? externalSource;
  final String? externalRef;

  @JsonKey(defaultValue: 0)
  final int pendingCount;
  @JsonKey(defaultValue: 0)
  final int printingCount;
  @JsonKey(defaultValue: 0)
  final int completedCount;
  @JsonKey(defaultValue: 0)
  final int failedCount;
  @JsonKey(defaultValue: 0)
  final int cancelledCount;
  @JsonKey(defaultValue: 0)
  final int skippedCount;

  @JsonKey(defaultValue: false)
  final bool hasTargets;
  @JsonKey(defaultValue: 0)
  final int targetCount;
  @JsonKey(defaultValue: 0)
  final int remainingCount;

  /// Of [remainingCount], the runs that can actually be queued (#2960, 1.2.5.4).
  /// Null before it; [dispatchable] then assumes all of them.
  final int? dispatchableCount;

  final double? actualCost;
  final double? estimatedRemainingCost;
  final double? filamentUsedGrams;
  @JsonKey(defaultValue: 0)
  final int printTimeSeconds;

  @JsonKey(defaultValue: <PrintBatchPlate>[])
  final List<PrintBatchPlate> plates;

  /// Runs a dispatch would queue now — zero for a grouping, which owes nothing.
  int get dispatchable =>
      hasTargets ? (dispatchableCount ?? remainingCount) : 0;

  /// Runs the order owes that nothing can produce any more (#2960).
  int get stranded => hasTargets ? remainingCount - dispatchable : 0;

  /// What progress is measured against: the target for an order, and what
  /// happened to be queued for a grouping — the web's denominator.
  int get progressTotal => hasTargets
      ? targetCount
      : completedCount + pendingCount + printingCount + failedCount;

  bool isOverdue(DateTime now) =>
      status == PrintBatchStatus.active &&
      dueDate != null &&
      dueDate!.isBefore(now);
}
