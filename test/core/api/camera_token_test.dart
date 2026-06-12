import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/camera_token.dart';
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
    test('mintuje i zwraca token z serwera', () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {'token': 'abc'}),
      );

      final result = await service.token();
      expect(result, 'abc');
    });

    test('druga próba używa cache (ten sam token)', () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {'token': 'abc'}),
      );

      final first = await service.token();
      // Drugi call nie wykonuje żadnego żądania sieciowego — adapter nie ma
      // kolejnego wpisu dla tej ścieżki, ale token powinien wrócić z cache.
      final second = await service.token();
      expect(second, first);
      expect(second, 'abc');
    });

    test('malformed (brak pola token) → ApiException malformedResponse',
        () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {}),
      );

      await expectLater(
        service.token(),
        throwsA(isA<ApiException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.malformedResponse,
        )),
      );
    });

    test('malformed (token nie jest stringiem) → ApiException malformedResponse',
        () async {
      adapter.onPost(
        _tokenPath,
        (server) => server.reply(200, {'token': 123}),
      );

      await expectLater(
        service.token(),
        throwsA(isA<ApiException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.malformedResponse,
        )),
      );
    });

    test('błąd sieci → AppApiException', () async {
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

      await expectLater(
        service.token(),
        throwsA(isA<AppApiException>()),
      );
    });
  });
}
