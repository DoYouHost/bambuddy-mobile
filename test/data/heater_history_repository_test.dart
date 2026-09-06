import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HeaterHistoryRepository repo;

  setUp(() {
    dio = testDio();
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
          'not-a-point',
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

  test(
    'fetch: parses series, skips an invalid point, reads time as UTC',
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
      expect(nozzle.points, hasLength(2)); // string entry skipped
      expect(nozzle.points.first.value, 219.8);
      expect(nozzle.points.first.target, 220);
      expect(
        nozzle.points.first.recordedAt.isUtc,
        isFalse,
      ); // local time for the chart
      expect(
        nozzle.points.first.recordedAt.toUtc(),
        DateTime.utc(2026, 8, 16, 10),
      );
      expect(nozzle.points.last.value, isNull); // a gap in the record, not zero
      expect(nozzle.avgValue, 180.2);

      expect(history.seriesFor('bed')!.isEmpty, isTrue);
      expect(history.seriesFor('chamber'), isNull); // an unrequested sensor
    },
  );

  test('fetch: without kinds asks for all sensors', () async {
    adapter.onGet(
      '/api/v1/printer-sensor-history/3',
      (s) => s.reply(200, {'printer_id': 3, 'series': <Object>[]}),
      queryParameters: {'hours': 6},
    );

    final history = await repo.fetch(3, hours: 6);

    expect(history.series, isEmpty);
  });

  test(
    'fetch: 404 (an old server without this route) flows out as AppApiException',
    () async {
      adapter.onGet(
        '/api/v1/printer-sensor-history/3',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        queryParameters: {'hours': 24},
      );

      expect(
        () => repo.fetch(3),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    },
  );

  group('whether to offer a chart at all', () {
    /// The route landed in v0.2.4.8, still under the old numbering — the
    /// threshold must catch both schemes.
    test('server version: 0.2.4.7 no, 0.2.4.8 and 1.2.5 yes', () async {
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

    test('an unknown version is not an old server — the chart stays', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(await repo.supportsHistory(), isTrue);
    });

    test('without a version service it also stays', () async {
      expect(await HeaterHistoryRepository(dio).supportsHistory(), isTrue);
    });

    test(
      'a 404 from the route overrides a version that claimed otherwise',
      () async {
        replyVersion('1.2.5.1');
        adapter.onGet(
          '/api/v1/printer-sensor-history/3',
          (s) => s.reply(404, {'detail': 'Not Found'}),
          queryParameters: {'hours': 24},
        );
        expect(await repo.supportsHistory(), isTrue);

        await expectLater(() => repo.fetch(3), throwsA(isA<AppApiException>()));

        expect(await repo.supportsHistory(), isFalse);
      },
    );

    test(
      '403 (a key without permission) hides the chart despite the route existing',
      () async {
        replyVersion('1.2.5.1');
        adapter.onGet(
          '/api/v1/printer-sensor-history/3',
          (s) => s.reply(403, {'detail': 'Missing required permissions'}),
          queryParameters: {'hours': 24},
        );

        await expectLater(() => repo.fetch(3), throwsA(isA<AppApiException>()));

        expect(await repo.supportsHistory(), isFalse);
      },
    );

    test('a successful response clears an earlier refusal', () async {
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
