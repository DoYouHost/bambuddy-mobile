import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/media_token.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://s.local:8000';
const _tokenPath = '/api/v1/auth/media-token';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late MediaTokenService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    adapter = DioAdapter(dio: dio);
    service = MediaTokenService(dio);
  });

  test('mints and returns a token from the server', () async {
    adapter.onPost(_tokenPath, (server) => server.reply(200, {'token': 'abc'}));

    expect(await service.token(), 'abc');
  });

  test('404 is a server older than #3025, not an error', () async {
    // The one thing that tells the two server generations apart — nothing here
    // is gated on the reported version.
    adapter.onPost(_tokenPath, (server) => server.reply(404, {}));

    expect(await service.token(), isNull);
  });

  test('a 200 without a token field is malformed, not an old server', () async {
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
  });

  test(
    'a refusal is an error — an unauthenticated caller is not an old server',
    () async {
      adapter.onPost(_tokenPath, (server) => server.reply(401, {}));

      await expectLater(service.token(), throwsA(isA<AuthException>()));
    },
  );
}
