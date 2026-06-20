import 'package:json_annotation/json_annotation.dart';

part 'firmware.g.dart';

/// Informacja o oprogramowaniu (firmware) jednej drukarki z
/// `GET /firmware/updates/{printer_id}` oraz jako element listy z
/// `GET /firmware/updates`. Parsowanie defensywne (wzorzec [PrinterStatus]):
/// pola nullable, liczby/boole przez tolerancyjne konwertery.
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

  /// Id drukarki — do mapowania na status/kartę. Tolerancyjny parser, bo gdyby
  /// serwer go pominął/zepsuł, wpis i tak da się pominąć po stronie providera.
  @JsonKey(fromJson: _toIntOrNull)
  final int? printerId;

  final String? printerName;
  final String? model;

  /// Wersja aktualnie zainstalowana na drukarce; null gdy nieznana.
  final String? currentVersion;

  /// Najnowsza dostępna wersja; null gdy serwer nie ma danych z chmury.
  final String? latestVersion;

  /// Czy serwer wykrył nowszą wersję niż zainstalowana.
  @JsonKey(fromJson: _toBoolOrFalse)
  final bool updateAvailable;

  final String? downloadUrl;
  final String? releaseNotes;

  /// Pełna lista wersji do wyboru (do przyszłego flow wykonania aktualizacji).
  @JsonKey(fromJson: _toAvailableVersionsOrNull)
  final List<AvailableFirmwareVersion>? availableVersions;

  /// Czy mamy cokolwiek sensownego do pokazania (przynajmniej bieżącą wersję).
  bool get hasVersion => currentVersion != null && currentVersion!.isNotEmpty;
}

/// Pojedyncza wersja firmware z `available_versions` (na przyszłość — wybór
/// wersji przy wykonywaniu aktualizacji).
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

  /// Czy plik firmware jest dostępny do pobrania/wgrania.
  @JsonKey(fromJson: _toBoolOrFalse)
  final bool fileAvailable;

  final String? downloadUrl;
  final String? releaseNotes;
  final String? releaseTime;
}

/// Odpowiedź `GET /firmware/updates` — firmware dla całej farmy jednym zapytaniem.
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

  /// Ile drukarek ma dostępną aktualizację (do ewentualnego badge'a globalnego).
  @JsonKey(fromJson: _toIntOrNull)
  final int? updatesAvailable;
}

// --- Modele pod PRZYSZŁE wykonywanie aktualizacji (jeszcze nie w UI) ---
// Repozytorium już je zwraca, więc warstwa wyżej będzie gotowa bez zmian modelu.

/// `GET /firmware/updates/{id}/prepare` — czy można wgrać firmware (SD, miejsce).
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

  @JsonKey(fromJson: _toBoolOrFalse)
  final bool canProceed;
  @JsonKey(fromJson: _toBoolOrFalse)
  final bool sdCardPresent;
  @JsonKey(fromJson: _toIntOrNull)
  final int? sdCardFreeSpace;
  @JsonKey(fromJson: _toIntOrNull)
  final int? firmwareSize;
  @JsonKey(fromJson: _toBoolOrFalse)
  final bool spaceSufficient;
  @JsonKey(fromJson: _toBoolOrFalse)
  final bool updateAvailable;
  final String? currentVersion;
  final String? latestVersion;
  final String? targetVersion;
  final String? firmwareFilename;
  @JsonKey(fromJson: _toStringListOrEmpty)
  final List<String> errors;
}

/// `POST /firmware/updates/{id}/upload` — start wgrywania firmware.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FirmwareUploadStartResult {
  const FirmwareUploadStartResult({this.started = false, this.message});

  factory FirmwareUploadStartResult.fromJson(Map<String, dynamic> json) =>
      _$FirmwareUploadStartResultFromJson(json);

  @JsonKey(fromJson: _toBoolOrFalse)
  final bool started;
  final String? message;
}

/// `GET /firmware/updates/{id}/upload/status` — postęp wgrywania firmware.
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

  /// Surowy stan z serwera (np. idle/uploading/done/error) — nie enumujemy.
  final String? status;
  @JsonKey(fromJson: _toIntOrNull)
  final int? progress;
  final String? message;
  final String? error;
  final String? firmwareFilename;
  final String? firmwareVersion;
}

int? _toIntOrNull(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

bool _toBoolOrFalse(dynamic value) => switch (value) {
      bool b => b,
      num n => n != 0,
      String s => s.toLowerCase() == 'true' || s == '1',
      _ => false,
    };

List<FirmwareUpdateInfo> _toUpdateListOrEmpty(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final e in value)
      if (e is Map) FirmwareUpdateInfo.fromJson(Map<String, dynamic>.from(e)),
  ];
}

List<AvailableFirmwareVersion>? _toAvailableVersionsOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map)
        AvailableFirmwareVersion.fromJson(Map<String, dynamic>.from(e)),
  ];
}

List<String> _toStringListOrEmpty(dynamic value) {
  if (value is! List) return const [];
  return [for (final e in value) e.toString()];
}
