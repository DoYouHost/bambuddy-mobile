import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'firmware.g.dart';

/// Firmware information for a single printer from
/// `GET /firmware/updates/{printer_id}` and as list element from
/// `GET /firmware/updates`. Defensive parsing (pattern: [PrinterStatus]):
/// nullable fields, numbers/bools via tolerant converters.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUpdateInfo {
  const FirmwareUpdateInfo({
    this.printerId,
    this.printerName,
    this.model,
    this.currentVersion,
    this.latestVersion,
    this.updateAvailable = false,
    this.downloadUrl,
    this.releaseNotes,
    this.availableVersions,
  });

  factory FirmwareUpdateInfo.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUpdateInfoFromJson(json);

  /// Printer ID — for mapping to status/card. Tolerant parser; if server
  /// omits/breaks it, entry can still be skipped by provider.
  @JsonKey(fromJson: toIntOrNull)
  final int? printerId;

  final String? printerName;
  final String? model;

  /// Currently installed version; null if unknown.
  final String? currentVersion;

  /// Latest available version; null if server has no cloud data.
  final String? latestVersion;

  /// Whether server detected newer version than installed.
  @JsonKey(fromJson: toBoolOrFalse)
  final bool updateAvailable;

  final String? downloadUrl;
  final String? releaseNotes;

  /// Full version list for selection (for future update flow).
  @JsonKey(fromJson: _toAvailableVersionsOrNull)
  final List<AvailableFirmwareVersion>? availableVersions;

  /// Whether there is anything meaningful to display (at least current version).
  bool get hasVersion => currentVersion != null && currentVersion!.isNotEmpty;
}

/// Single firmware version from `available_versions` (for future update flow).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class AvailableFirmwareVersion {
  const AvailableFirmwareVersion({
    this.version,
    this.fileAvailable = false,
    this.downloadUrl,
    this.releaseNotes,
    this.releaseTime,
  });

  factory AvailableFirmwareVersion.fromJson(Map<String, dynamic> json) =>
      _$AvailableFirmwareVersionFromJson(json);

  final String? version;

  /// Whether firmware file is available for download/upload.
  @JsonKey(fromJson: toBoolOrFalse)
  final bool fileAvailable;

  final String? downloadUrl;
  final String? releaseNotes;
  final String? releaseTime;
}

/// Response from `GET /firmware/updates` — firmware for entire fleet in one call.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUpdatesResponse {
  const FirmwareUpdatesResponse({
    this.updates = const [],
    this.updatesAvailable,
  });

  factory FirmwareUpdatesResponse.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUpdatesResponseFromJson(json);

  @JsonKey(fromJson: _toUpdateListOrEmpty)
  final List<FirmwareUpdateInfo> updates;

  /// How many printers have updates available (for optional global badge).
  @JsonKey(fromJson: toIntOrNull)
  final int? updatesAvailable;
}

/// Models for FUTURE update execution (not yet in UI) — repository already
/// returns them, so higher layer will be ready without model changes.

/// `GET /firmware/updates/{id}/prepare` — can we upload firmware (SD, space)?
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUploadPrepare {
  const FirmwareUploadPrepare({
    this.canProceed = false,
    this.sdCardPresent = false,
    this.sdCardFreeSpace,
    this.firmwareSize,
    this.spaceSufficient = false,
    this.updateAvailable = false,
    this.currentVersion,
    this.latestVersion,
    this.targetVersion,
    this.firmwareFilename,
    this.errors = const [],
  });

  factory FirmwareUploadPrepare.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUploadPrepareFromJson(json);

  @JsonKey(fromJson: toBoolOrFalse)
  final bool canProceed;
  @JsonKey(fromJson: toBoolOrFalse)
  final bool sdCardPresent;
  @JsonKey(fromJson: toIntOrNull)
  final int? sdCardFreeSpace;
  @JsonKey(fromJson: toIntOrNull)
  final int? firmwareSize;
  @JsonKey(fromJson: toBoolOrFalse)
  final bool spaceSufficient;
  @JsonKey(fromJson: toBoolOrFalse)
  final bool updateAvailable;
  final String? currentVersion;
  final String? latestVersion;
  final String? targetVersion;
  final String? firmwareFilename;
  @JsonKey(fromJson: _toStringListOrEmpty)
  final List<String> errors;
}

/// `POST /firmware/updates/{id}/upload` — start firmware upload.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUploadStartResult {
  const FirmwareUploadStartResult({this.started = false, this.message});

  factory FirmwareUploadStartResult.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUploadStartResultFromJson(json);

  @JsonKey(fromJson: toBoolOrFalse)
  final bool started;
  final String? message;
}

/// `GET /firmware/updates/{id}/upload/status` — firmware upload progress.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUploadStatus {
  const FirmwareUploadStatus({
    this.status,
    this.progress,
    this.message,
    this.error,
    this.firmwareFilename,
    this.firmwareVersion,
  });

  factory FirmwareUploadStatus.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUploadStatusFromJson(json);

  /// Raw status from server (e.g. idle/uploading/done/error) — not enum-backed.
  final String? status;
  @JsonKey(fromJson: toIntOrNull)
  final int? progress;
  final String? message;
  final String? error;
  final String? firmwareFilename;
  final String? firmwareVersion;
}

List<FirmwareUpdateInfo> _toUpdateListOrEmpty(dynamic value) =>
    parseJsonList(value, FirmwareUpdateInfo.fromJson);

/// Null rather than empty: an absent list is a server that does not offer the
/// catalogue, an empty one is a printer with nothing to install, and the screen
/// says different things about the two.
List<AvailableFirmwareVersion>? _toAvailableVersionsOrNull(dynamic value) =>
    parseJsonListOrNull(value, AvailableFirmwareVersion.fromJson);

/// Private on purpose, next to `json_utils`'s [toStringList]: this one
/// stringifies whatever arrives, because the field carries printer-reported
/// module versions that have shown up as numbers. Unifying the two would change
/// what one of them parses.
List<String> _toStringListOrEmpty(dynamic value) {
  if (value is! List) return const [];
  return [for (final e in value) e.toString()];
}
