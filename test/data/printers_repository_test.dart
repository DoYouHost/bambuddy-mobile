import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/wled_config.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PrintersRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = PrintersRepository(dio);
  });

  test('fetchAll: list + statuses', () async {
    adapter
      ..onGet(
        '/api/v1/printers/',
        (server) => server.reply(200, readFixture('printers_list.json')),
      )
      ..onGet(
        '/api/v1/printers/1/status',
        (server) =>
            server.reply(200, readFixture('printer_status_printing.json')),
      )
      ..onGet(
        '/api/v1/printers/2/status',
        (server) => server.reply(200, readFixture('printer_status_idle.json')),
      );

    final all = await repo.fetchAll();

    expect(all, hasLength(2));
    expect(all[0].printer.name, 'X1C Warsztat');
    expect(all[0].status?.state, 'RUNNING');
    expect(all[1].status?.state, 'IDLE');
  });

  test(
    'a failed status for one printer does not crash the dashboard',
    () async {
      adapter
        ..onGet(
          '/api/v1/printers/',
          (server) => server.reply(200, readFixture('printers_list.json')),
        )
        ..onGet(
          '/api/v1/printers/1/status',
          (server) =>
              server.reply(200, readFixture('printer_status_printing.json')),
        )
        ..onGet(
          '/api/v1/printers/2/status',
          (server) => server.reply(500, {'detail': 'printer offline'}),
        );

      final all = await repo.fetchAll();

      expect(all, hasLength(2));
      expect(all[0].status, isNotNull);
      expect(all[1].status, isNull);
    },
  );

  test('an unparseable list entry is skipped', () async {
    adapter.onGet(
      '/api/v1/printers/',
      (server) => server.reply(200, [
        {'id': 1, 'name': 'OK'},
        {'name': 'no id — dropped'},
        'junk',
      ]),
    );

    final printers = await repo.fetchPrinters();
    expect(printers, hasLength(1));
    expect(printers.single.name, 'OK');
  });

  test(
    '401 on the list → AuthException (UI redirects to configuration)',
    () async {
      adapter.onGet(
        '/api/v1/printers/',
        (server) => server.reply(401, {'detail': 'Unauthorized'}),
      );

      await expectLater(repo.fetchPrinters(), throwsA(isA<AuthException>()));
    },
  );

  test('401 on the status also flows out as AuthException', () async {
    adapter
      ..onGet(
        '/api/v1/printers/',
        (server) => server.reply(200, [
          {'id': 1, 'name': 'OK'},
        ]),
      )
      ..onGet(
        '/api/v1/printers/1/status',
        (server) => server.reply(401, {'detail': 'Unauthorized'}),
      );

    await expectLater(repo.fetchAll(), throwsA(isA<AuthException>()));
  });

  test('timeout → NetworkException', () async {
    adapter.onGet(
      '/api/v1/printers/',
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/printers/'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    );

    await expectLater(repo.fetchPrinters(), throwsA(isA<NetworkException>()));
  });

  group('WLED', () {
    setUp(() => repo = PrintersRepository(dio, ServerVersionService(dio)));

    void replyVersion(String version) => adapter.onGet(
      '/api/v1/updates/version',
      (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
    );

    void replyPrinters(List<Map<String, dynamic>> rows) =>
        adapter.onGet('/api/v1/printers/', (s) => s.reply(200, rows));

    const config = WledConfig(
      enabled: true,
      baseUrl: 'http://wled.local',
      presets: {WledState.printing: 3},
    );

    test('the version decides before a printer row has answered', () async {
      replyVersion('1.3.1');
      expect(await repo.wledCapability.supported, isFalse);
    });

    test('a 1.3.2b1 daily is offered it before a row has answered', () async {
      replyVersion('1.3.2b1');
      expect(await repo.wledCapability.supported, isTrue);
    });

    test('a row without wled_config closes it on a server whose version '
        'would offer it', () async {
      replyVersion('1.3.2b1');
      replyPrinters([
        {'id': 1, 'name': 'X1C'},
      ]);

      await repo.fetchPrinters();

      expect(await repo.wledCapability.supported, isFalse);
    });

    test('a row with wled_config null opens it on a server whose version '
        'would not', () async {
      replyVersion('1.3.1');
      replyPrinters([
        {'id': 1, 'name': 'X1C', 'wled_config': null},
      ]);

      await repo.fetchPrinters();

      expect(await repo.wledCapability.supported, isTrue);
    });

    test('an empty fleet settles nothing', () async {
      replyPrinters(const []);

      await repo.fetchPrinters();

      expect(repo.wledCapability.observedAnswer, isNull);
    });

    test('save sends the whole mapping and nothing else', () async {
      adapter.onPatch(
        '/api/v1/printers/4',
        (s) => s.reply(200, {
          'id': 4,
          'name': 'X1C',
          'wled_config': config.toJson(),
        }),
        data: {'wled_config': config.toJson()},
      );

      final saved = await repo.saveWledConfig(4, config);

      expect(saved.wledConfig?.presets, {WledState.printing: 3});
      expect(repo.wledCapability.observedAnswer, isTrue);
    });

    test('a 200 without wled_config is a save that did not happen', () async {
      adapter.onPatch(
        '/api/v1/printers/4',
        (s) => s.reply(200, {'id': 4, 'name': 'X1C'}),
        data: {'wled_config': config.toJson()},
      );

      await expectLater(
        repo.saveWledConfig(4, config),
        throwsA(isA<ApiException>()),
      );
      expect(repo.wledCapability.observedAnswer, isFalse);
    });

    test('a refused URL surfaces as a 422', () async {
      adapter.onPatch(
        '/api/v1/printers/4',
        (s) => s.reply(422, {
          'detail': [
            {'msg': 'Value error, WLED URL must not include credentials'},
          ],
        }),
        data: {'wled_config': config.toJson()},
      );

      await expectLater(
        repo.saveWledConfig(4, config),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
    });

    test('presets are read as the server lists them; a row without an id '
        'is skipped and one without a name is named by its id', () async {
      adapter.onPost(
        '/api/v1/printers/4/wled/presets',
        (s) => s.reply(200, [
          {'id': 1, 'name': 'Idle blue'},
          {'name': 'no id'},
          {'id': 9},
        ]),
        data: {'base_url': 'http://wled.local'},
      );

      expect(await repo.fetchWledPresets(4, 'http://wled.local'), [
        (id: 1, name: 'Idle blue'),
        (id: 9, name: '9'),
      ]);
    });

    test('a WLED that does not answer is a 502', () async {
      adapter.onPost(
        '/api/v1/printers/4/wled/test-connection',
        (s) => s.reply(502, {'detail': 'Could not connect to WLED'}),
        data: {'base_url': 'http://wled.local'},
      );

      await expectLater(
        repo.testWledConnection(4, 'http://wled.local'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
      );
    });

    test('test-connection reads name and version, both optional', () async {
      adapter.onPost(
        '/api/v1/printers/4/wled/test-connection',
        (s) => s.reply(200, {'name': 'Shelf strip', 'version': null}),
        data: {'base_url': 'http://wled.local'},
      );

      expect(await repo.testWledConnection(4, 'http://wled.local'), (
        name: 'Shelf strip',
        version: null,
      ));
    });

    test('test-preset sends the URL and the preset', () async {
      adapter.onPost(
        '/api/v1/printers/4/wled/test-preset',
        (s) => s.reply(200, {'success': true}),
        data: {'base_url': 'http://wled.local', 'preset_id': 3},
      );

      await repo.testWledPreset(4, 'http://wled.local', 3);
    });
  });
}
