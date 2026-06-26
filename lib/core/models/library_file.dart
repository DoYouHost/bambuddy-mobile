import 'package:json_annotation/json_annotation.dart';

part 'library_file.g.dart';

/// File in library file manager (`FileListResponse`).
///
/// Defensive parsing: all except id/filename/file_type/file_size/created_at
/// are nullable, unknown keys ignored — API contract evolves.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.filename,
    required this.fileType,
    required this.fileSize,
    required this.printCount,
    this.folderId,
    this.isExternal = false,
    this.thumbnailPath,
    this.duplicateCount = 0,
    this.createdByUsername,
    this.createdAt,
    this.printName,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.slicedForModel,
  });

  factory LibraryFile.fromJson(Map<String, dynamic> json) =>
      _$LibraryFileFromJson(json);

  final int id;
  final int? folderId;

  /// File from external folder (host-side read-only) — some actions
  /// (delete/rename) may be unavailable.
  @JsonKey(defaultValue: false)
  final bool isExternal;

  /// Filename on disk (e.g. "Mug Holder.3mf").
  final String filename;

  /// File extension/type (e.g. "3mf", "gcode", "stl").
  final String fileType;

  /// File size in bytes.
  final int fileSize;

  /// Thumbnail path (if generated). Actual render goes via `thumbnail` endpoint
  /// with token — this field only checks "does it exist".
  final String? thumbnailPath;

  /// Print count for this file.
  final int printCount;

  /// Duplicate count (same hash elsewhere in library).
  @JsonKey(defaultValue: 0)
  final int duplicateCount;

  /// Username who uploaded the file.
  final String? createdByUsername;

  final DateTime? createdAt;

  /// Human-readable print name from slicer metadata (if different from [filename]).
  final String? printName;

  /// Estimated print time in seconds from slicer metadata.
  final int? printTimeSeconds;

  /// Estimated filament usage in grams from slicer metadata.
  final double? filamentUsedGrams;

  /// Printer model this file was sliced for (e.g. "P1S", "X1C").
  final String? slicedForModel;

  /// Display name: print name if available, otherwise filename.
  String get displayName => printName ?? filename;

  /// Whether file is printable (sliced g-code). Print endpoint only accepts these
  /// — see `FilePrint` in API.
  bool get isPrintable {
    final t = fileType.toLowerCase();
    final name = filename.toLowerCase();
    return t == 'gcode' ||
        name.endsWith('.gcode') ||
        name.endsWith('.gcode.3mf');
  }
}
