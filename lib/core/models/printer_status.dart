import 'package:json_annotation/json_annotation.dart';

part 'printer_status.g.dart';

/// Status drukarki z `GET /printers/{id}/status` (i docelowo z ramek WS
/// `printer_status` w M2). Centralne DTO — tu obowiązuje wzorzec
/// parsowania defensywnego: pola nullable, liczby przez konwertery
/// tolerujące int/double/string, nieznane klucze ignorowane,
/// nigdy `!` na danych z serwera.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrinterStatus {
  const PrinterStatus({
    required this.id,
    this.name,
    this.connected,
    this.state,
    this.currentPrint,
    this.gcodeFile,
    this.progress,
    this.remainingTime,
    this.layerNum,
    this.totalLayers,
    this.temperatures,
    this.coverUrl,
    this.stgCurName,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) =>
      _$PrinterStatusFromJson(json);

  final int id;
  final String? name;
  final bool? connected;

  /// Surowy stan z serwera (np. RUNNING/IDLE/FAILED) — nie enumujemy,
  /// żeby nowe wartości nie wywalały parsera.
  final String? state;
  final String? currentPrint;
  final String? gcodeFile;

  /// Postęp w procentach 0–100.
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? progress;

  /// Pozostały czas w minutach.
  @JsonKey(fromJson: _toIntOrNull)
  final int? remainingTime;

  @JsonKey(fromJson: _toIntOrNull)
  final int? layerNum;

  @JsonKey(fromJson: _toIntOrNull)
  final int? totalLayers;

  /// Klucze nieudokumentowane po stronie serwera (zwykle nozzle/bed/
  /// chamber) — renderujemy co przyjdzie, nie zakładamy zestawu.
  @JsonKey(fromJson: _toTemperaturesOrNull)
  final Map<String, double>? temperatures;

  /// Ścieżka do okładki bieżącego wydruku (np. `/api/v1/printers/1/cover`).
  /// Wymaga tokenu strumienia kamery jako `?token=` przy pobieraniu.
  final String? coverUrl;

  /// Nazwa bieżącego etapu z serwera (np. „Auto bed leveling", „Heating");
  /// null/pusta poza fazą przygotowania. Przychodzi po angielsku.
  final String? stgCurName;

  /// Czy trwa zadanie wydruku — w tym fazy przygotowania (nagrzewanie,
  /// auto bed leveling, pauza), gdzie `progress`/`remainingTime` bywają
  /// zerowe, a serwer i tak raportuje aktywny stan. Fallback na dane
  /// postępu, gdy serwer nie poda stanu.
  bool get isPrinting {
    switch (state?.toUpperCase()) {
      case 'RUNNING':
      case 'PREPARE':
      case 'PAUSE':
      case 'PAUSED':
        return true;
      case 'IDLE':
      case 'FINISH':
      case 'FINISHED':
      case 'FAILED':
        return false;
    }
    return (progress ?? 0) > 0 && (remainingTime ?? 0) > 0;
  }

  /// Faza przygotowania: aktywny wydruk, ale jeszcze bez realnego postępu —
  /// wtedy w UI pokazujemy nazwę etapu zamiast paska 0%.
  bool get isPreparing => isPrinting && (progress ?? 0) <= 0;
}

double? _toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? _toIntOrNull(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

Map<String, double>? _toTemperaturesOrNull(dynamic value) {
  if (value is! Map) return null;
  final out = <String, double>{};
  for (final entry in value.entries) {
    final v = _toDoubleOrNull(entry.value);
    if (v != null) out[entry.key.toString()] = v;
  }
  return out;
}
