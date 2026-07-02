import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const baseUrl = 'http://server.local:8000';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late InMemoryCredentialsStore store;
  late AuthService service;

  setUp(() {
    dio = Dio();
    adapter = DioAdapter(dio: dio);
    store = InMemoryCredentialsStore();
    service = AuthService(bareDio: dio, credentials: store);
  });

  group('probeAuthStatus', () {
    test('czyta auth_enabled z /auth/status', () async {
      adapter.onGet(
        '$baseUrl/api/v1/auth/status',
        (server) =>
            server.reply(200, readFixture('auth_status_enabled.json')),
      );

      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isTrue);
      expect(probe.requiresSetup, isFalse);
      // No redirect in this mock → the probed URL is echoed back unchanged.
      expect(probe.baseUrl, baseUrl);
    });

    test('auth wyłączony', () async {
      adapter.onGet(
        '$baseUrl/api/v1/auth/status',
        (server) =>
            server.reply(200, readFixture('auth_status_disabled.json')),
      );

      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
    });

    test('fallback dla starszego serwera: 404 → sonda /printers (200 = off)',
        () async {
      adapter
        ..onGet(
          '$baseUrl/api/v1/auth/status',
          (server) => server.reply(404, {'detail': 'Not Found'}),
        )
        ..onGet(
          '$baseUrl/api/v1/printers/',
          (server) => server.reply(200, readFixture('printers_list.json')),
        );

      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
    });

    test('fallback: 404 → /printers odpowiada 401 = auth włączony',
        () async {
      adapter
        ..onGet(
          '$baseUrl/api/v1/auth/status',
          (server) => server.reply(404, {'detail': 'Not Found'}),
        )
        ..onGet(
          '$baseUrl/api/v1/printers/',
          (server) => server.reply(401, {'detail': 'Unauthorized'}),
        );

      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isTrue);
    });
  });

  group('login', () {
    test('zapisuje JWT; bez remember nie zapisuje hasła', () async {
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) => server.reply(200, readFixture('login_response_ok.json')),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      final token = await service.login(
        baseUrl: baseUrl,
        username: 'tester',
        password: 'sekret',
      );

      expect(token, startsWith('eyJ'));
      expect(store.jwt, token);
      expect(await store.readRememberedLogin(), isNull);
    });

    test('remember=true zapisuje login i hasło', () async {
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) => server.reply(200, readFixture('login_response_ok.json')),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      await service.login(
        baseUrl: baseUrl,
        username: 'tester',
        password: 'sekret',
        remember: true,
      );

      final saved = await store.readRememberedLogin();
      expect(saved?.username, 'tester');
      expect(saved?.password, 'sekret');
    });

    test('requires_2fa → AuthException, JWT niezapisany', () async {
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) =>
            server.reply(200, readFixture('login_response_2fa.json')),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorUnsupported)),
      );
      expect(store.jwt, isNull);
    });

    test('401 → AuthException o złych danych', () async {
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) => server.reply(401, {'detail': 'Invalid credentials'}),
        data: {'username': 'tester', 'password': 'zle'},
      );

      await expectLater(
        service.login(baseUrl: baseUrl, username: 'tester', password: 'zle'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('silentReLogin', () {
    test('null gdy nic nie zapamiętano', () async {
      expect(await service.silentReLogin(baseUrl), isNull);
    });

    test('loguje zapamiętanymi poświadczeniami i zwraca nowy JWT', () async {
      store
        ..username = 'tester'
        ..password = 'sekret';
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) => server.reply(200, readFixture('login_response_ok.json')),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      final token = await service.silentReLogin(baseUrl);
      expect(token, isNotNull);
      expect(store.jwt, token);
    });

    test('null (bez wyjątku) gdy re-login odrzucony', () async {
      store
        ..username = 'tester'
        ..password = 'niewazne';
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (server) => server.reply(401, {'detail': 'Invalid credentials'}),
        data: {'username': 'tester', 'password': 'niewazne'},
      );

      expect(await service.silentReLogin(baseUrl), isNull);
    });
  });

  group('verifyAndStoreApiKey', () {
    test('200 → klucz zapisany', () async {
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (server) => server.reply(200, readFixture('printers_list.json')),
        headers: {'X-API-Key': 'bb_dobry'},
      );

      await service.verifyAndStoreApiKey(baseUrl: baseUrl, apiKey: 'bb_dobry');
      expect(store.apiKey, 'bb_dobry');
    });

    test('403 → AuthException, klucz niezapisany', () async {
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (server) => server.reply(403, {'detail': 'Missing scope'}),
        headers: {'X-API-Key': 'bb_slaby'},
      );

      await expectLater(
        service.verifyAndStoreApiKey(baseUrl: baseUrl, apiKey: 'bb_slaby'),
        throwsA(isA<AuthException>()),
      );
      expect(store.apiKey, isNull);
    });
  });
}
