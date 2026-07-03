import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'archive.g.dart';

/// Archive entry from `ArchiveResponse`.
/// Defensive parsing: all fields except id/filename/status are nullable, unknown
/// keys ignored — the API is young and evolving.
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

  final String filename;

  /// Raw status from server (e.g. "completed", "printing") — not enum-backed
  /// to avoid breaking on new server values.
  final String status;

  final int? printerId;

  /// Human-readable print name from user or slicer.
  final String? printName;

  /// Thumbnail path for the print.
  final String? thumbnailPath;

  /// Print time in seconds.
  final int? printTimeSeconds;

  /// Filament used in grams.
  final double? filamentUsedGrams;

  /// Filament type (e.g. "PETG", "PLA").
  final String? filamentType;

  /// Filament color as hex (e.g. "#FFFF00").
  final String? filamentColor;

  /// Print cost in server-configured currency.
  final double? cost;

  /// Whether marked as favorite. Defaults to false.
  @JsonKey(defaultValue: false)
  final bool isFavorite;

  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? createdAt;

  /// Model designer/author (e.g. from MakerWorld).
  final String? designer;

  /// Link to model on MakerWorld, if imported from there.
  final String? makerworldUrl;

  /// Total layer count for the print.
  final int? totalLayers;

  /// Layer height in mm.
  final double? layerHeight;

  /// Nozzle diameter in mm.
  final double? nozzleDiameter;

  /// Printer model this file was sliced for (e.g. "X2D").
  final String? slicedForModel;

  /// Print quantity.
  final int? quantity;

  /// Display name: print name if available, otherwise filename.
  String get displayName => printName ?? filename;
}
