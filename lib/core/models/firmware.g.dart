// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firmware.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirmwareUpdateInfo _$FirmwareUpdateInfoFromJson(Map<String, dynamic> json) =>
    FirmwareUpdateInfo(
      printerId: toIntOrNull(json['printer_id']),
      printerName: json['printer_name'] as String?,
      model: json['model'] as String?,
      currentVersion: json['current_version'] as String?,
      latestVersion: json['latest_version'] as String?,
      updateAvailable: json['update_available'] == null
          ? false
          : _toBoolOrFalse(json['update_available']),
      downloadUrl: json['download_url'] as String?,
      releaseNotes: json['release_notes'] as String?,
      availableVersions: _toAvailableVersionsOrNull(json['available_versions']),
    );

AvailableFirmwareVersion _$AvailableFirmwareVersionFromJson(
  Map<String, dynamic> json,
) => AvailableFirmwareVersion(
  version: json['version'] as String?,
  fileAvailable: json['file_available'] == null
      ? false
      : _toBoolOrFalse(json['file_available']),
  downloadUrl: json['download_url'] as String?,
  releaseNotes: json['release_notes'] as String?,
  releaseTime: json['release_time'] as String?,
);

FirmwareUpdatesResponse _$FirmwareUpdatesResponseFromJson(
  Map<String, dynamic> json,
) => FirmwareUpdatesResponse(
  updates: json['updates'] == null
      ? const []
      : _toUpdateListOrEmpty(json['updates']),
  updatesAvailable: toIntOrNull(json['updates_available']),
);

FirmwareUploadPrepare _$FirmwareUploadPrepareFromJson(
  Map<String, dynamic> json,
) => FirmwareUploadPrepare(
  canProceed: json['can_proceed'] == null
      ? false
      : _toBoolOrFalse(json['can_proceed']),
  sdCardPresent: json['sd_card_present'] == null
      ? false
      : _toBoolOrFalse(json['sd_card_present']),
  sdCardFreeSpace: toIntOrNull(json['sd_card_free_space']),
  firmwareSize: toIntOrNull(json['firmware_size']),
  spaceSufficient: json['space_sufficient'] == null
      ? false
      : _toBoolOrFalse(json['space_sufficient']),
  updateAvailable: json['update_available'] == null
      ? false
      : _toBoolOrFalse(json['update_available']),
  currentVersion: json['current_version'] as String?,
  latestVersion: json['latest_version'] as String?,
  targetVersion: json['target_version'] as String?,
  firmwareFilename: json['firmware_filename'] as String?,
  errors: json['errors'] == null
      ? const []
      : _toStringListOrEmpty(json['errors']),
);

FirmwareUploadStartResult _$FirmwareUploadStartResultFromJson(
  Map<String, dynamic> json,
) => FirmwareUploadStartResult(
  started: json['started'] == null ? false : _toBoolOrFalse(json['started']),
  message: json['message'] as String?,
);

FirmwareUploadStatus _$FirmwareUploadStatusFromJson(
  Map<String, dynamic> json,
) => FirmwareUploadStatus(
  status: json['status'] as String?,
  progress: toIntOrNull(json['progress']),
  message: json['message'] as String?,
  error: json['error'] as String?,
  firmwareFilename: json['firmware_filename'] as String?,
  firmwareVersion: json['firmware_version'] as String?,
);
