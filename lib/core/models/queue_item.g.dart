// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'queue_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QueueItem _$QueueItemFromJson(Map<String, dynamic> json) => QueueItem(
  id: (json['id'] as num).toInt(),
  position: (json['position'] as num).toInt(),
  status: json['status'] as String,
  printerId: (json['printer_id'] as num?)?.toInt(),
  archiveId: (json['archive_id'] as num?)?.toInt(),
  libraryFileId: (json['library_file_id'] as num?)?.toInt(),
  archiveName: json['archive_name'] as String?,
  archiveThumbnail: json['archive_thumbnail'] as String?,
  archiveDeleted: json['archive_deleted'] as bool? ?? false,
  libraryFileName: json['library_file_name'] as String?,
  libraryFileThumbnail: json['library_file_thumbnail'] as String?,
  printerName: json['printer_name'] as String?,
  printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt(),
  filamentUsedGrams: (json['filament_used_grams'] as num?)?.toDouble(),
  filamentType: json['filament_type'] as String?,
  filamentColor: json['filament_color'] as String?,
  amsMapping: (json['ams_mapping'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  beenJumped: json['been_jumped'] as bool? ?? false,
  errorMessage: json['error_message'] as String?,
  waitingReason: json['waiting_reason'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
  completedAt: json['completed_at'] == null
      ? null
      : DateTime.parse(json['completed_at'] as String),
);
