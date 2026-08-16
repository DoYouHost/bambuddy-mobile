import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AmsHistoryRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = AmsHistoryRepository(dio);
  });

  test('fetch: parsuje punkty i statystyki, czyta czas jako UTC', () async {
    adapter.onGet(
      '/api/v1/ams-history/1/0',
      (s) => s.reply(200, {
        'printer_id': 1,
        'ams_id': 0,
        'data': [
          // Naive stamp — the server sends UTC without the `Z`.
          {'recorded_at': '2026-08-16T10:00:00', 'humidity': 22.5, 'temperature': 27.1},
          'nie-punkt',
        ],
        'min_humidity': 19.0,
        'avg_temperature': 27.5,
      }),
      queryParameters: {'hours': 24},
    );

    final history = await repo.fetch(1, 0);

    expect(history.points, hasLength(1)); // wpis-string pominięty
    expect(history.points.single.humidity, 22.5);
    expect(history.points.single.recordedAt.toUtc(),
        DateTime.utc(2026, 8, 16, 10));
    expect(history.minHumidity, 19.0);
    expect(history.avgTemperature, 27.5);
  });

  group('czy w ogóle proponować wykres', () {
    test('domyślnie tak — trasa jest starsza niż każdy wspierany serwer',
        () async {
      expect(await repo.supportsHistory(), isTrue);
    });

    test('403 (klucz bez ams_history:read) zostawia sam odczyt', () async {
      adapter.onGet(
        '/api/v1/ams-history/1/0',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        queryParameters: {'hours': 24},
      );

      await expectLater(() => repo.fetch(1, 0), throwsA(isA<AppApiException>()));

      expect(await repo.supportsHistory(), isFalse);
    });

    test('404 też chowa wykres, a udana odpowiedź go przywraca', () async {
      adapter
        ..onGet(
          '/api/v1/ams-history/1/0',
          (s) => s.reply(404, {'detail': 'Not Found'}),
          queryParameters: {'hours': 24},
        )
        ..onGet(
          '/api/v1/ams-history/1/0',
          (s) => s.reply(200, {'printer_id': 1, 'ams_id': 0, 'data': <Object>[]}),
          queryParameters: {'hours': 6},
        );

      await expectLater(() => repo.fetch(1, 0), throwsA(isA<AppApiException>()));
      expect(await repo.supportsHistory(), isFalse);

      await repo.fetch(1, 0, hours: 6);

      expect(await repo.supportsHistory(), isTrue);
    });
  });
}
