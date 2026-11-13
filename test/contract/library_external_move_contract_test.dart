import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A file moved into an external folder (a mount): the server moves its bytes
/// onto the mount, refuses a read-only one with 403, and skips a name already
/// taken there inside a 200. Measured the same on 1.2.5, 1.3.1 and the dailies,
/// which is why the move picker offers a writable mount.
///
/// Needs `BAMBUDDY_CONTRACT_EXTERNAL_ROOT`: a path in the server's
/// `BAMBUDDY_EXTERNAL_ROOTS` holding writable `rw/` and `ro/` directories
/// (`tool/contract_stack.sh`, contract-tests.yml).
void main() {
  final root = Platform.environment['BAMBUDDY_CONTRACT_EXTERNAL_ROOT'];
  final skip =
      contractSkipReason ??
      ((root ?? '').isEmpty
          ? 'BAMBUDDY_CONTRACT_EXTERNAL_ROOT is unset'
          : null);

  group('moving a file into an external folder', skip: skip, () {
    late Dio dio;
    late LibraryRepository library;
    late LibraryFolder rw;
    late LibraryFolder ro;
    late Directory temp;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final uploaded = <int>[];

    /// The mount at [path], made on first use: a rerun on the same server
    /// finds the one it made before (409 for a path already mounted).
    Future<LibraryFolder> mount(String path, {required bool readonly}) async {
      await dio.post<dynamic>(
        '${Endpoints.libraryFolders}/external',
        data: {
          'name': 'contract-mount-${readonly ? 'ro' : 'rw'}',
          'external_path': path,
          'readonly': readonly,
        },
        options: Options(validateStatus: (s) => s == 200 || s == 409),
      );
      return flattenFolders(
        await library.listFolders(),
      ).firstWhere((f) => f.isExternal && f.externalPath == path);
    }

    /// A one-facet ASCII STL; [solid] names it, so each upload hashes apart.
    Future<int> upload(String solid) async {
      final content =
          'solid $solid\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\n'
          'vertex 10 0 0\nvertex 0 10 0\nendloop\nendfacet\nendsolid $solid\n';
      final name = 'contract-collide-$stamp.stl';
      final file = File('${temp.path}/${uploaded.length}-$name')
        ..writeAsStringSync(content);
      await library.uploadFile(filePath: file.path, filename: name);
      final id = (await library.listFiles(
        folderId: null,
      )).where((f) => f.filename == name && !uploaded.contains(f.id)).single.id;
      uploaded.add(id);
      return id;
    }

    Future<String> pathOf(int fileId) async =>
        (await dio.get<Map<String, dynamic>>(
              Endpoints.libraryFile(fileId),
            )).data!['file_path']
            as String;

    setUpAll(() async {
      dio = await authenticatedDio();
      library = LibraryRepository(dio);
      temp = await Directory.systemTemp.createTemp('external-move');
      rw = await mount('$root/rw', readonly: false);
      ro = await mount('$root/ro', readonly: true);
    });

    tearDownAll(() async {
      for (final id in uploaded) {
        await library.moveFiles([id]);
        await library.deleteFile(id);
      }
      await temp.delete(recursive: true);
    });

    test('a writable mount takes the bytes, and the root takes them '
        'back', () async {
      final id = await upload('a');

      expect(await library.moveFiles([id], folderId: rw.id), (
        moved: 1,
        skipped: 0,
        skipCode: null,
        skipReason: null,
      ));
      expect(await pathOf(id), startsWith('$root/rw/'));

      expect((await library.moveFiles([id])).moved, 1);
      expect(await pathOf(id), isNot(startsWith('$root/')));
    });

    test('a read-only mount is refused before anything moves', () async {
      final id = await upload('b');

      await expectLater(
        library.moveFiles([id], folderId: ro.id),
        throwsA(
          isA<AppApiException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
      expect(await pathOf(id), isNot(startsWith('$root/')));
    });

    test('a name the mount already holds is skipped inside a 200, with its '
        'code and reason', () async {
      final first = await upload('c');
      final second = await upload('d');

      expect((await library.moveFiles([first], folderId: rw.id)).moved, 1);
      final outcome = await library.moveFiles([second], folderId: rw.id);

      expect(outcome.moved, 0);
      expect(outcome.skipped, 1);
      expect(outcome.skipCode, 'name_collision');
      expect(outcome.skipReason, contains('already exists'));
    });
  });
}
