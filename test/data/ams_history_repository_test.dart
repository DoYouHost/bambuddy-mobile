import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AmsHistoryRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = AmsHistoryRepository(dio);
  });

  test('fetch: parses points and stats, reads time as UTC', () async {
    adapter.onGet(
      '/api/v1/ams-history/1/0',
      (s) => s.reply(200, {
        'printer_id': 1,
        'ams_id': 0,
        'data': [
          // Naive stamp — the server sends UTC without the `Z`.
          {
            'recorded_at': '2026-08-16T10:00:00',
            'humidity': 22.5,
            'temperature': 27.1,
          },
          'not-a-point',
        ],
        'min_humidity': 19.0,
        'avg_temperature': 27.5,
      }),
      queryParameters: {'hours': 24},
    );

    final history = await repo.fetch(1, 0);

    expect(history.points, hasLength(1)); // string entry skipped
    expect(history.points.single.humidity, 22.5);
    expect(
      history.points.single.recordedAt.toUtc(),
      DateTime.utc(2026, 8, 16, 10),
    );
    expect(history.minHumidity, 19.0);
    expect(history.avgTemperature, 27.5);
  });

  group('whether to offer a chart at all', () {
    test(
      'yes by default — the route is older than every supported server',
      () async {
        expect(await repo.supportsHistory(), isTrue);
      },
    );

    test('403 (a key without ams_history:read) leaves only the read', () async {
      adapter.onGet(
        '/api/v1/ams-history/1/0',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        queryParameters: {'hours': 24},
      );

      await expectLater(
        () => repo.fetch(1, 0),
        throwsA(isA<AppApiException>()),
      );

      expect(await repo.supportsHistory(), isFalse);
    });

    test(
      '404 also hides the chart, and a successful response restores it',
      () async {
        adapter
          ..onGet(
            '/api/v1/ams-history/1/0',
            (s) => s.reply(404, {'detail': 'Not Found'}),
            queryParameters: {'hours': 24},
          )
          ..onGet(
            '/api/v1/ams-history/1/0',
            (s) => s.reply(200, {
              'printer_id': 1,
              'ams_id': 0,
              'data': <Object>[],
            }),
            queryParameters: {'hours': 6},
          );

        await expectLater(
          () => repo.fetch(1, 0),
          throwsA(isA<AppApiException>()),
        );
        expect(await repo.supportsHistory(), isFalse);

        await repo.fetch(1, 0, hours: 6);

        expect(await repo.supportsHistory(), isTrue);
      },
    );
  });
}
