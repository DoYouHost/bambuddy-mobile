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
    this.plateId,
    this.completedAt,
    this.thumbnailPath,
    this.timelapsePath,
    this.photos = const [],
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
    this.fileSize,
    this.duplicateCount = 0,
    this.duplicateSequence = 0,
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

  /// Which plate of a multi-plate 3MF this run printed (`#2603`; the value was
  /// stored but always reported as null before server 1.2.5.4). Null whenever
  /// no plate was picked for the print — a plain single-plate file, or a print
  /// started from a client that does not send one, this app included — so it is
  /// shown only when present rather than defaulted to plate 1.
  final int? plateId;

  /// Thumbnail path for the print.
  final String? thumbnailPath;

  /// Server-side path of the recorded timelapse, or null when the print has
  /// none. Read as a presence flag only — the video is fetched through
  /// `Endpoints.archiveTimelapse`, never from this path.
  final String? timelapsePath;

  /// Whether a timelapse video exists for this print.
  bool get hasTimelapse => (timelapsePath ?? '').isNotEmpty;

  /// Filenames of the photos attached to the print — the shot the server
  /// captures from the camera when the print ends (named `finish_…`) plus
  /// anything uploaded in the web UI. Fetched through `Endpoints.archivePhoto`;
  /// the server only serves a name that appears in this list.
  @JsonKey(fromJson: toStringList)
  final List<String> photos;

  /// Whether the print has at least one photo.
  bool get hasPhotos => photos.isNotEmpty;

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

  /// When the print on this archive last ended. Unlike [createdAt] it is
  /// rewritten on every run — a reprint reuses the archive row and refreshes
  /// this and `started_at`, leaving `created_at` on the original print
  /// (`main.py`, expected-archive branch; `ArchiveService.update_status`). So
  /// this, not the row's age, says which print just finished.
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? completedAt;

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

  /// File size in bytes (for size sorting).
  final int? fileSize;

  /// How many other archives duplicate this one (server-computed). 0 = unique.
  @JsonKey(defaultValue: 0)
  final int duplicateCount;

  /// Position of this archive within its duplicate group, oldest first.
  /// 0 marks the original (kept when "hide duplicates" is on); >0 are copies.
  @JsonKey(defaultValue: 0)
  final int duplicateSequence;

  /// Display name: print name if available, otherwise filename.
  String get displayName => printName ?? filename;

  /// Copy with a flipped/overridden favorite flag — for optimistic UI updates
  /// (the only field the app mutates locally). Everything else is carried over.
  Archive withFavorite(bool value) => Archive(
    id: id,
    filename: filename,
    status: status,
    printerId: printerId,
    printName: printName,
    plateId: plateId,
    completedAt: completedAt,
    thumbnailPath: thumbnailPath,
    timelapsePath: timelapsePath,
    photos: photos,
    printTimeSeconds: printTimeSeconds,
    filamentUsedGrams: filamentUsedGrams,
    filamentType: filamentType,
    filamentColor: filamentColor,
    cost: cost,
    isFavorite: value,
    createdAt: createdAt,
    designer: designer,
    makerworldUrl: makerworldUrl,
    totalLayers: totalLayers,
    layerHeight: layerHeight,
    nozzleDiameter: nozzleDiameter,
    slicedForModel: slicedForModel,
    quantity: quantity,
    fileSize: fileSize,
    duplicateCount: duplicateCount,
    duplicateSequence: duplicateSequence,
  );

  /// Whether this archive is a sliced/printable file rather than a source
  /// project. Mirrors bambuddy's `isSlicedFile`: a `.gcode`/`.gcode.*` name, or
  /// any file carrying sliced metadata (layer count / print-time estimate).
  bool get isSliced {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.gcode') || lower.contains('.gcode.')) return true;
    return (totalLayers ?? 0) > 0 || (printTimeSeconds ?? 0) > 0;
  }

  /// Filament colors as a list of hex tokens (a print can use several).
  /// Empty when no color is recorded. Values are kept verbatim (may include a
  /// leading `#`); callers normalize as needed.
  List<String> get filamentColors =>
      filamentColor
          ?.split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList() ??
      const [];
}
