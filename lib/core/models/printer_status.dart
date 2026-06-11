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

  bool get isPrinting => (progress ?? 0) > 0 && (remainingTime ?? 0) > 0;
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
