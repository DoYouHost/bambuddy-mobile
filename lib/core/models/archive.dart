import 'package:json_annotation/json_annotation.dart';

part 'archive.g.dart';

/// Wpis archiwum wydruku z `ArchiveResponse`.
/// Parsowanie defensywne: poza id/filename/status wszystko nullable, nieznane
/// klucze ignorowane — API bambuddy jest młode i ruchliwe.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class Archive {
  const Archive({
    required this.id,
    required this.filename,
    required this.status,
    this.printerId,
    this.printName,
    this.thumbnailPath,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.filamentType,
    this.filamentColor,
    this.cost,
    this.isFavorite = false,
    this.createdAt,
    this.designer,
    this.makerworldUrl,
    this.totalLayers,
    this.layerHeight,
    this.nozzleDiameter,
    this.slicedForModel,
    this.quantity,
  });

  factory Archive.fromJson(Map<String, dynamic> json) =>
      _$ArchiveFromJson(json);

  final int id;

  /// Nazwa pliku gcode/3mf na dysku.
  final String filename;

  /// Surowy status z serwera (np. „completed", „printing") — nie enumujemy,
  /// żeby nowe wartości nie wywalały parsera.
  final String status;

  final int? printerId;

  /// Czytelna nazwa wydruku podana przez użytkownika lub eksportera slicera.
  final String? printName;

  /// Ścieżka do miniatury wydruku.
  final String? thumbnailPath;

  /// Czas wydruku w sekundach.
  final int? printTimeSeconds;

  /// Zużyty filament w gramach.
  final double? filamentUsedGrams;

  /// Typ filamentu (np. „PETG", „PLA").
  final String? filamentType;

  /// Kolor filamentu jako hex (np. „#FFFF00").
  final String? filamentColor;

  /// Koszt wydruku w walucie skonfigurowanej na serwerze.
  final double? cost;

  /// Czy wydruk jest oznaczony jako ulubiony. Domyślnie false.
  @JsonKey(defaultValue: false)
  final bool isFavorite;

  final DateTime? createdAt;

  /// Projektant/autor modelu (np. z MakerWorld).
  final String? designer;

  /// Link do modelu na MakerWorld, jeśli pochodzi stamtąd.
  final String? makerworldUrl;

  /// Łączna liczba warstw wydruku.
  final int? totalLayers;

  /// Wysokość warstwy w mm.
  final double? layerHeight;

  /// Średnica dyszy w mm.
  final double? nozzleDiameter;

  /// Model drukarki, dla którego plik był skrojony (np. „X2D").
  final String? slicedForModel;

  /// Liczba egzemplarzy wydruku.
  final int? quantity;

  /// Wyświetlana nazwa: czytelna nazwa wydruku, jeśli dostępna, w przeciwnym
  /// razie surowa nazwa pliku.
  String get displayName => printName ?? filename;
}
