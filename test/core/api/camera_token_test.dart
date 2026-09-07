import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/camera_token.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://s.local:8000';
const _tokenPath = '/api/v1/printers/camera/stream-token';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late CameraTokenService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    adapter = DioAdapter(dio: dio);
    service = CameraTokenService(dio);
  });

  group('token()', () {
    test('mints and returns a token from the server', () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {'token': 'abc'}),
      );

      final result = await service.token();
      expect(result, 'abc');
    });

    test('a second attempt uses the cache (the same token)', () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {'token': 'abc'}),
      );

      final first = await service.token();
      // The second call makes no network request — the adapter has no
      // second entry for this path, but the token should come back from cache.
      final second = await service.token();
      expect(second, first);
      expect(second, 'abc');
    });

    test(
      'a token past its lifetime is minted again, not served from cache',
      () async {
        // The cache keeps a token for 55 minutes. Nothing used to exercise the
        // far side of that: the service read the wall clock, so the only way to
        // reach the lapse was to wait for it.
        // Answered from an interceptor rather than the mock adapter: the
        // adapter's route handler runs once, when the route is declared, so it
        // cannot hand out a different token to the second request.
        var minted = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              minted++;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'token': 'abc$minted'},
                ),
              );
            },
          ),
        );

        final issued = DateTime(2026, 9, 3, 12);
        expect(await withClock(Clock.fixed(issued), service.token), 'abc1');
        expect(
          await withClock(
            Clock.fixed(issued.add(const Duration(minutes: 54))),
            service.token,
          ),
          'abc1',
          reason: 'still inside the lifetime',
        );
        expect(
          await withClock(
            Clock.fixed(issued.add(const Duration(minutes: 56))),
            service.token,
          ),
          'abc2',
        );
      },
    );

    test(
      'malformed (no token field) → ApiException malformedResponse',
      () async {
        adapter.onPost(_tokenPath, (server) => server.reply(200, {}));

        await expectLater(
          service.token(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.malformedResponse,
            ),
          ),
        );
      },
    );

    test(
      'malformed (token is not a string) → ApiException malformedResponse',
      () async {
        adapter.onPost(
          _tokenPath,
          (server) => server.reply(200, {'token': 123}),
        );

        await expectLater(
          service.token(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.malformedResponse,
            ),
          ),
        );
      },
    );

    test('a network error → AppApiException', () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.throws(
          500,
          DioException(
            requestOptions: RequestOptions(path: _tokenPath),
            type: DioExceptionType.connectionError,
          ),
        ),
      );

      await expectLater(service.token(), throwsA(isA<AppApiException>()));
    });
  });
}
