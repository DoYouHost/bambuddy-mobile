import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ServerSettingsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = ServerSettingsRepository(dio);
  });

  group('fetch', () {
    test('reads the map', () async {
      adapter.onGet(
        '/api/v1/settings',
        (s) => s.reply(200, {'require_plate_clear': true}),
      );

      expect(await repo.fetch(), {'require_plate_clear': true});
    });

    test('a failure is an empty map, not a thrown screen', () async {
      adapter.onGet('/api/v1/settings', (s) => s.reply(500, {'detail': 'no'}));

      expect(await repo.fetch(), isEmpty);
    });
  });

  group('update', () {
    test(
      'goes to the slashed path, which is the only one PUT is registered on',
      () async {
        // Without the slash FastAPI answers a redirect and Dio replays it as a
        // GET: a 200, and nothing written. Registering the mock on the unslashed
        // path instead would make this test pass over exactly that bug.
        adapter.onPut(
          '/api/v1/settings/',
          (s) => s.reply(200, {'queue_keep_bed_warm': true}),
          data: {'queue_keep_bed_warm': true},
        );
        final log = captureRequests(dio);

        final answer = await repo.update({'queue_keep_bed_warm': true});

        expect(log.calls, ['PUT /api/v1/settings/']);
        expect(answer, {'queue_keep_bed_warm': true});
      },
    );

    test('carries only the keys it was given', () async {
      adapter.onPut(
        '/api/v1/settings/',
        (s) => s.reply(200, const <String, dynamic>{}),
        data: {'preheat_soak_seconds': 600},
      );
      final log = captureRequests(dio);

      await repo.update({'preheat_soak_seconds': 600});

      expect(log.last.data, {'preheat_soak_seconds': 600});
    });

    test('a refusal throws and is remembered', () async {
      adapter.onPut(
        '/api/v1/settings/',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        data: {'queue_shortest_first': true},
      );

      expect(await repo.writable(), isTrue, reason: 'nothing tried yet');
      await expectLater(
        repo.update({'queue_shortest_first': true}),
        throwsA(isA<AppApiException>()),
      );
      expect(
        await repo.writable(),
        isFalse,
        reason: 'the route outranks whatever /auth/me claimed',
      );
    });

    test(
      'a failure that says nothing about permission leaves the latch alone',
      () async {
        adapter.onPut(
          '/api/v1/settings/',
          (s) => s.reply(500, {'detail': 'boom'}),
          data: {'queue_shortest_first': true},
        );

        await expectLater(
          repo.update({'queue_shortest_first': true}),
          throwsA(isA<AppApiException>()),
        );
        expect(await repo.writable(), isTrue);
      },
    );
  });
}
