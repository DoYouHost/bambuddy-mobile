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

/// The folders [folder] may be moved into, as `FileManagerPage.tsx` offers them
/// (`moveDisallowedFolderIds`, `isValidFolderMove`): not itself or anything
/// below it, nothing external or below an external folder (a mount mirrors a
/// path on disk), nothing the user may not write to, and not the parent it
/// already has. The root is a separate entry, offered while
/// `folder.parentId != null`. [all] is flat, so ancestry is read from
/// `parentId` and a listing that arrives without nested children still works.
List<LibraryFolder> folderMoveTargets(
  List<LibraryFolder> all,
  LibraryFolder folder,
) {
  // A mount stays where the scan put it (the server answers 400), so it has no
  // target at all.
  if (folder.isExternal) return const [];
  // [folder] is seeded in case [all] was filtered and no longer lists it.
  final byId = {for (final f in all) f.id: f, folder.id: folder};
  bool blocked(LibraryFolder f) {
    final seen = <int>{};
    for (
      LibraryFolder? c = f;
      c != null && seen.add(c.id);
      c = byId[c.parentId]
    ) {
      if (c.id == folder.id || c.isExternal) return true;
    }
    return false;
  }

  return [
    for (final f in all)
      if (f.canWrite && f.id != folder.parentId && !blocked(f)) f,
  ];
}

/// Every folder of [tree], each parent before its children.
List<LibraryFolder> flattenFolders(List<LibraryFolder> tree) => [
  for (final f in tree) ...[f, ...flattenFolders(f.children)],
];
