import 'package:json_annotation/json_annotation.dart';

part 'trash_file.g.dart';

/// Plik w koszu biblioteki (`TrashFile`). Parsowanie defensywne.
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

  /// Nazwa folderu, z którego plik trafił do kosza.
  final String? folderName;
  final String? createdByUsername;

  /// Kiedy plik trafił do kosza.
  final DateTime? deletedAt;

  /// Kiedy plik zostanie automatycznie wyczyszczony (retencja kosza).
  final DateTime? autoPurgeAt;
}
