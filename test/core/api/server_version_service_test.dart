import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ServerVersionService service;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    service = ServerVersionService(dio);
  });

  /// Counts the requests that really left the app and answers them here.
  /// A counter inside `adapter.onGet(...)` counts route REGISTRATIONS — the
  /// handler is invoked once, when the route is declared — so it reads `1`
  /// whether the service asked once, twice or never.
  int Function() countingReplies(Response<dynamic> Function() reply) {
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          final staged = reply();
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: staged.statusCode,
              data: staged.data,
            ),
          );
        },
      ),
    );
    return () => requests;
  }

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (server) => server.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  test('reads the version and recognizes tri-state', () async {
    replyVersion('1.2.5.1');

    expect((await service.current())?.raw, '1.2.5.1');
    expect(await service.supports(ServerFeature.triStateCalibration), isTrue);
    expect(await service.reportedVersion(), '1.2.5.1');
  });

  test('an older server: no tri-state', () async {
    replyVersion('0.2.4.9');

    expect(await service.supports(ServerFeature.triStateCalibration), isFalse);
  });

  test('asks once, then uses the remembered response', () async {
    final calls = countingReplies(
      () => Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {'version': '1.2.5', 'repo': 'x/y'},
      ),
    );

    await service.current();
    await service.current();
    await service.supports(ServerFeature.triStateCalibration);

    expect(
      calls(),
      1,
      reason: 'the version does not change without a server restart',
    );
  });

  test('concurrent calls share a single request', () async {
    final calls = countingReplies(
      () => Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {'version': '1.2.5', 'repo': 'x/y'},
      ),
    );

    await Future.wait([
      service.current(),
      service.current(),
      service.current(),
    ]);

    expect(calls(), 1);
  });

  test('cached: without a network call it does not guess', () async {
    replyVersion('1.2.5');
    expect(service.cached, isNull, reason: 'nothing is known before a read');

    await service.current();

    expect(service.cached?.raw, '1.2.5');
  });

  group('server does not answer with what we expect', () {
    test('HTTP error → no version, no exception', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(500, null),
      );

      expect(await service.current(), isNull);
      expect(
        await service.supports(ServerFeature.triStateCalibration),
        isFalse,
        reason: 'unknown is treated as older',
      );
      expect(await service.reportedVersion(), isNull);
    });

    test('404 (route moved) is also an answer, not a failure', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(404, null),
      );

      expect(await service.current(), isNull);
    });

    test('a non-version in the version field → no version', () async {
      replyVersion('not-a-version');

      expect(await service.current(), isNull);
    });

    test('body without a version field', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'repo': 'x/y'}),
      );

      expect(await service.current(), isNull);
    });

    test('a failed read is not remembered permanently', () async {
      // A probe that hit a moment without a network must not disable a feature
      // for the whole session — otherwise one offline moment costs the feature
      // until the app restarts.
      final calls = countingReplies(
        () => Response(requestOptions: RequestOptions(), statusCode: 500),
      );

      await service.current();
      await service.current();

      expect(
        calls(),
        1,
        reason: 'inside the retry window it does not hit the server again',
      );
      expect(service.cached, isNull);
    });

    test('past the retry window the read is attempted again', () async {
      // The other half of the rule above, and the half that decides whether a
      // feature comes back at all: a probe that met a moment without a network
      // has to be retried once the window is out, not once the app restarts.
      final calls = countingReplies(
        () => Response(requestOptions: RequestOptions(), statusCode: 500),
      );

      final failedAt = DateTime(2026, 9, 3, 12);
      await withClock(Clock.fixed(failedAt), () async {
        await service.current();
        await service.current();
      });
      expect(calls(), 1, reason: 'inside the window the server is left alone');

      await withClock(
        Clock.fixed(failedAt.add(const Duration(minutes: 6))),
        () async {
          await service.current();
        },
      );
      expect(calls(), 2);
    });
  });
}
