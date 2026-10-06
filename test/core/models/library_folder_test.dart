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
        {'project_name': 'Desk'},
        {'archive_name': 'Benchy'},
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
}
