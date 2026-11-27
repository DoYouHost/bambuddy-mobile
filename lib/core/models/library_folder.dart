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

/// Why a row of the move picker cannot be picked.
enum MoveBlock { current, self, inside, external, readOnly, notWritable }

/// One row of the move picker, [depth] levels below the root.
typedef FolderRow = ({LibraryFolder folder, int depth});

/// [all] in tree order, as [flattenFolders] gives it, as the rows of the web's
/// `FolderTargetList` (`FileManagerPage.tsx`). Read along `parentId`, so a folder
/// whose parent is not listed starts a tree of its own.
List<FolderRow> folderRows(List<LibraryFolder> all) {
  final rows = <int, FolderRow>{};
  return [
    for (final f in all)
      rows[f.id] = (folder: f, depth: (rows[f.parentId]?.depth ?? -1) + 1),
  ];
}

/// Why [folder] may not be moved into [target] (null is the root), as
/// `FileManagerPage.tsx` decides it (`moveDisallowedFolderIds`,
/// `isValidFolderMove`): the parent it already has, itself or anything below
/// it, anything external or below an external folder (a mount mirrors a path on
/// disk), a folder the user may not write to. Null where the move is allowed.
/// Ancestry is read from `parentId`, so a listing without nested children works.
MoveBlock? folderMoveBlock(
  List<LibraryFolder> all,
  LibraryFolder folder,
  LibraryFolder? target,
) {
  // A mount stays where the scan put it (the server answers 400), so it has no
  // target at all, the root included.
  if (folder.isExternal) return MoveBlock.external;
  if (target?.id == folder.parentId) return MoveBlock.current;
  if (target == null) return null;
  // [folder] is seeded in case [all] was filtered and no longer lists it.
  final byId = {for (final f in all) f.id: f, folder.id: folder};
  final seen = <int>{};
  for (
    LibraryFolder? c = target;
    c != null && seen.add(c.id);
    c = byId[c.parentId]
  ) {
    if (c.id == folder.id) {
      return c.id == target.id ? MoveBlock.self : MoveBlock.inside;
    }
    if (c.isExternal) return MoveBlock.external;
  }
  return target.canWrite ? null : MoveBlock.notWritable;
}

/// Why a file in [currentId] (null is the root) may not be moved into
/// [target]: it is there already, the user may not write to it, or it is a
/// read-only mount — the two refusals of `library.py::move_files`. A writable
/// mount takes the file's bytes, on every server from 1.2.5 on
/// (`library_external_move_contract_test.dart`).
MoveBlock? fileMoveBlock(int? currentId, LibraryFolder? target) =>
    switch (target) {
      _ when target?.id == currentId => MoveBlock.current,
      final t? when !t.canWrite => MoveBlock.notWritable,
      final t? when t.isExternal && t.externalReadonly => MoveBlock.readOnly,
      _ => null,
    };

List<LibraryFolder> flattenFolders(List<LibraryFolder> tree) => [
  for (final f in tree) ...[f, ...flattenFolders(f.children)],
];
