import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  const path = '/api/v1/spoolman/inventory/spools/7/usage';

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
  });

  Future<dynamic> fetch() => SpoolmanInventorySource(dio).fetchUsage(7);

  test('reads the charges a Spoolman spool was billed for', () async {
    adapter.onGet(
      path,
      (s) => s.reply(200, [
        {
          'id': 3,
          'spool_id': null,
          'spoolman_spool_id': 7,
          'print_name': 'Bag dispenser',
          'weight_used': 96.2,
          'percent_used': 10,
          'status': 'completed',
          'cost': null,
          'created_at': '2026-11-01T10:00:00',
        },
      ]),
    );

    final rows = await fetch();

    expect(rows, hasLength(1));
    expect(rows.single.printName, 'Bag dispenser');
    expect(rows.single.weightUsed, 96.2);
    expect(rows.single.cost, isNull);
    expect(
      rows.single.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 1, 10)),
      isTrue,
    );
  });

  test('a spool never charged has an empty history', () async {
    adapter.onGet(path, (s) => s.reply(200, const []));

    expect(await fetch(), isEmpty);
  });

  // Servers before 1.3.1 keep no per-print record in Spoolman mode and have
  // no route; the sheet must read as "no history", not as a failure.
  test('an older server without the route reads as empty', () async {
    adapter.onGet(path, (s) => s.reply(404, {'detail': 'Not Found'}));

    expect(await fetch(), isEmpty);
  });

  test('a refusal other than 404 is still an error', () {
    adapter.onGet(path, (s) => s.reply(403, {'detail': 'Forbidden'}));

    expect(fetch, throwsA(isA<AppApiException>()));
  });

  test('a server error is still an error', () {
    adapter.onGet(path, (s) => s.reply(500, {'detail': 'boom'}));

    expect(fetch, throwsA(isA<AppApiException>()));
  });
}
