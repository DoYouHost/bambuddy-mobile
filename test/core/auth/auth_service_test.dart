import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const baseUrl = 'http://server.local:8000';

/// Adapter that counts requests per path and can hold a response open, for the
/// cases where *how many times* the app called the server is the assertion.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.respond);

  /// Returns the body for a request, or a future that completes later.
  final Future<ResponseBody> Function(RequestOptions options, int callNo)
      respond;

  final calls = <RequestOptions>[];

  int countOf(String pathEnd) =>
      calls.where((o) => o.path.endsWith(pathEnd)).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls.add(options);
    return respond(options, calls.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

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

  // The callback type (`MockServerCallback`) is not exported by the package, so
  // the parameter is typed structurally — `dynamic` is assignable to it.
  void onStatus(void Function(dynamic server) reply) =>
      adapter.onGet('$baseUrl/api/v1/auth/status', reply);

  group('probeAuthStatus — the two flags', () {
    // `requires_setup` is `not setup_completed` on the server and says nothing
    // about auth; the two flags are independent and all four combinations are
    // reachable, so the probe reports both and lets the caller decide.
    test('auth on, setup done', () async {
      onStatus((s) => s.reply(200, readFixture('auth_status_enabled.json')));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isTrue);
      expect(probe.requiresSetup, isFalse);
      // No redirect in this mock → the probed URL is echoed back unchanged.
      expect(probe.baseUrl, baseUrl);
    });

    test('auth off, setup done', () async {
      onStatus((s) => s.reply(200, readFixture('auth_status_disabled.json')));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
      expect(probe.requiresSetup, isFalse);
    });

    test('auth on, setup flag still pending — a working, reachable server',
        () async {
      // The reported case: an install whose `setup_completed` row is missing
      // reports requires_setup forever while auth works fine.
      onStatus(
          (s) => s.reply(200, readFixture('auth_status_setup_pending.json')));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isTrue);
      expect(probe.requiresSetup, isTrue);
    });

    test('auth off, setup pending — a genuinely fresh server', () async {
      onStatus(
          (s) => s.reply(200, readFixture('auth_status_fresh_server.json')));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
      expect(probe.requiresSetup, isTrue);
    });

    test('an answer without the keys reads as auth off', () async {
      // Deliberate: `== true` and nothing else. Something else answering 200 at
      // this path (a proxy landing page serialized as JSON) therefore looks
      // like an auth-free server, and the first real request 401s. Pinned so
      // the semantics are a decision rather than an accident.
      onStatus((s) => s.reply(200, <String, dynamic>{}));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
      expect(probe.requiresSetup, isFalse);
    });

    test('stringified booleans are not truthy', () async {
      onStatus((s) =>
          s.reply(200, {'auth_enabled': 'true', 'requires_setup': 'true'}));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
      expect(probe.requiresSetup, isFalse);
    });
  });

  group('probeAuthStatus — failures that are not 404', () {
    test('a proxy that is up with bambuddy down surfaces the status', () async {
      // 502/503 through a reverse proxy is the shape of "wrong port / container
      // not running", and it must not be mistaken for either auth mode.
      for (final status in [500, 502, 503]) {
        final localDio = Dio();
        final localAdapter = DioAdapter(dio: localDio);
        final localService =
            AuthService(bareDio: localDio, credentials: store);
        localAdapter.onGet('$baseUrl/api/v1/auth/status',
            (s) => s.reply(status, {'detail': 'nope'}));
        await expectLater(
          localService.probeAuthStatus(baseUrl),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)),
          reason: 'status $status',
        );
      }
    });

    test('429 on the probe → tooManyAttempts', () async {
      onStatus((s) => s.reply(429, {'detail': 'Too many failed attempts.'}));
      await expectLater(
        service.probeAuthStatus(baseUrl),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts)),
      );
    });

    test('unreachable host → NetworkException, no fallback probe', () async {
      onStatus((s) => s.throws(
            0,
            DioException.connectionError(
              requestOptions: RequestOptions(path: '/api/v1/auth/status'),
              reason: 'refused',
            ),
          ));
      await expectLater(
        service.probeAuthStatus(baseUrl),
        throwsA(isA<NetworkException>()
            .having((e) => e.code, 'code', AppErrorCode.serverUnreachable)),
      );
    });
  });

  group('probeAuthStatus — 404 fallback for servers without the endpoint', () {
    void onStatus404() => adapter.onGet(
        '$baseUrl/api/v1/auth/status', (s) => s.reply(404, {'detail': 'Not Found'}));

    test('/printers answers 200 → auth is off', () async {
      onStatus404();
      adapter.onGet('$baseUrl/api/v1/printers/',
          (s) => s.reply(200, readFixture('printers_list.json')));
      final probe = await service.probeAuthStatus(baseUrl);
      expect(probe.authEnabled, isFalse);
      expect(probe.requiresSetup, isFalse);
    });

    test('/printers answers 401 or 403 → auth is on', () async {
      for (final status in [401, 403]) {
        final localDio = Dio();
        final localAdapter = DioAdapter(dio: localDio);
        final localService =
            AuthService(bareDio: localDio, credentials: store);
        localAdapter
          ..onGet('$baseUrl/api/v1/auth/status',
              (s) => s.reply(404, {'detail': 'Not Found'}))
          ..onGet('$baseUrl/api/v1/printers/',
              (s) => s.reply(status, {'detail': 'denied'}));
        final probe = await localService.probeAuthStatus(baseUrl);
        expect(probe.authEnabled, isTrue, reason: 'status $status');
      }
    });

    test('/printers answers 500 → the error surfaces, not a guessed mode',
        () async {
      onStatus404();
      adapter.onGet(
          '$baseUrl/api/v1/printers/', (s) => s.reply(500, {'detail': 'boom'}));
      await expectLater(
        service.probeAuthStatus(baseUrl),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('/printers unreachable → NetworkException', () async {
      onStatus404();
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/printers/'),
            reason: 'refused',
          ),
        ),
      );
      await expectLater(
        service.probeAuthStatus(baseUrl),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('login', () {
    void onLogin(
      void Function(dynamic server) reply, {
      String username = 'tester',
      String password = 'sekret',
    }) =>
        adapter.onPost('$baseUrl/api/v1/auth/login', reply,
            data: {'username': username, 'password': password});

    test('stores the JWT; without remember it stores no password', () async {
      onLogin((s) => s.reply(200, readFixture('login_response_ok.json')));

      final token = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      expect(token, startsWith('eyJ'));
      expect(store.jwt, token);
      expect(await store.readRememberedLogin(), isNull);
    });

    test('remember=true stores username and password', () async {
      onLogin((s) => s.reply(200, readFixture('login_response_ok.json')));

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

    test('a rejected login stores nothing, even with remember=true', () async {
      // Otherwise a typo would be persisted and then replayed by every silent
      // re-login, spending the server's failed-attempt budget in the
      // background — and that budget is shared per IP behind a reverse proxy.
      onLogin((s) => s.reply(401, {'detail': 'Incorrect username or password'}),
          password: 'zle');

      await expectLater(
        service.login(
            baseUrl: baseUrl,
            username: 'tester',
            password: 'zle',
            remember: true),
        throwsA(isA<AuthException>()),
      );
      expect(store.jwt, isNull);
      expect(await store.readRememberedLogin(), isNull);
    });

    test('401 → invalidCredentials', () async {
      onLogin((s) => s.reply(401, {'detail': 'Incorrect username or password'}),
          password: 'zle');
      await expectLater(
        service.login(baseUrl: baseUrl, username: 'tester', password: 'zle'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.invalidCredentials)),
      );
    });

    test('429 → tooManyAttempts, not "wrong password"', () async {
      // The server checks its rate limit before the password, so this is what a
      // locked-out user gets even when they finally type the right one. Telling
      // them the password is wrong would send them rotating credentials.
      onLogin((s) =>
          s.reply(429, {'detail': 'Too many failed attempts. Please try again later.'}));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts)),
      );
      expect(store.jwt, isNull);
    });

    test('400 (auth disabled server-side) is not a credentials problem',
        () async {
      // `POST /auth/login` answers 400 "Authentication is not enabled" when the
      // admin turned auth off while the app was configured for JWT.
      onLogin(
          (s) => s.reply(400, {'detail': 'Authentication is not enabled'}));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.badResponse)
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('500 → badResponse with the status', () async {
      onLogin((s) => s.reply(500, {'detail': 'Internal Server Error'}));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('requires_2fa → refused, and no JWT is stored', () async {
      onLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorUnsupported)),
      );
      expect(store.jwt, isNull);
    });

    test('requires_2fa wins even if a token came along with it', () async {
      // The 2FA answer carries `pre_auth_token`, not an access token, and a
      // future server that sent both must not be treated as a completed login.
      onLogin((s) => s.reply(200, {
            'requires_2fa': true,
            'pre_auth_token': 'pre-auth-xyz',
            'access_token': 'eyJ.looks.real',
            'two_fa_methods': ['totp'],
          }));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorUnsupported)),
      );
      expect(store.jwt, isNull);
    });

    test('a 200 without a usable token → malformedResponse', () async {
      // `access_token` is nullable in the server's own schema, so "200 with no
      // token" is a shape the contract allows and the app must not store.
      final bodies = <Object>[
        <String, dynamic>{},
        {'token_type': 'bearer', 'access_token': null},
        {'access_token': ''},
        {'access_token': 12345},
        {'access_token': ['eyJ']},
      ];
      for (final body in bodies) {
        final localDio = Dio();
        final localAdapter = DioAdapter(dio: localDio);
        final localStore = InMemoryCredentialsStore();
        final localService =
            AuthService(bareDio: localDio, credentials: localStore);
        localAdapter.onPost('$baseUrl/api/v1/auth/login', (s) => s.reply(200, body),
            data: {'username': 'tester', 'password': 'sekret'});
        await expectLater(
          localService.login(
              baseUrl: baseUrl, username: 'tester', password: 'sekret'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', AppErrorCode.malformedResponse)),
          reason: 'body $body',
        );
        expect(localStore.jwt, isNull, reason: 'body $body');
      }
    });

    test('a token with no token_type is still accepted', () async {
      onLogin((s) => s.reply(200, {'access_token': 'eyJ.bare.token'}));
      final token = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');
      expect(token, 'eyJ.bare.token');
      expect(store.jwt, 'eyJ.bare.token');
    });
  });

  group('verifyAndStoreApiKey', () {
    test('200 → key stored, sent as X-API-Key', () async {
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (s) => s.reply(200, readFixture('printers_list.json')),
        headers: {'X-API-Key': 'bb_dobry'},
      );

      await service.verifyAndStoreApiKey(baseUrl: baseUrl, apiKey: 'bb_dobry');
      expect(store.apiKey, 'bb_dobry');
    });

    test('401 and 403 both mean the key is unusable, and nothing is stored',
        () async {
      // 401 is an unknown/revoked key, 403 a valid key without the permission.
      // Neither can drive the app, and both must leave the store empty so the
      // next launch does not retry with a key the server already refused.
      for (final status in [401, 403]) {
        final localDio = Dio();
        final localAdapter = DioAdapter(dio: localDio);
        final localStore = InMemoryCredentialsStore();
        final localService =
            AuthService(bareDio: localDio, credentials: localStore);
        localAdapter.onGet(
          '$baseUrl/api/v1/printers/',
          (s) => s.reply(status, {'detail': 'denied'}),
          headers: {'X-API-Key': 'bb_slaby'},
        );
        await expectLater(
          localService.verifyAndStoreApiKey(
              baseUrl: baseUrl, apiKey: 'bb_slaby'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', AppErrorCode.apiKeyRejected)),
          reason: 'status $status',
        );
        expect(localStore.apiKey, isNull, reason: 'status $status');
      }
    });

    test('a server-side failure is not the key\'s fault, and stores nothing',
        () async {
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (s) => s.reply(500, {'detail': 'boom'}),
        headers: {'X-API-Key': 'bb_dobry'},
      );
      await expectLater(
        service.verifyAndStoreApiKey(baseUrl: baseUrl, apiKey: 'bb_dobry'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.badResponse)),
      );
      expect(store.apiKey, isNull);
    });

    test('an unreachable server stores nothing', () async {
      adapter.onGet(
        '$baseUrl/api/v1/printers/',
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/printers/'),
            reason: 'refused',
          ),
        ),
        headers: {'X-API-Key': 'bb_dobry'},
      );
      await expectLater(
        service.verifyAndStoreApiKey(baseUrl: baseUrl, apiKey: 'bb_dobry'),
        throwsA(isA<NetworkException>()),
      );
      expect(store.apiKey, isNull);
    });
  });

  group('silentReLogin', () {
    test('null when nothing was remembered, and no request is made', () async {
      final counting = _CountingAdapter((o, _) async => _json(<String, dynamic>{}, 200));
      final localDio = Dio()..httpClientAdapter = counting;
      final localService = AuthService(bareDio: localDio, credentials: store);

      expect(await localService.silentReLogin(baseUrl), isNull);
      expect(counting.calls, isEmpty);
    });

    test('logs in with the remembered credentials and returns a fresh JWT',
        () async {
      store
        ..username = 'tester'
        ..password = 'sekret';
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (s) => s.reply(200, readFixture('login_response_ok.json')),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      final token = await service.silentReLogin(baseUrl);
      expect(token, isNotNull);
      expect(store.jwt, token);
    });

    test('null instead of throwing when the server refuses', () async {
      // Callers are interceptors and background timers; an exception there
      // would surface as a crash rather than a redirect to settings.
      for (final status in [401, 429, 500]) {
        final localStore = InMemoryCredentialsStore()
          ..username = 'tester'
          ..password = 'niewazne';
        final localDio = Dio();
        final localAdapter = DioAdapter(dio: localDio);
        final localService =
            AuthService(bareDio: localDio, credentials: localStore);
        localAdapter.onPost(
          '$baseUrl/api/v1/auth/login',
          (s) => s.reply(status, {'detail': 'no'}),
          data: {'username': 'tester', 'password': 'niewazne'},
        );
        expect(await localService.silentReLogin(baseUrl), isNull,
            reason: 'status $status');
        expect(localStore.jwt, isNull, reason: 'status $status');
      }
    });

    test('null when the server is unreachable', () async {
      store
        ..username = 'tester'
        ..password = 'sekret';
      adapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/auth/login'),
            reason: 'refused',
          ),
        ),
        data: {'username': 'tester', 'password': 'sekret'},
      );
      expect(await service.silentReLogin(baseUrl), isNull);
    });

    test('concurrent callers share one POST /auth/login', () async {
      // The interceptor, the WS client and the proactive refresher can all
      // notice the same expiry. Without sharing, that is N logins against a
      // server that rate-limits them — and on a server that invalidates the
      // previous JWT on each login, the extra ones turn a retry into a logout.
      store
        ..username = 'tester'
        ..password = 'sekret';
      final gate = Completer<void>();
      final counting = _CountingAdapter((options, _) async {
        await gate.future;
        return _json(readFixture('login_response_ok.json'), 200);
      });
      final localDio = Dio()..httpClientAdapter = counting;
      final localService = AuthService(bareDio: localDio, credentials: store);

      final calls = [
        localService.silentReLogin(baseUrl),
        localService.silentReLogin(baseUrl),
        localService.silentReLogin(baseUrl),
      ];
      // Let all three reach the in-flight check before the response lands.
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final tokens = await Future.wait(calls);

      expect(counting.countOf('/api/v1/auth/login'), 1);
      expect(tokens.toSet(), hasLength(1));
      expect(tokens.first, isNotNull);
    });

    test('a later expiry logs in again — the sharing is per attempt', () async {
      store
        ..username = 'tester'
        ..password = 'sekret';
      final counting = _CountingAdapter(
          (options, _) async => _json(readFixture('login_response_ok.json'), 200));
      final localDio = Dio()..httpClientAdapter = counting;
      final localService = AuthService(bareDio: localDio, credentials: store);

      await localService.silentReLogin(baseUrl);
      await localService.silentReLogin(baseUrl);

      expect(counting.countOf('/api/v1/auth/login'), 2);
    });

    test('a transient failure does not stick — the next one tries again',
        () async {
      store
        ..username = 'tester'
        ..password = 'sekret';
      final counting = _CountingAdapter((options, callNo) async => callNo == 1
          ? _json({'detail': 'Internal Server Error'}, 500)
          : _json(readFixture('login_response_ok.json'), 200));
      final localDio = Dio()..httpClientAdapter = counting;
      final localService = AuthService(bareDio: localDio, credentials: store);

      expect(await localService.silentReLogin(baseUrl), isNull);
      expect(await localService.silentReLogin(baseUrl), isNotNull);
      expect(counting.countOf('/api/v1/auth/login'), 2);
    });
  });

  group('silentReLogin when the credentials are definitively rejected', () {
    /// A store with a password the server will refuse, and a service that
    /// records the rejection the way the app does.
    ({
      AuthService service,
      InMemoryCredentialsStore store,
      _CountingAdapter adapter,
      List<int> rejections,
    }) rejecting({int status = 401}) {
      final localStore = InMemoryCredentialsStore()
        ..username = 'tester'
        ..password = 'stare-haslo';
      final counting = _CountingAdapter(
          (options, _) async => _json({'detail': 'no'}, status));
      final rejections = <int>[];
      final localService = AuthService(
        bareDio: Dio()..httpClientAdapter = counting,
        credentials: localStore,
        onCredentialsRejected: () async => rejections.add(1),
      );
      return (
        service: localService,
        store: localStore,
        adapter: counting,
        rejections: rejections,
      );
    }

    test('401 → one attempt, then it stops asking', () async {
      // The whole point: the server counts failed logins per username *and* per
      // IP, and behind a reverse proxy that IP is shared with everyone else. An
      // app that replays a rejected password on every 401 it meets — three
      // requests per polling tick — empties that budget in under a minute.
      final r = rejecting();

      expect(await r.service.silentReLogin(baseUrl), isNull);
      expect(r.adapter.countOf('/api/v1/auth/login'), 1);
      expect(await r.store.readRememberedLogin(), isNull,
          reason: 'the rejected password must not be kept');

      for (var i = 0; i < 5; i++) {
        expect(await r.service.silentReLogin(baseUrl), isNull);
      }
      expect(r.adapter.countOf('/api/v1/auth/login'), 1,
          reason: 'no further attempts after the server said no');
    });

    test('the rejection is reported once, for the warning on next open',
        () async {
      final r = rejecting();

      await r.service.silentReLogin(baseUrl);
      await r.service.silentReLogin(baseUrl);

      expect(r.rejections, hasLength(1));
    });

    test('the JWT is left alone — only the password is forgotten', () async {
      // Clearing the token here would only turn a recoverable state into a
      // blank one; it is already useless, and the profile stays intact so the
      // user can sign in again over the same server.
      final r = rejecting();
      r.store.jwt = 'wygasly';

      await r.service.silentReLogin(baseUrl);

      expect(r.store.jwt, 'wygasly');
    });

    test('anything but 401 keeps the credentials and reports nothing', () async {
      // 429 is the rate limit the app is trying not to trip, 5xx is the server
      // having a bad day, and a dropped connection says nothing at all. None of
      // them is a verdict on the password.
      for (final status in [429, 500, 502, 503]) {
        final r = rejecting(status: status);

        expect(await r.service.silentReLogin(baseUrl), isNull,
            reason: 'status $status');
        expect(await r.store.readRememberedLogin(), isNotNull,
            reason: 'status $status must not discard the password');
        expect(r.rejections, isEmpty, reason: 'status $status');

        await r.service.silentReLogin(baseUrl);
        expect(r.adapter.countOf('/api/v1/auth/login'), 2,
            reason: 'status $status should be retried later');
      }
    });

    test('a lost connection keeps the credentials', () async {
      final localStore = InMemoryCredentialsStore()
        ..username = 'tester'
        ..password = 'sekret';
      final rejections = <int>[];
      final localDio = Dio();
      final localAdapter = DioAdapter(dio: localDio);
      final localService = AuthService(
        bareDio: localDio,
        credentials: localStore,
        onCredentialsRejected: () async => rejections.add(1),
      );
      localAdapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/auth/login'),
            reason: 'refused',
          ),
        ),
        data: {'username': 'tester', 'password': 'sekret'},
      );

      expect(await localService.silentReLogin(baseUrl), isNull);
      expect(await localStore.readRememberedLogin(), isNotNull);
      expect(rejections, isEmpty);
    });

    test('an interactive sign-in that fails leaves the saved password alone',
        () async {
      // Only the silent path draws the conclusion. A wrong password typed into
      // the form says nothing about the one already stored, and dropping it
      // there would log the user out of a session that still works.
      final localStore = InMemoryCredentialsStore()
        ..username = 'tester'
        ..password = 'stare-haslo';
      final rejections = <int>[];
      final localDio = Dio();
      final localAdapter = DioAdapter(dio: localDio);
      final localService = AuthService(
        bareDio: localDio,
        credentials: localStore,
        onCredentialsRejected: () async => rejections.add(1),
      );
      localAdapter.onPost(
        '$baseUrl/api/v1/auth/login',
        (s) => s.reply(401, {'detail': 'Incorrect username or password'}),
        data: {'username': 'kto-inny', 'password': 'zle'},
      );

      await expectLater(
        localService.login(
            baseUrl: baseUrl, username: 'kto-inny', password: 'zle'),
        throwsA(isA<AuthException>()),
      );
      expect((await localStore.readRememberedLogin())?.password, 'stare-haslo');
      expect(rejections, isEmpty);
    });
  });
}
