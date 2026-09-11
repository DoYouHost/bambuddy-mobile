import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late MakerWorldRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = MakerWorldRepository(dio);
  });

  group('MakerWorldRepository', () {
    test('status decodes cloud token availability', () async {
      adapter.onGet(
        Endpoints.makerworldStatus,
        (s) => s.reply(200, {
          'has_cloud_token': true,
          'can_download': true,
        }),
      );

      final status = await repo.status();
      expect(status.hasCloudToken, isTrue);
      expect(status.canDownload, isTrue);
    });

    test('resolve decodes model design, instances and already imported ids', () async {
      adapter.onPost(
        Endpoints.makerworldResolve,
        (s) => s.reply(200, {
          'model_id': 12345,
          'profile_id': 67890,
          'design': {
            'title': 'Awesome Benchy Stand',
            'cover': 'https://example.com/cover.png',
          },
          'instances': [
            {
              'profile_id': 67890,
              'name': 'Standard Plate',
              'cover': 'https://example.com/plate.png',
            },
          ],
          'already_imported_library_ids': [101, 102],
        }),
        data: {'url': 'https://makerworld.com/en/models/12345#profileId-67890'},
      );

      final resolved = await repo.resolve(
        'https://makerworld.com/en/models/12345#profileId-67890',
      );

      expect(resolved.modelId, 12345);
      expect(resolved.profileId, 67890);
      expect(resolved.design.title, 'Awesome Benchy Stand');
      expect(resolved.design.coverUrl, 'https://example.com/cover.png');
      expect(resolved.instances, hasLength(1));
      expect(resolved.instances.single.name, 'Standard Plate');
      expect(resolved.alreadyImportedLibraryIds, {101, 102});
    });

    test('import sends modelId, profileId, folderId and parses response', () async {
      adapter.onPost(
        Endpoints.makerworldImport,
        (s) => s.reply(200, {
          'library_file_id': 42,
          'filename': 'awesome_benchy.3mf',
          'folder_id': 3,
          'profile_id': 67890,
          'was_existing': false,
        }),
        data: {
          'model_id': 12345,
          'profile_id': 67890,
          'folder_id': 3,
        },
      );

      final result = await repo.import(
        modelId: 12345,
        profileId: 67890,
        folderId: 3,
      );

      expect(result.libraryFileId, 42);
      expect(result.filename, 'awesome_benchy.3mf');
      expect(result.folderId, 3);
      expect(result.profileId, 67890);
      expect(result.wasExisting, isFalse);
    });

    test('recentImports decodes list with defensive fallback', () async {
      adapter.onGet(
        Endpoints.makerworldRecentImports,
        (s) => s.reply(200, [
          {
            'library_file_id': 42,
            'filename': 'benchy.3mf',
            'folder_id': 1,
            'thumbnail_path': '/thumbs/42.png',
            'source_url': 'https://makerworld.com/models/123',
            'created_at': '2026-03-01T12:00:00Z',
          },
          'invalid entry',
        ]),
        queryParameters: {'limit': 10},
      );

      final recent = await repo.recentImports(limit: 10);
      expect(recent, hasLength(1));
      expect(recent.single.libraryFileId, 42);
      expect(recent.single.filename, 'benchy.3mf');
      expect(recent.single.thumbnailPath, '/thumbs/42.png');
      expect(recent.single.sourceUrl, 'https://makerworld.com/models/123');
    });

    test('maps 403 DioException to AuthException via guard', () async {
      adapter.onGet(
        Endpoints.makerworldStatus,
        (s) => s.reply(403, {'detail': 'Permission MAKERWORLD_VIEW required'}),
      );

      expect(
        () => repo.status(),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
