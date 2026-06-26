import 'package:json_annotation/json_annotation.dart';

part 'trash_file.g.dart';

/// File in library trash (`TrashFile`). Defensive parsing.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TrashFile {
  const TrashFile({
    required this.id,
    required this.filename,
    required this.fileSize,
    this.thumbnailPath,
    this.folderName,
    this.createdByUsername,
    this.deletedAt,
    this.autoPurgeAt,
  });

  factory TrashFile.fromJson(Map<String, dynamic> json) =>
      _$TrashFileFromJson(json);

  final int id;
  final String filename;
  final int fileSize;
  final String? thumbnailPath;

  /// Folder name the file was trashed from.
  final String? folderName;
  final String? createdByUsername;

  /// When file was moved to trash.
  final DateTime? deletedAt;

  /// When file will auto-purge (trash retention).
  final DateTime? autoPurgeAt;
}
