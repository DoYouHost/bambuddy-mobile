import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/manyfold.dart';
import 'package:bambuddy_mobile/data/manyfold_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ManyfoldRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = ManyfoldRepository(dio);
  });

  Map<String, dynamic> coded(String code) => {
    'detail': {'code': code, 'message': 'server text'},
  };

  group('status', () {
    test('reads a connected install', () async {
      adapter.onGet(
        '/api/v1/manyfold/status',
        (s) => s.reply(200, {'configured': true, 'url': 'http://mf:3214'}),
      );
      final status = await repo.status();
      expect(status?.configured, isTrue);
      expect(status?.url, 'http://mf:3214');
    });

    test('a server without the routes has no Manyfold', () async {
      adapter.onGet(
        '/api/v1/manyfold/status',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );
      expect(await repo.status(), isNull);
    });

    test('a session without manyfold:view has none either', () async {
      adapter.onGet(
        '/api/v1/manyfold/status',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );
      expect(await repo.status(), isNull);
    });

    test('a server error is still an error', () async {
      adapter.onGet('/api/v1/manyfold/status', (s) => s.reply(500, null));
      await expectLater(repo.status(), throwsA(isA<AppApiException>()));
    });
  });

  test('a coded failure names its code, a plain one maps as usual', () async {
    adapter
      ..onGet(
        '/api/v1/manyfold/models',
        (s) => s.reply(502, coded('manyfold_unreachable')),
        queryParameters: {'q': '', 'page': 1},
      )
      ..onPost(
        '/api/v1/manyfold/import',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        data: {'model_id': 'a1', 'file_id': 'b2', 'folder_id': null},
      );

    await expectLater(
      repo.models(),
      throwsA(
        isA<ManyfoldFailure>()
            .having((f) => f.code, 'code', 'manyfold_unreachable')
            .having((f) => f.statusCode, 'status', 502),
      ),
    );
    await expectLater(
      repo.import(modelId: 'a1', fileId: 'b2'),
      throwsA(isA<AuthException>()),
    );
  });

  test('a model parses with its files and earlier imports', () async {
    adapter.onGet(
      '/api/v1/manyfold/models/k3x9',
      (s) => s.reply(200, {
        'id': 'k3x9',
        'name': 'Dragon',
        'caption': null,
        'description': 'Print in place',
        'license': 'CC0',
        'tags': ['toy'],
        'url': 'http://mf/models/k3x9',
        'has_preview': true,
        'files': [
          {
            'id': 'f1',
            'name': 'dragon.3mf',
            'mime': 'model/3mf',
            'importable': true,
            'library_file': {'id': 9, 'filename': 'dragon.3mf', 'folder_id': 4},
          },
          {
            'id': 'f2',
            'name': 'tail.stl',
            'mime': 'model/x-stl',
            'importable': true,
            'library_file': null,
          },
          {
            'id': 'f3',
            'name': 'readme.pdf',
            'mime': 'application/pdf',
            'importable': false,
          },
        ],
      }),
    );

    final model = await repo.model('k3x9');

    expect(model.files.first.libraryFile?.folderId, 4);
    expect(model.importCandidates.map((f) => f.id), ['f2']);
    expect(model.files.map((f) => f.typeLabel), ['3MF', 'STL', 'PDF']);
  });

  test('a model without a preview answers null, not an error', () async {
    adapter.onGet(
      '/api/v1/manyfold/models/k3x9/preview',
      (s) => s.reply(404, coded('manyfold_not_found')),
    );
    expect(await repo.preview('k3x9'), isNull);
  });

  test('an empty secret is left out, so the stored one is kept', () async {
    adapter.onPut(
      '/api/v1/manyfold/config',
      (s) => s.reply(200, {
        'url': 'http://mf:3214',
        'client_id': 'app',
        'has_client_secret': true,
        'configured': true,
      }),
      data: {'url': 'http://mf:3214', 'client_id': 'app'},
    );

    final config = await repo.saveConfig(
      url: ' http://mf:3214 ',
      clientId: 'app',
      clientSecret: '  ',
    );

    expect(config.configured, isTrue);
  });

  group('manyfoldCodeOf', () {
    test('reads a Manyfold code', () {
      expect(manyfoldCodeOf(coded('manyfold_scope')), 'manyfold_scope');
    });

    test('ignores a plain detail, another code and odd bodies', () {
      expect(manyfoldCodeOf({'detail': 'Not Found'}), isNull);
      expect(
        manyfoldCodeOf({
          'detail': {'code': 'printer_connection_failed'},
        }),
        isNull,
      );
      expect(manyfoldCodeOf(null), isNull);
      expect(manyfoldCodeOf('<html>'), isNull);
      expect(
        manyfoldCodeOf({
          'detail': {'code': 7},
        }),
        isNull,
      );
    });
  });

  group('typeLabel', () {
    String label(String mime) =>
        ManyfoldFile(id: '', name: '', mime: mime).typeLabel;

    test('takes the subtype without x- and suffixes', () {
      expect(label('model/x-step+zip'), 'STEP');
      expect(label('model/3mf'), '3MF');
      expect(label('image/png;charset=x'), 'PNG');
    });

    test('a missing or odd type is a question mark', () {
      expect(label(''), '?');
      expect(label('model'), '?');
      expect(label('model/'), '?');
    });
  });
}
