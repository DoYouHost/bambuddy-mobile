import 'package:app_util/app_util.dart';
import 'package:json_annotation/json_annotation.dart';

import 'current_user.dart';

part 'library_folder.g.dart';

/// Library folder tree node (`FolderTreeItem`). Nested via [children];
/// recursive and defensive parsing.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.projectId,
    this.archiveId,
    this.projectName,
    this.archiveName,
    this.isExternal = false,
    this.externalPath,
    this.externalReadonly = false,
    this.fileCount = 0,
    this.canWrite = true,
    this.canRename,
    this.canDelete,
    this.children = const [],
  });

  factory LibraryFolder.fromJson(Map<String, dynamic> json) =>
      _$LibraryFolderFromJson(json);

  final int id;
  final String name;

  /// Parent folder; `null` = root-level folder.
  final int? parentId;

  /// Linked project / archive. Ids rather than names decide whether a folder is
  /// linked: an archive without a print name links with a null name.
  final int? projectId;
  final int? archiveId;

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

  /// What the signed-in user may do with this folder (#3201, server-computed:
  /// `services/library_folder_access.py`). Write is adding files or
  /// subfolders, and being a move target. Folders had no owner before it, so an
  /// older server sends none of these and nothing is withheld for ownership;
  /// rename and delete are null there, and
  /// [mayRename] / [mayDelete] fall back to the web's permission rule.
  @JsonKey(defaultValue: true)
  final bool canWrite;
  final bool? canRename;
  final bool? canDelete;

  /// `FileManagerPage.tsx`'s `canRename`.
  bool mayRename(CurrentUser? me) =>
      canRename ?? me?.can(Permissions.libraryUpdateAll) ?? true;

  /// `FileManagerPage.tsx`'s `canDeleteFolder`: before #3201 a user without
  /// delete-all deletes only an empty, unlinked, local folder.
  bool mayDelete(CurrentUser? me) =>
      canDelete ??
      (me == null ||
          me.can(Permissions.libraryDeleteAll) ||
          (me.can(Permissions.libraryDeleteOwn) &&
              fileCount == 0 &&
              children.isEmpty &&
              !isExternal &&
              projectId == null &&
              archiveId == null));

  /// Subfolders.
  @JsonKey(fromJson: _childrenFromJson)
  final List<LibraryFolder> children;
}

List<LibraryFolder> _childrenFromJson(dynamic value) =>
    parseJsonList(value, LibraryFolder.fromJson);
