import 'package:bambuddy_mobile/core/api/ws_token.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = 'http://s.local:8000';

/// Counts the mints and answers with [status], which the mock adapter cannot do
/// — its route handler runs once, when the route is declared.
class _MintStub extends Interceptor {
  var status = 404;
  var mints = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    mints++;
    if (status != 200) {
      return handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: status),
        ),
      );
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {'token': 'tok$mints'},
      ),
    );
  }
}

/// The absence of a route is cached like the presence of a token. Exercised
/// through `WsTokenService`, where a handshake retried every few seconds used
/// to fire one 404 POST per attempt for as long as the app was pointed at a
/// server predating the endpoint.
void main() {
  late Dio dio;
  late _MintStub mint;
  late WsTokenService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    mint = _MintStub();
    dio.interceptors.add(mint);
    service = WsTokenService(dio);
  });

  test('a missing route is asked for once, not once per use', () async {
    expect(await service.token(), isNull);
    expect(await service.token(), isNull);
    expect(await service.token(), isNull);

    expect(mint.mints, 1);
    expect(service.routeAbsent, isTrue);
  });

  test('invalidate re-probes, so an upgraded server is picked up', () async {
    expect(await service.token(), isNull);

    mint.status = 200;
    service.invalidate();

    expect(await service.token(), 'tok2');
    expect(service.routeAbsent, isFalse);
  });

  test('a forced refresh re-probes as well', () async {
    expect(await service.token(), isNull);

    mint.status = 200;

    expect(await service.token(forceRefresh: true), 'tok2');
  });

  test('405 is an absence too — that is what bambuddy answers', () async {
    // The SPA catch-all is GET-only (`@app.get("/{full_path:path}")`), so a
    // POST to a mint the server does not have matches its path but not its
    // method: Starlette replies 405 and never reaches its own 404. Reading
    // only 404 here is what left every media request without a credential on
    // a pre-#3025 server.
    mint.status = 405;

    expect(await service.token(), isNull);
    expect(service.routeAbsent, isTrue);
  });

  test('a route that answers is not marked absent', () async {
    mint.status = 200;

    expect(await service.token(), 'tok1');
    expect(service.routeAbsent, isFalse);
  });

  test(
    'a refusal is not an absence — it neither caches nor swallows',
    () async {
      // 401 says "not you", 404 says "not here". Caching the first would strand
      // the app on a token it could mint the moment the session came back.
      mint.status = 401;

      await expectLater(service.token(), throwsA(isA<Object>()));
      expect(service.routeAbsent, isFalse);
    },
  );
}
