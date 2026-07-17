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
  createdAt: dateTimeFromJson(json['created_at']),
  startedAt: dateTimeFromJson(json['started_at']),
  completedAt: dateTimeFromJson(json['completed_at']),
  targetModel: json['target_model'] as String?,
  targetLocation: json['target_location'] as String?,
  filamentOverrides: (json['filament_overrides'] as List<dynamic>?)
      ?.map((e) => e as Map<String, dynamic>)
      .toList(),
  scheduledTime: dateTimeFromJson(json['scheduled_time']),
  requirePreviousSuccess: json['require_previous_success'] as bool? ?? false,
  autoOffAfter: json['auto_off_after'] as bool? ?? false,
  manualStart: json['manual_start'] as bool? ?? false,
  plateId: (json['plate_id'] as num?)?.toInt(),
  bedLevelling: json['bed_levelling'] as bool? ?? true,
  flowCali: json['flow_cali'] as bool? ?? false,
  vibrationCali: json['vibration_cali'] as bool? ?? true,
  layerInspect: json['layer_inspect'] as bool? ?? false,
  timelapse: json['timelapse'] as bool? ?? false,
  useAms: json['use_ams'] as bool? ?? true,
  nozzleOffsetCali: json['nozzle_offset_cali'] as bool? ?? true,
  preheatOverride: json['preheat_override'] as String? ?? 'inherit',
  preheatChamberTargetOverride:
      (json['preheat_chamber_target_override'] as num?)?.toInt(),
  gcodeInjection: json['gcode_injection'] as bool? ?? false,
  nozzleMapping: (json['nozzle_mapping'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  slicedForModel: json['sliced_for_model'] as String?,
);
