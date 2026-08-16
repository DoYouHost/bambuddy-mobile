import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HeaterHistoryRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = HeaterHistoryRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
      );

  Map<String, dynamic> response() => {
        'printer_id': 3,
        'series': [
          {
            'sensor_kind': 'nozzle',
            'data': [
              // Naive stamp — the server sends UTC without the `Z`.
              {'recorded_at': '2026-08-16T10:00:00', 'value': 219.8, 'target': 220},
              {'recorded_at': '2026-08-16T10:01:00', 'value': null, 'target': null},
              'nie-punkt',
            ],
            'min_value': 24.0,
            'max_value': 220.4,
            'avg_value': 180.2,
          },
          {
            'sensor_kind': 'bed',
            'data': <Object>[],
            'min_value': null,
            'max_value': null,
            'avg_value': null,
          },
        ],
      };

  test('fetch: parsuje serie, pomija niepoprawny punkt, czyta czas jako UTC',
      () async {
    adapter.onGet(
      '/api/v1/printer-sensor-history/3',
      (s) => s.reply(200, response()),
      queryParameters: {'hours': 24, 'kinds': 'nozzle,bed'},
    );

    final history = await repo.fetch(3, kinds: const ['nozzle', 'bed']);

    expect(history.printerId, 3);
    expect(history.series, hasLength(2));

    final nozzle = history.seriesFor('nozzle')!;
    expect(nozzle.points, hasLength(2)); // wpis-string pominięty
    expect(nozzle.points.first.value, 219.8);
    expect(nozzle.points.first.target, 220);
    expect(nozzle.points.first.recordedAt.isUtc, isFalse); // lokalny czas do wykresu
    expect(
      nozzle.points.first.recordedAt.toUtc(),
      DateTime.utc(2026, 8, 16, 10),
    );
    expect(nozzle.points.last.value, isNull); // luka w zapisie, nie zero
    expect(nozzle.avgValue, 180.2);

    expect(history.seriesFor('bed')!.isEmpty, isTrue);
    expect(history.seriesFor('chamber'), isNull); // nieproszony czujnik
  });

  test('fetch: bez kinds pyta o wszystkie czujniki', () async {
    adapter.onGet(
      '/api/v1/printer-sensor-history/3',
      (s) => s.reply(200, {'printer_id': 3, 'series': <Object>[]}),
      queryParameters: {'hours': 6},
    );

    final history = await repo.fetch(3, hours: 6);

    expect(history.series, isEmpty);
  });

  test('fetch: 404 (stary serwer bez tej trasy) wypływa jako AppApiException',
      () async {
    adapter.onGet(
      '/api/v1/printer-sensor-history/3',
      (s) => s.reply(404, {'detail': 'Not Found'}),
      queryParameters: {'hours': 24},
    );

    expect(
      () => repo.fetch(3),
      throwsA(isA<AppApiException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  group('czy w ogóle proponować wykres', () {
    /// Trasa weszła w v0.2.4.8, czyli jeszcze w starym numerowaniu — próg musi
    /// łapać oba schematy.
    test('wersja serwera: 0.2.4.7 nie, 0.2.4.8 i 1.2.5 tak', () async {
      replyVersion('0.2.4.7');
      expect(await repo.supportsHistory(), isFalse);

      final newer = HeaterHistoryRepository(dio, ServerVersionService(dio));
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': '0.2.4.8', 'repo': 'x/y'}),
      );
      expect(await newer.supportsHistory(), isTrue);

      final current = HeaterHistoryRepository(dio, ServerVersionService(dio));
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': '1.2.5.1', 'repo': 'x/y'}),
      );
      expect(await current.supportsHistory(), isTrue);
    });

    test('nieznana wersja to nie stary serwer — wykres zostaje', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(await repo.supportsHistory(), isTrue);
    });

    test('bez usługi wersji też zostaje', () async {
      expect(await HeaterHistoryRepository(dio).supportsHistory(), isTrue);
    });

    test('404 z trasy przebija wersję, która twierdziła inaczej', () async {
      replyVersion('1.2.5.1');
      adapter.onGet(
        '/api/v1/printer-sensor-history/3',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        queryParameters: {'hours': 24},
      );
      expect(await repo.supportsHistory(), isTrue);

      await expectLater(() => repo.fetch(3), throwsA(isA<AppApiException>()));

      expect(await repo.supportsHistory(), isFalse);
    });

    test('403 (klucz bez uprawnienia) chowa wykres mimo istniejącej trasy',
        () async {
      replyVersion('1.2.5.1');
      adapter.onGet(
        '/api/v1/printer-sensor-history/3',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        queryParameters: {'hours': 24},
      );

      await expectLater(() => repo.fetch(3), throwsA(isA<AppApiException>()));

      expect(await repo.supportsHistory(), isFalse);
    });

    test('udana odpowiedź kasuje wcześniejszą odmowę', () async {
      replyVersion('1.2.5.1');
      adapter
        ..onGet(
          '/api/v1/printer-sensor-history/3',
          (s) => s.reply(403, {'detail': 'nope'}),
          queryParameters: {'hours': 24},
        )
        ..onGet(
          '/api/v1/printer-sensor-history/3',
          (s) => s.reply(200, {'printer_id': 3, 'series': <Object>[]}),
          queryParameters: {'hours': 6},
        );

      await expectLater(() => repo.fetch(3), throwsA(isA<AppApiException>()));
      expect(await repo.supportsHistory(), isFalse);

      await repo.fetch(3, hours: 6);

      expect(await repo.supportsHistory(), isTrue);
    });
  });
}
