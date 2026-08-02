import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/core/auth/two_factor.dart';
import 'package:bambuddy_mobile/core/settings/sign_in_reason.dart';
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

      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      final token = (result as LoginCompleted).token;
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

    test('requires_2fa → a challenge to finish, and no JWT stored yet',
        () async {
      onLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));

      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      final challenge = (result as LoginNeedsTwoFactor).challenge;
      expect(challenge.preAuthToken, 'pre-auth-xyz');
      expect(challenge.methods, [TwoFactorMethod.totp]);
      expect(store.jwt, isNull);
    });

    test('requires_2fa with remember=true still stores no password', () async {
      // The password alone cannot finish this login, and a secret on disk that
      // buys nothing is pure liability. Only a completed sign-in stores it.
      onLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));

      await service.login(
        baseUrl: baseUrl,
        username: 'tester',
        password: 'sekret',
        remember: true,
      );

      expect(await store.readRememberedLogin(), isNull);
    });

    test('the binding cookie is picked out of the login response', () async {
      // Set-Cookie carries attributes (HttpOnly, Path, Max-Age) and the
      // response may set more than one cookie; only the value of
      // `2fa_challenge` is ours to send back.
      final counting = _CountingAdapter((options, _) async =>
          ResponseBody.fromString(
            jsonEncode({
              'requires_2fa': true,
              'pre_auth_token': 'pre-auth-xyz',
              'two_fa_methods': ['totp'],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
              'set-cookie': [
                'other=zzz; Path=/',
                '2fa_challenge=wiazanie-123; HttpOnly; Path=/api/v1/auth/2fa; '
                    'Max-Age=300; SameSite=lax',
              ],
            },
          ));
      final localService = AuthService(
        bareDio: Dio()..httpClientAdapter = counting,
        credentials: InMemoryCredentialsStore(),
      );

      final result = await localService.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      expect((result as LoginNeedsTwoFactor).challenge.challengeCookie,
          'wiazanie-123');
    });

    test('no Set-Cookie leaves the binding empty rather than guessed',
        () async {
      onLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));

      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      expect((result as LoginNeedsTwoFactor).challenge.challengeCookie, isNull);
    });

    test('requires_2fa without a pre-auth token is malformed', () async {
      // Nothing to answer the challenge with — the app cannot invent a token
      // and must not treat this as a login either.
      onLogin((s) => s.reply(200, {'requires_2fa': true}));
      await expectLater(
        service.login(
            baseUrl: baseUrl, username: 'tester', password: 'sekret'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.malformedResponse)),
      );
      expect(store.jwt, isNull);
    });

    test('an unknown method name does not leave the user without a field',
        () async {
      // A server that grows a fourth factor must not produce an empty picker;
      // whatever the user types is checked server-side anyway.
      onLogin((s) => s.reply(200, {
            'requires_2fa': true,
            'pre_auth_token': 'pre-auth-xyz',
            'two_fa_methods': ['passkey'],
          }));

      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      expect((result as LoginNeedsTwoFactor).challenge.methods,
          [TwoFactorMethod.totp]);
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

      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');

      expect(result, isA<LoginNeedsTwoFactor>());
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
      final result = await service.login(
          baseUrl: baseUrl, username: 'tester', password: 'sekret');
      expect((result as LoginCompleted).token, 'eyJ.bare.token');
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
      List<SignInReason> rejections,
    }) rejecting({int status = 401}) {
      final localStore = InMemoryCredentialsStore()
        ..username = 'tester'
        ..password = 'stare-haslo';
      final counting = _CountingAdapter(
          (options, _) async => _json({'detail': 'no'}, status));
      final rejections = <SignInReason>[];
      final localService = AuthService(
        bareDio: Dio()..httpClientAdapter = counting,
        credentials: localStore,
        onSignInRequired: (reason) async => rejections.add(reason),
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

      expect(r.rejections, [SignInReason.credentialsRejected]);
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
      final rejections = <SignInReason>[];
      final localDio = Dio();
      final localAdapter = DioAdapter(dio: localDio);
      final localService = AuthService(
        bareDio: localDio,
        credentials: localStore,
        onSignInRequired: (reason) async => rejections.add(reason),
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
      final rejections = <SignInReason>[];
      final localDio = Dio();
      final localAdapter = DioAdapter(dio: localDio);
      final localService = AuthService(
        bareDio: localDio,
        credentials: localStore,
        onSignInRequired: (reason) async => rejections.add(reason),
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

  group('the second step', () {
    const verifyPath = '/api/v1/auth/2fa/verify';
    const sendPath = '/api/v1/auth/2fa/email/send';

    const challenge = TwoFactorChallenge(
      preAuthToken: 'pre-auth-xyz',
      methods: [TwoFactorMethod.totp, TwoFactorMethod.email],
      challengeCookie: 'wiazanie-123',
    );

    /// A service whose every call is recorded, so the assertions can be about
    /// what went out (the cookie, the normalised code) and not only about what
    /// came back.
    ({AuthService service, InMemoryCredentialsStore store, _CountingAdapter calls})
        recording(Future<ResponseBody> Function(RequestOptions o) reply) {
      final localStore = InMemoryCredentialsStore();
      final counting = _CountingAdapter((options, _) => reply(options));
      return (
        service: AuthService(
          bareDio: Dio()..httpClientAdapter = counting,
          credentials: localStore,
        ),
        store: localStore,
        calls: counting,
      );
    }

    test('the login response cookie travels back on the verify call', () async {
      // The server binds the pre-auth token to the HttpOnly `2fa_challenge`
      // cookie and refuses the token when the binding does not come back
      // (`peek_pre_auth_token`). Dio carries no cookie jar, so losing this
      // header turns every correct code into "invalid or expired token".
      final r = recording((o) async => _json({'access_token': 'eyJ.po.2fa'}, 200));

      await r.service.verifyTwoFactor(
        baseUrl: baseUrl,
        challenge: challenge,
        method: TwoFactorMethod.totp,
        code: '123456',
      );

      final sent = r.calls.calls.single;
      expect(sent.path, endsWith(verifyPath));
      expect(sent.headers['Cookie'], '2fa_challenge=wiazanie-123');
      expect(r.store.jwt, 'eyJ.po.2fa');
    });

    test('a login without the cookie sends no binding at all', () async {
      // A reverse proxy that strips Set-Cookie leaves us nothing to send. Made
      // up values would fail the comparison anyway; the omission is what the
      // log record marks so the report points at the proxy.
      final r = recording((o) async => _json({'access_token': 'eyJ.x'}, 200));

      await r.service.verifyTwoFactor(
        baseUrl: baseUrl,
        challenge: const TwoFactorChallenge(
          preAuthToken: 'pre-auth-xyz',
          methods: [TwoFactorMethod.totp],
        ),
        method: TwoFactorMethod.totp,
        code: '123456',
      );

      expect(r.calls.calls.single.headers.containsKey('Cookie'), isFalse);
    });

    test('the code is trimmed and upper-cased before it goes out', () async {
      // The server's own validator rejects surrounding space with a 422 and
      // upper-cases backup codes; both are one keyboard slip away on a watch.
      final r = recording((o) async => _json({'access_token': 'eyJ.x'}, 200));

      await r.service.verifyTwoFactor(
        baseUrl: baseUrl,
        challenge: challenge,
        method: TwoFactorMethod.backup,
        code: ' a1b2c3d4 ',
      );

      expect(r.calls.calls.single.data, {
        'pre_auth_token': 'pre-auth-xyz',
        'code': 'A1B2C3D4',
        'method': 'backup',
      });
    });

    test('a wrong code is told apart from a dead challenge', () async {
      // Opposite next steps: type the next code, or go back and sign in again
      // because only the password step can mint a new pre-auth token.
      for (final (detail, expected) in [
        ('Invalid TOTP code', AppErrorCode.twoFactorCodeRejected),
        ('Invalid OTP code', AppErrorCode.twoFactorCodeRejected),
        ('Invalid backup code', AppErrorCode.twoFactorCodeRejected),
        ('Invalid or expired pre-auth token',
            AppErrorCode.twoFactorChallengeExpired),
      ]) {
        final r = recording((o) async => _json({'detail': detail}, 401));
        await expectLater(
          r.service.verifyTwoFactor(
            baseUrl: baseUrl,
            challenge: challenge,
            method: TwoFactorMethod.totp,
            code: '123456',
          ),
          throwsA(isA<AuthException>().having((e) => e.code, 'code', expected)),
          reason: detail,
        );
        expect(r.store.jwt, isNull, reason: detail);
      }
    });

    test('a 401 with no detail is read as a wrong code', () async {
      // The recoverable reading: it costs the user one more attempt, while the
      // other way round would throw away a challenge that still works.
      final r = recording((o) async => _json(<String, dynamic>{}, 401));
      await expectLater(
        r.service.verifyTwoFactor(
          baseUrl: baseUrl,
          challenge: challenge,
          method: TwoFactorMethod.totp,
          code: '123456',
        ),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorCodeRejected)),
      );
    });

    test('429 stays the rate limit, not a wrong code', () async {
      // 5 failed attempts per 15 minutes, checked before the code — a correct
      // one gets this too, and "wrong code" would have them retyping forever.
      final r = recording((o) async => _json({'detail': 'Too many'}, 429));
      await expectLater(
        r.service.verifyTwoFactor(
          baseUrl: baseUrl,
          challenge: challenge,
          method: TwoFactorMethod.totp,
          code: '123456',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts)),
      );
    });

    test('400 means this method is gone, so offer another', () async {
      final r = recording(
          (o) async => _json({'detail': 'TOTP is not enabled for this user'}, 400));
      await expectLater(
        r.service.verifyTwoFactor(
          baseUrl: baseUrl,
          challenge: challenge,
          method: TwoFactorMethod.totp,
          code: '123456',
        ),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorMethodUnavailable)),
      );
    });

    test('a 200 with no token stores nothing', () async {
      final r = recording((o) async => _json({'token_type': 'bearer'}, 200));
      await expectLater(
        r.service.verifyTwoFactor(
          baseUrl: baseUrl,
          challenge: challenge,
          method: TwoFactorMethod.totp,
          code: '123456',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.malformedResponse)),
      );
      expect(r.store.jwt, isNull);
    });

    test('sending an e-mail code swaps in the fresh pre-auth token', () async {
      // `/2fa/email/send` consumes the token it is given and issues another.
      // Carrying the old one forward is a guaranteed 401 at verification.
      final r = recording((o) async => _json(
            {'message': 'Code sent', 'pre_auth_token': 'pre-auth-2'},
            200,
          ));

      final refreshed = await r.service.sendEmailOtp(
        baseUrl: baseUrl,
        challenge: challenge,
      );

      expect(r.calls.calls.single.path, endsWith(sendPath));
      expect(r.calls.calls.single.headers['Cookie'],
          '2fa_challenge=wiazanie-123');
      expect(refreshed.preAuthToken, 'pre-auth-2');
      expect(refreshed.challengeCookie, 'wiazanie-123',
          reason: 'the binding carries through the e-mail step');
      expect(refreshed.methods, challenge.methods);
    });

    test('a send that answers without a token keeps the old one', () async {
      // The server only re-issues after consuming, so a 200 with no token
      // means the original is still the live one.
      final r = recording((o) async => _json({'message': 'Code sent'}, 200));

      final refreshed = await r.service.sendEmailOtp(
        baseUrl: baseUrl,
        challenge: challenge,
      );

      expect(refreshed.preAuthToken, 'pre-auth-xyz');
    });

    test('a server with no SMTP says so instead of failing generically',
        () async {
      // 500 "Email service is not configured" is a setup problem the user can
      // only route around by picking another factor.
      final r = recording((o) async =>
          _json({'detail': 'Email service is not configured'}, 500));
      await expectLater(
        r.service.sendEmailOtp(baseUrl: baseUrl, challenge: challenge),
        throwsA(isA<ApiException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorEmailUnavailable)),
      );
    });

    test('a failed send leaves the challenge for a retry', () async {
      // The server rolls the transaction back, so the token it was handed is
      // still valid — the caller keeps using the challenge it already has.
      final r = recording((o) async => _json({'detail': 'nope'}, 500));

      await expectLater(
        r.service.sendEmailOtp(baseUrl: baseUrl, challenge: challenge),
        throwsA(isA<AppApiException>()),
      );
      expect(challenge.preAuthToken, 'pre-auth-xyz');
    });
  });

  group('silent re-login meeting 2FA', () {
    ({AuthService service, InMemoryCredentialsStore store, _CountingAdapter calls, List<SignInReason> reasons})
        withTwoFactorServer() {
      final localStore = InMemoryCredentialsStore()
        ..username = 'tester'
        ..password = 'sekret'
        ..jwt = 'wygasly';
      final counting = _CountingAdapter((options, _) async => _json({
            'requires_2fa': true,
            'pre_auth_token': 'pre-auth-xyz',
            'two_fa_methods': ['totp'],
          }, 200));
      final reasons = <SignInReason>[];
      return (
        service: AuthService(
          bareDio: Dio()..httpClientAdapter = counting,
          credentials: localStore,
          onSignInRequired: (reason) async => reasons.add(reason),
        ),
        store: localStore,
        calls: counting,
        reasons: reasons,
      );
    }

    test('stops after one attempt and asks for a hands-on sign-in', () async {
      // The password is still right, but nobody can type a code from an
      // interceptor or a background timer. Repeating the login would spend the
      // server's failed-attempt budget — shared per IP behind a proxy — on an
      // attempt that cannot finish.
      final r = withTwoFactorServer();

      expect(await r.service.silentReLogin(baseUrl), isNull);
      for (var i = 0; i < 3; i++) {
        expect(await r.service.silentReLogin(baseUrl), isNull);
      }

      expect(r.calls.countOf('/api/v1/auth/login'), 1);
      expect(await r.store.readRememberedLogin(), isNull);
    });

    test('the warning names 2FA, not the password', () async {
      // Sending the user off to reset a password that works is the one thing
      // this must not do.
      final r = withTwoFactorServer();

      await r.service.silentReLogin(baseUrl);

      expect(r.reasons, [SignInReason.twoFactorRequired]);
    });

    test('the expired JWT is left where it is', () async {
      final r = withTwoFactorServer();

      await r.service.silentReLogin(baseUrl);

      expect(r.store.jwt, 'wygasly');
    });
  });
}
