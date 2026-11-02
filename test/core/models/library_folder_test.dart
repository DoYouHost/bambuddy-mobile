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

  group('folderMoveTargets', () {
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

    List<int> ids(List<LibraryFolder> all, LibraryFolder folder) => [
      for (final t in folderMoveTargets(all, folder)) t.id,
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
  });
}
