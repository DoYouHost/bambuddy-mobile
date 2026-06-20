import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late MaintenanceRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = MaintenanceRepository(dio);
  });

  test('fetchOverview: parsuje, pomija niepoprawny wpis listy', () async {
    adapter.onGet(
      '/api/v1/maintenance/overview',
      (s) => s.reply(200, readFixture('maintenance_overview.json')),
    );

    final printers = await repo.fetchOverview();

    expect(printers, hasLength(1)); // wpis-string pominięty
    final p = printers.first;
    expect(p.printerName, 'X2D-3DP');
    expect(p.maintenanceItems, hasLength(2));
    expect(p.dueItems.map((i) => i.id), [10]);
    final due = p.maintenanceItems.first;
    expect(due.isDue, isTrue);
    expect(due.progress, 1.0); // 60/50 → klamrowane do 1
    expect(due.lastPerformedAt, isNotNull);
  });

  test('fetchPrinter: 500 → null (drukarka nieosiągalna)', () async {
    adapter.onGet(
      '/api/v1/maintenance/printers/1',
      (s) => s.reply(500, {'detail': 'boom'}),
    );

    expect(await repo.fetchPrinter(1), isNull);
  });

  test('fetchPrinter: 401 wypływa jako AuthException', () async {
    adapter.onGet(
      '/api/v1/maintenance/printers/1',
      (s) => s.reply(401, {'detail': 'nope'}),
    );

    expect(
      () => repo.fetchPrinter(1),
      throwsA(isA<AuthException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );
  });

  test('perform: wysyła body {notes} i kończy bez wyjątku', () async {
    Object? sentBody;
    adapter.onPost(
      '/api/v1/maintenance/items/10/perform',
      (s) => s.reply(200, {'id': 10}),
      data: Matchers.any,
    );
    // http_mock_adapter nie przechwytuje body bezpośrednio — sprawdzamy przez
    // interceptor, że żądanie poszło z oczekiwanym kształtem.
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      sentBody = o.data;
      h.next(o);
    }));

    await repo.perform(10, notes: 'wyczyszczone');

    expect(sentBody, {'notes': 'wyczyszczone'});
  });

  test('perform: 403 → AuthException(forbidden)', () async {
    adapter.onPost(
      '/api/v1/maintenance/items/10/perform',
      (s) => s.reply(403, {'detail': 'forbidden'}),
      data: Matchers.any,
    );

    expect(
      () => repo.perform(10),
      throwsA(isA<AuthException>()
          .having((e) => e.code, 'code', AppErrorCode.forbidden)),
    );
  });
}
