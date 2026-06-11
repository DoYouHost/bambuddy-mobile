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
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = PrintersRepository(dio);
  });

  test('fetchAll: lista + statusy', () async {
    adapter
      ..onGet(
        '/api/v1/printers',
        (server) => server.reply(200, readFixture('printers_list.json')),
      )
      ..onGet(
        '/api/v1/printers/1/status',
        (server) =>
            server.reply(200, readFixture('printer_status_printing.json')),
      )
      ..onGet(
        '/api/v1/printers/2/status',
        (server) =>
            server.reply(200, readFixture('printer_status_idle.json')),
      );

    final all = await repo.fetchAll();

    expect(all, hasLength(2));
    expect(all[0].printer.name, 'X1C Warsztat');
    expect(all[0].status?.state, 'RUNNING');
    expect(all[1].status?.state, 'IDLE');
  });

  test('padnięty status jednej drukarki nie wywala dashboardu', () async {
    adapter
      ..onGet(
        '/api/v1/printers',
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
  });

  test('niesparsowalny wpis na liście jest pomijany', () async {
    adapter.onGet(
      '/api/v1/printers',
      (server) => server.reply(200, [
        {'id': 1, 'name': 'OK'},
        {'name': 'bez id — odpada'},
        'śmieć',
      ]),
    );

    final printers = await repo.fetchPrinters();
    expect(printers, hasLength(1));
    expect(printers.single.name, 'OK');
  });

  test('401 na liście → AuthException (UI odsyła do konfiguracji)',
      () async {
    adapter.onGet(
      '/api/v1/printers',
      (server) => server.reply(401, {'detail': 'Unauthorized'}),
    );

    await expectLater(repo.fetchPrinters(), throwsA(isA<AuthException>()));
  });

  test('401 na statusie też wypływa jako AuthException', () async {
    adapter
      ..onGet(
        '/api/v1/printers',
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
      '/api/v1/printers',
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/printers'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    );

    await expectLater(repo.fetchPrinters(), throwsA(isA<NetworkException>()));
  });
}
