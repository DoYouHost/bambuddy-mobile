// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectListResponse _$ProjectListResponseFromJson(Map<String, dynamic> json) =>
    ProjectListResponse(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String?,
      color: json['color'] as String?,
      status: json['status'] as String? ?? 'active',
      targetCount: toIntOrNull(json['target_count']),
      targetPartsCount: toIntOrNull(json['target_parts_count']),
      budget: toDoubleOrNull(json['budget']),
      createdAt: json['created_at'] as String?,
      archiveCount: json['archive_count'] == null
          ? 0
          : toInt(json['archive_count']),
      totalItems: json['total_items'] == null ? 0 : toInt(json['total_items']),
      completedCount: json['completed_count'] == null
          ? 0
          : toInt(json['completed_count']),
      failedCount: json['failed_count'] == null
          ? 0
          : toInt(json['failed_count']),
      queueCount: json['queue_count'] == null ? 0 : toInt(json['queue_count']),
      progressPercent: toDoubleOrNull(json['progress_percent']),
      url: json['url'] as String?,
      coverImageFilename: json['cover_image_filename'] as String?,
      archives: json['archives'] == null
          ? const []
          : _archivesFromJson(json['archives']),
    );

ArchivePreview _$ArchivePreviewFromJson(Map<String, dynamic> json) =>
    ArchivePreview(
      id: (json['id'] as num).toInt(),
      printName: json['print_name'] as String?,
      thumbnailPath: json['thumbnail_path'] as String?,
      status: json['status'] as String?,
      filamentType: json['filament_type'] as String?,
      filamentColor: json['filament_color'] as String?,
    );

ProjectChildPreview _$ProjectChildPreviewFromJson(Map<String, dynamic> json) =>
    ProjectChildPreview(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      color: json['color'] as String?,
      status: json['status'] as String? ?? 'active',
      progressPercent: toDoubleOrNull(json['progress_percent']),
    );

ProjectStats _$ProjectStatsFromJson(Map<String, dynamic> json) => ProjectStats(
  totalArchives: json['total_archives'] == null
      ? 0
      : toInt(json['total_archives']),
  totalItems: json['total_items'] == null ? 0 : toInt(json['total_items']),
  completedPrints: json['completed_prints'] == null
      ? 0
      : toInt(json['completed_prints']),
  failedPrints: json['failed_prints'] == null
      ? 0
      : toInt(json['failed_prints']),
  queuedPrints: json['queued_prints'] == null
      ? 0
      : toInt(json['queued_prints']),
  inProgressPrints: json['in_progress_prints'] == null
      ? 0
      : toInt(json['in_progress_prints']),
  totalPrintTimeHours: json['total_print_time_hours'] == null
      ? 0
      : toDouble(json['total_print_time_hours']),
  totalFilamentGrams: json['total_filament_grams'] == null
      ? 0
      : toDouble(json['total_filament_grams']),
  progressPercent: toDoubleOrNull(json['progress_percent']),
  partsProgressPercent: toDoubleOrNull(json['parts_progress_percent']),
  estimatedCost: json['estimated_cost'] == null
      ? 0
      : toDouble(json['estimated_cost']),
  totalEnergyKwh: json['total_energy_kwh'] == null
      ? 0
      : toDouble(json['total_energy_kwh']),
  totalEnergyCost: json['total_energy_cost'] == null
      ? 0
      : toDouble(json['total_energy_cost']),
  remainingPrints: toIntOrNull(json['remaining_prints']),
  remainingParts: toIntOrNull(json['remaining_parts']),
  bomTotalItems: json['bom_total_items'] == null
      ? 0
      : toInt(json['bom_total_items']),
  bomCompletedItems: json['bom_completed_items'] == null
      ? 0
      : toInt(json['bom_completed_items']),
  bomCost: json['bom_cost'] == null ? 0 : toDouble(json['bom_cost']),
);

ProjectResponse _$ProjectResponseFromJson(Map<String, dynamic> json) =>
    ProjectResponse(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String?,
      color: json['color'] as String?,
      status: json['status'] as String? ?? 'active',
      targetCount: toIntOrNull(json['target_count']),
      targetPartsCount: toIntOrNull(json['target_parts_count']),
      notes: json['notes'] as String?,
      attachments: json['attachments'] == null
          ? const []
          : _attachmentsFromJson(json['attachments']),
      tags: json['tags'] as String?,
      dueDate: json['due_date'] as String?,
      priority: json['priority'] as String? ?? 'normal',
      budget: toDoubleOrNull(json['budget']),
      isTemplate: json['is_template'] as bool? ?? false,
      templateSourceId: (json['template_source_id'] as num?)?.toInt(),
      parentId: (json['parent_id'] as num?)?.toInt(),
      parentName: json['parent_name'] as String?,
      children: json['children'] == null
          ? const []
          : _childrenFromJson(json['children']),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      stats: json['stats'] == null
          ? null
          : ProjectStats.fromJson(json['stats'] as Map<String, dynamic>),
      url: json['url'] as String?,
      coverImageFilename: json['cover_image_filename'] as String?,
    );

BomItem _$BomItemFromJson(Map<String, dynamic> json) => BomItem(
  id: (json['id'] as num).toInt(),
  projectId: (json['project_id'] as num).toInt(),
  name: json['name'] as String,
  quantityNeeded: json['quantity_needed'] == null
      ? 1
      : toInt(json['quantity_needed']),
  quantityAcquired: json['quantity_acquired'] == null
      ? 0
      : toInt(json['quantity_acquired']),
  unitPrice: toDoubleOrNull(json['unit_price']),
  sourcingUrl: json['sourcing_url'] as String?,
  archiveId: (json['archive_id'] as num?)?.toInt(),
  archiveName: json['archive_name'] as String?,
  stlFilename: json['stl_filename'] as String?,
  remarks: json['remarks'] as String?,
  sortOrder: json['sort_order'] == null ? 0 : toInt(json['sort_order']),
  isComplete: json['is_complete'] as bool? ?? false,
);

TimelineEvent _$TimelineEventFromJson(Map<String, dynamic> json) =>
    TimelineEvent(
      eventType: json['event_type'] as String? ?? '',
      timestamp: json['timestamp'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
