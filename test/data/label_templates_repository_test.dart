import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:bambuddy_mobile/data/label_templates_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late LabelTemplatesRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = LabelTemplatesRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  Map<String, dynamic> row(int id, String name) => {
    'id': id,
    'name': name,
    'layout': SheetLayout.starting.toJson(),
    'created_at': '2026-11-01T10:00:00',
    'updated_at': '2026-11-01T10:00:00',
  };

  final body = {'name': 'Avery', 'layout': SheetLayout.starting.toJson()};

  group('capability', () {
    test('the version decides before the listing has answered', () async {
      replyVersion('1.2.5.7');
      expect(await repo.capability.supported, isFalse);
    });

    test('a 1.3.0 server is offered custom sheets', () async {
      replyVersion('1.3.0');
      expect(await repo.capability.supported, isTrue);
    });

    test('a 404 on the listing hides them where the version would '
        'offer them', () async {
      replyVersion('1.3.1b1');
      adapter.onGet(
        '/api/v1/label-templates',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.list(), isEmpty);
      expect(await repo.capability.supported, isFalse);
    });

    test('a listing that answers settles it present', () async {
      replyVersion('1.2.5.7');
      adapter.onGet('/api/v1/label-templates', (s) => s.reply(200, <Object>[]));

      await repo.list();
      expect(await repo.capability.supported, isTrue);
    });

    test('a 403 on the listing hides the feature and lists nothing', () async {
      adapter.onGet(
        '/api/v1/label-templates',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      expect(await repo.list(), isEmpty);
      expect(repo.capability.observedAnswer, isFalse);
    });
  });

  test("the listing keeps the server's order and drops an unreadable "
      'row', () async {
    adapter.onGet(
      '/api/v1/label-templates',
      (s) => s.reply(200, [
        row(2, 'Address'),
        {
          'id': 3,
          'name': 'Future page',
          'layout': {...SheetLayout.starting.toJson(), 'page': 'a5'},
        },
        row(1, 'Shipping'),
      ]),
    );

    final listed = await repo.list();
    expect([for (final t in listed) t.name], ['Address', 'Shipping']);
  });

  group('writes', () {
    test('create posts the name and the whole layout', () async {
      adapter.onPost(
        '/api/v1/label-templates',
        (s) => s.reply(201, row(7, 'Avery')),
        data: body,
      );

      expect((await repo.create('Avery', SheetLayout.starting)).id, 7);
    });

    test('update puts the whole template on its id', () async {
      adapter.onPut(
        '/api/v1/label-templates/7',
        (s) => s.reply(200, row(7, 'Avery')),
        data: body,
      );

      final saved = await repo.update(7, 'Avery', SheetLayout.starting);
      expect(saved.name, 'Avery');
    });

    test('delete answers nothing', () async {
      adapter.onDelete('/api/v1/label-templates/7', (s) => s.reply(204, null));

      await repo.delete(7);
    });

    test('a taken name is a 409 the caller can read', () async {
      adapter.onPost(
        '/api/v1/label-templates',
        (s) => s.reply(409, {
          'detail': 'A label template with this name already exists',
        }),
        data: body,
      );

      await expectLater(
        repo.create('Avery', SheetLayout.starting),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
        ),
      );
    });

    test('a refused write leaves the read side offered', () async {
      adapter
        ..onGet('/api/v1/label-templates', (s) => s.reply(200, <Object>[]))
        ..onPost(
          '/api/v1/label-templates',
          (s) => s.reply(403, {'detail': 'Missing required permissions'}),
          data: body,
        );

      await repo.list();
      await expectLater(
        repo.create('Avery', SheetLayout.starting),
        throwsA(isA<AppApiException>()),
      );
      expect(await repo.capability.supported, isTrue);
    });

    test('a 404 on a save is the row gone, not the route', () async {
      adapter
        ..onGet('/api/v1/label-templates', (s) => s.reply(200, <Object>[]))
        ..onPut(
          '/api/v1/label-templates/9',
          (s) => s.reply(404, {'detail': 'Label template not found'}),
          data: body,
        );

      await repo.list();
      await expectLater(
        repo.update(9, 'Avery', SheetLayout.starting),
        throwsA(isA<AppApiException>()),
      );
      expect(await repo.capability.supported, isTrue);
    });
  });
}
