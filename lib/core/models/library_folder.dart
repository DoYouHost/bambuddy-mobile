import 'package:json_annotation/json_annotation.dart';

part 'library_folder.g.dart';

/// Węzeł drzewa folderów biblioteki (`FolderTreeItem`). Zagnieżdżony przez
/// [children]; parsowanie rekurencyjne i defensywne.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.projectName,
    this.archiveName,
    this.isExternal = false,
    this.externalPath,
    this.externalReadonly = false,
    this.fileCount = 0,
    this.children = const [],
  });

  factory LibraryFolder.fromJson(Map<String, dynamic> json) =>
      _$LibraryFolderFromJson(json);

  final int id;
  final String name;

  /// Folder nadrzędny; `null` = folder na poziomie root.
  final int? parentId;

  final String? projectName;
  final String? archiveName;

  /// Folder zewnętrzny wskazujący na katalog hosta.
  @JsonKey(defaultValue: false)
  final bool isExternal;
  final String? externalPath;

  /// Folder zewnętrzny tylko do odczytu — zapisy odrzucane przez serwer.
  @JsonKey(defaultValue: false)
  final bool externalReadonly;

  /// Liczba plików bezpośrednio w tym folderze.
  @JsonKey(defaultValue: 0)
  final int fileCount;

  /// Podfoldery.
  @JsonKey(defaultValue: [])
  final List<LibraryFolder> children;
}
