import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Server #3201: a folder says what the user asking may do with it, and an
/// older server leaves the app to the web's permission rule. Either way, what
/// the folder tile offers has to go through, and what it withholds has to be
/// refused — checked on the route itself.
void main() {
  group('library folder rights contract', skip: contractSkipReason, () {
    late Dio admin;
    late Dio user;
    late CurrentUser me;

    setUpAll(() async {
      admin = await authenticatedDio();
      (dio: user, :me) = await contractUser(admin, const [
        'library:read_own',
        'library:upload',
        'library:update_own',
        'library:delete_own',
      ]);
    });

    LibraryFolder find(List<LibraryFolder> tree, String name) =>
        flattenFolders(tree).firstWhere((f) => f.name == name);

    Future<bool> goesThrough(Future<void> Function() write) async {
      try {
        await write();
        return true;
      } on AppApiException catch (e) {
        if (e.code != AppErrorCode.forbidden) rethrow;
        return false;
      }
    }

    /// Renames [name] and then deletes it as [user], each expected to succeed
    /// exactly when the tile offers it.
    Future<void> offeredMatchesServer(String name) async {
      final repo = LibraryRepository(user);
      final folder = find(await repo.listFolders(), name);
      expect(
        await goesThrough(() => repo.renameFolder(folder.id, name)),
        folder.mayRename(me),
        reason: 'rename of $name',
      );
      expect(
        await goesThrough(() => repo.deleteFolder(folder.id)),
        folder.mayDelete(me),
        reason: 'delete of $name',
      );
    }

    String fresh(String what) =>
        'contract-$what-${DateTime.now().microsecondsSinceEpoch}';

    test('the user\'s own empty folder', () async {
      final name = fresh('own');
      await LibraryRepository(user).createFolder(name);
      addTearDown(() => _deleteByName(admin, name));
      await offeredMatchesServer(name);
    });

    test('someone else\'s shared folder', () async {
      final name = fresh('shared');
      final repo = LibraryRepository(admin);
      await repo.createFolder(name);
      addTearDown(() => _deleteByName(admin, name));
      final made = find(await repo.listFolders(), name);
      // Not empty, so delete_own is refused on a pre-#3201 server as well
      // (#1781) and the delete is a refusal on both generations.
      await repo.createFolder('$name-sub', parentId: made.id);
      // An older server ignores the field, and shows the folder to all anyway.
      await admin.put<dynamic>(
        Endpoints.libraryFolder(made.id),
        data: {'shared': true},
      );

      final seen = find(await LibraryRepository(user).listFolders(), name);
      if (seen.canRename != null) {
        expect(seen.canWrite, isTrue);
        expect(seen.canRename, isFalse);
        expect(seen.canDelete, isFalse);
      }
      expect(seen.mayDelete(me), isFalse);
      await offeredMatchesServer(name);
    });
  });
}

Future<void> _deleteByName(Dio admin, String name) async {
  final repo = LibraryRepository(admin);
  for (final f in await repo.listFolders()) {
    if (f.name == name) await repo.deleteFolder(f.id);
  }
}
