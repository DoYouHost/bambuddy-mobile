import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CurrentUser user(Set<String> permissions) => CurrentUser(
    id: 3,
    username: 'u',
    isAdmin: false,
    permissions: permissions,
  );

  group('a server with folder ownership (#3201)', () {
    final folder = LibraryFolder.fromJson({
      'id': 1,
      'name': 'Theirs',
      'can_write': false,
      'can_rename': false,
      'can_delete': true,
    });

    test('decides, whatever the permissions say', () {
      final all = user({
        Permissions.libraryUpdateAll,
        Permissions.libraryDeleteAll,
      });
      expect(folder.canWrite, isFalse);
      expect(folder.mayRename(all), isFalse);
      expect(folder.mayDelete(user(const {})), isTrue);
    });
  });

  group('an older server, without the flags', () {
    LibraryFolder folder([Map<String, dynamic> extra = const {}]) =>
        LibraryFolder.fromJson({'id': 1, 'name': 'Old', ...extra});

    test('lets everyone write', () {
      expect(folder().canWrite, isTrue);
    });

    test('renames with update-all only', () {
      expect(folder().mayRename(user(const {})), isFalse);
      expect(folder().mayRename(user({Permissions.libraryUpdateAll})), isTrue);
      expect(folder().mayRename(null), isTrue, reason: 'nobody known');
    });

    test('deletes with delete-own only an empty, unlinked, local folder', () {
      final own = user({Permissions.libraryDeleteOwn});
      expect(folder().mayDelete(own), isTrue);
      for (final blocked in [
        {'file_count': 2},
        {
          'children': [
            {'id': 2, 'name': 'Sub'},
          ],
        },
        {'is_external': true},
        {'project_id': 4},
        {'archive_id': 9, 'archive_name': null},
      ]) {
        expect(folder(blocked).mayDelete(own), isFalse, reason: '$blocked');
        expect(
          folder(blocked).mayDelete(user({Permissions.libraryDeleteAll})),
          isTrue,
        );
      }
      expect(folder().mayDelete(user(const {})), isFalse);
    });
  });

  group('folderMoveBlock', () {
    LibraryFolder f(
      int id, {
      int? parent,
      bool external = false,
      bool canWrite = true,
    }) => LibraryFolder(
      id: id,
      name: 'F$id',
      parentId: parent,
      isExternal: external,
      canWrite: canWrite,
    );

    /// The folders a move may pick.
    List<int> ids(List<LibraryFolder> all, LibraryFolder folder) => [
      for (final t in all)
        if (folderMoveBlock(all, folder, t) == null) t.id,
    ];

    test('leaves out the folder, its subtree and its current parent', () {
      final moving = f(2, parent: 1);
      final all = [
        f(1),
        moving,
        f(3, parent: 2),
        f(4, parent: 3),
        f(5),
        f(6, parent: 5),
      ];

      expect(ids(all, moving), [5, 6]);
    });

    test('leaves out an external folder and everything below it', () {
      final moving = f(1);
      final all = [moving, f(2, external: true), f(3, parent: 2), f(4)];

      expect(ids(all, moving), [4]);
    });

    test('offers nothing for an external folder', () {
      final moving = f(1, external: true);

      expect(ids([moving, f(2), f(3)], moving), isEmpty);
    });

    test('still leaves out the subtree when the list omits the folder', () {
      final moving = f(2, parent: 1);

      expect(ids([f(1), f(3, parent: 2), f(4)], moving), [4]);
    });

    test('leaves out a folder the user may not write to', () {
      final moving = f(1);
      final all = [moving, f(2, canWrite: false), f(3)];

      expect(ids(all, moving), [3]);
    });

    test('reads ancestry from parentId, not from nested children', () {
      final moving = f(1);
      // Children are empty on every row: the nesting is only in parentId.
      final all = [moving, f(2, parent: 1), f(3, parent: 2), f(4)];

      expect(ids(all, moving), [4]);
    });

    test(
      'nothing to offer, a lone folder and a parent missing from the list',
      () {
        final alone = f(1);
        expect(ids([alone], alone), isEmpty);
        expect(ids(const [], alone), isEmpty);

        // The parent is not in the list (e.g. a filtered tree): no crash.
        final orphan = f(2, parent: 99);
        expect(ids([orphan, f(3)], orphan), [3]);
      },
    );

    test('a parent cycle in the data ends instead of looping', () {
      final moving = f(1);
      final all = [moving, f(2, parent: 3), f(3, parent: 2)];

      expect(ids(all, moving), [2, 3]);
    });

    test('names why each row is refused', () {
      final moving = f(2, parent: 1);
      final all = [
        f(1),
        moving,
        f(3, parent: 2),
        f(4, external: true),
        f(5, parent: 4),
        f(6, canWrite: false),
        f(7),
      ];
      MoveBlock? why(int id) =>
          folderMoveBlock(all, moving, all.firstWhere((x) => x.id == id));

      expect(why(1), MoveBlock.current);
      expect(why(2), MoveBlock.self);
      expect(why(3), MoveBlock.inside);
      expect(why(4), MoveBlock.external);
      expect(why(5), MoveBlock.external);
      expect(why(6), MoveBlock.notWritable);
      expect(why(7), isNull);
    });

    test('the root is refused only to a folder already there and to a '
        'mount', () {
      expect(folderMoveBlock(const [], f(1), null), MoveBlock.current);
      expect(folderMoveBlock(const [], f(2, parent: 1), null), isNull);
      expect(
        folderMoveBlock(const [], f(2, parent: 1, external: true), null),
        MoveBlock.external,
      );
      expect(
        folderMoveBlock(const [], f(3, external: true), null),
        MoveBlock.external,
        reason: 'a mount at the top cannot go anywhere, so that is the reason',
      );
    });
  });

  group('fileMoveBlock', () {
    test('refuses where the file is and a folder the user may not write', () {
      const mine = LibraryFolder(id: 1, name: 'Mine');
      const theirs = LibraryFolder(id: 2, name: 'Theirs', canWrite: false);

      expect(fileMoveBlock(null, null), MoveBlock.current);
      expect(fileMoveBlock(1, mine), MoveBlock.current);
      expect(fileMoveBlock(null, mine), isNull);
      expect(fileMoveBlock(1, null), isNull);
      expect(fileMoveBlock(null, theirs), MoveBlock.notWritable);
    });

    test('takes a writable mount and refuses a read-only one', () {
      const rw = LibraryFolder(id: 3, name: 'NAS', isExternal: true);
      const ro = LibraryFolder(
        id: 4,
        name: 'Archive',
        isExternal: true,
        externalReadonly: true,
      );
      // `external_readonly` means nothing on a local folder.
      const local = LibraryFolder(id: 5, name: 'Odd', externalReadonly: true);

      expect(fileMoveBlock(null, rw), isNull);
      expect(fileMoveBlock(null, ro), MoveBlock.readOnly);
      expect(fileMoveBlock(null, local), isNull);
    });
  });

  group('folderRows', () {
    LibraryFolder f(int id, {int? parent}) =>
        LibraryFolder(id: id, name: 'F$id', parentId: parent);

    test('a depth per level, read along parentId, in the order given', () {
      final rows = folderRows([
        f(1),
        f(2, parent: 1),
        f(3, parent: 2),
        f(4),
        f(5, parent: 4),
      ]);

      expect(
        [for (final r in rows) (r.folder.id, r.depth)],
        [(1, 0), (2, 1), (3, 2), (4, 0), (5, 1)],
      );
    });

    test('an empty list, an orphan and a cycle neither fail nor loop', () {
      expect(folderRows(const []), isEmpty);
      expect(folderRows([f(2, parent: 99)]).single.depth, 0);
      expect(
        [
          for (final r in folderRows([f(2, parent: 3), f(3, parent: 2)]))
            r.depth,
        ],
        [0, 1],
      );
    });
  });
}
