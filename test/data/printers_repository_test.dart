import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
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
    adapter = DioAdapter(dio: dio);
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
}
