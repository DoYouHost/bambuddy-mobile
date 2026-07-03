import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'library_folder.g.dart';

/// Library folder tree node (`FolderTreeItem`). Nested via [children];
/// recursive and defensive parsing.
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

  /// Parent folder; `null` = root-level folder.
  final int? parentId;

  final String? projectName;
  final String? archiveName;

  /// External folder pointing to host directory.
  @JsonKey(defaultValue: false)
  final bool isExternal;
  final String? externalPath;

  /// External folder read-only — writes rejected by server.
  @JsonKey(defaultValue: false)
  final bool externalReadonly;

  /// File count directly in this folder.
  @JsonKey(defaultValue: 0)
  final int fileCount;

  /// Subfolders.
  @JsonKey(fromJson: _childrenFromJson)
  final List<LibraryFolder> children;
}

List<LibraryFolder> _childrenFromJson(dynamic value) =>
    parseJsonList(value, LibraryFolder.fromJson);
