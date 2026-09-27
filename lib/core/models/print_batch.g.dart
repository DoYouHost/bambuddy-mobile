// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'print_batch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PrintBatchPlate _$PrintBatchPlateFromJson(Map<String, dynamic> json) =>
    PrintBatchPlate(
      plateId: (json['plate_id'] as num?)?.toInt(),
      plateName: json['plate_name'] as String?,
      quantityTarget: (json['quantity_target'] as num?)?.toInt() ?? 0,
      dispatched: (json['dispatched'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      printingCount: (json['printing_count'] as num?)?.toInt() ?? 0,
      completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      actualCost: (json['actual_cost'] as num?)?.toDouble(),
      estimatedRemainingCost: (json['estimated_remaining_cost'] as num?)
          ?.toDouble(),
      printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt() ?? 0,
      canDispatch: json['can_dispatch'] as bool?,
    );

PrintBatch _$PrintBatchFromJson(Map<String, dynamic> json) => PrintBatch(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  status: $enumDecode(
    _$PrintBatchStatusEnumMap,
    json['status'],
    unknownValue: PrintBatchStatus.unknown,
  ),
  archiveId: (json['archive_id'] as num?)?.toInt(),
  libraryFileId: (json['library_file_id'] as num?)?.toInt(),
  quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  createdAt: dateTimeFromJson(json['created_at']),
  completedAt: dateTimeFromJson(json['completed_at']),
  createdById: (json['created_by_id'] as num?)?.toInt(),
  createdByUsername: json['created_by_username'] as String?,
  projectId: (json['project_id'] as num?)?.toInt(),
  dueDate: dateTimeFromJson(json['due_date']),
  notes: json['notes'] as String?,
  externalSource: json['external_source'] as String?,
  externalRef: json['external_ref'] as String?,
  pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
  printingCount: (json['printing_count'] as num?)?.toInt() ?? 0,
  completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
  failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
  cancelledCount: (json['cancelled_count'] as num?)?.toInt() ?? 0,
  skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
  hasTargets: json['has_targets'] as bool? ?? false,
  targetCount: (json['target_count'] as num?)?.toInt() ?? 0,
  remainingCount: (json['remaining_count'] as num?)?.toInt() ?? 0,
  dispatchableCount: (json['dispatchable_count'] as num?)?.toInt(),
  actualCost: (json['actual_cost'] as num?)?.toDouble(),
  estimatedRemainingCost: (json['estimated_remaining_cost'] as num?)
      ?.toDouble(),
  filamentUsedGrams: (json['filament_used_grams'] as num?)?.toDouble(),
  printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt() ?? 0,
  plates:
      (json['plates'] as List<dynamic>?)
          ?.map((e) => PrintBatchPlate.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

const _$PrintBatchStatusEnumMap = {
  PrintBatchStatus.active: 'active',
  PrintBatchStatus.completed: 'completed',
  PrintBatchStatus.cancelled: 'cancelled',
  PrintBatchStatus.unknown: 'unknown',
};
