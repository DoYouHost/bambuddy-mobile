import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/two_factor.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/setup/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _baseUrl = 'http://server.local:8000';

/// The setup flow end to end against a mocked server: probe the URL, then sign
/// in with a password or an API key. Everything runs through the real
/// providers — including the profile save — so "connected" means the same thing
/// it means in the app: a [ServerProfile] persisted with the right [AuthMode].
void main() {
  late DioAdapter adapter;
  late ProviderContainer container;
  late InMemoryCredentialsStore credentials;

  /// The overrides every container here needs; a group that wants one more
  /// (the 2FA countdown) rebuilds the container on top of these.
  late List<Override> overrides;

  ProviderContainer buildContainer([List<Override> extra = const []]) {
    final built = ProviderContainer(overrides: [...overrides, ...extra]);
    // AutoDispose provider: keep the controller alive across the awaits.
    built.listen(setupControllerProvider, (_, _) {});
    addTearDown(built.dispose);
    return built;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    adapter = DioAdapter(dio: dio);
    credentials = InMemoryCredentialsStore();
    overrides = [
      sharedPreferencesProvider.overrideWithValue(prefs),
      credentialsStoreProvider.overrideWithValue(credentials),
      bareDioProvider.overrideWithValue(dio),
    ];
    container = buildContainer();
  });

  SetupController controller() =>
      container.read(setupControllerProvider.notifier);
  SetupState state() => container.read(setupControllerProvider);
  ServerProfile? savedProfile() => container.read(serverProfileProvider);

  void mockAuthStatus(String fixture) => adapter.onGet(
        '$_baseUrl/api/v1/auth/status',
        (server) => server.reply(200, readFixture(fixture)),
      );

  group('SetupController.probe', () {
    test('auth on + requires_setup → sign-in form, no error', () async {
      // Regression: servers with auth on but no `setup_completed` row report
      // requires_setup forever, and the app used to refuse them outright.
      mockAuthStatus('auth_status_setup_pending.json');

      await controller().probe(_baseUrl);

      expect(state().error, isNull);
      expect(state().needsAuth, isTrue);
      expect(state().baseUrl, _baseUrl);
      // Nothing is connected yet — credentials come next.
      expect(savedProfile(), isNull);
    });

    test('fresh server (auth off + requires_setup) → setup error', () async {
      mockAuthStatus('auth_status_fresh_server.json');

      await controller().probe(_baseUrl);

      expect(state().error, SetupErrorCode.requiresServerSetup);
      expect(state().baseUrl, isNull);
      expect(savedProfile(), isNull);
    });

    test('auth off → connected immediately, with no credentials at all',
        () async {
      // An auth-free server is a supported configuration: the probe is the whole
      // setup, and AuthMode.none must be what lands in the profile so the
      // interceptor never attaches a stale header.
      mockAuthStatus('auth_status_disabled.json');

      await controller().probe(_baseUrl);

      expect(state().error, isNull);
      expect(savedProfile()?.baseUrl, _baseUrl);
      expect(savedProfile()?.authMode, AuthMode.none);
      expect(credentials.jwt, isNull);
      expect(credentials.apiKey, isNull);
    });

    test('auth on → waits for credentials', () async {
      mockAuthStatus('auth_status_enabled.json');

      await controller().probe(_baseUrl);

      expect(state().needsAuth, isTrue);
      expect(savedProfile(), isNull);
    });

    test('empty URL → missingUrl, no request made', () async {
      await controller().probe('   ');

      expect(state().error, SetupErrorCode.missingUrl);
      expect(state().baseUrl, isNull);
    });

    test('a URL is normalized before it is probed', () async {
      // The user types a host; the app adds the scheme and drops the trailing
      // slash, so the probe goes to exactly one place.
      mockAuthStatus('auth_status_enabled.json');

      await controller().probe('  server.local:8000/  ');

      expect(state().error, isNull);
      expect(state().baseUrl, _baseUrl);
    });

    test('a proxy with bambuddy down surfaces the status, not a setup error',
        () async {
      adapter.onGet('$_baseUrl/api/v1/auth/status',
          (server) => server.reply(502, {'detail': 'Bad Gateway'}));

      await controller().probe(_baseUrl);

      expect(
        state().error,
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502),
      );
      expect(state().baseUrl, isNull);
      expect(savedProfile(), isNull);
    });

    test('an unreachable host reports unreachable', () async {
      adapter.onGet(
        '$_baseUrl/api/v1/auth/status',
        (server) => server.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/v1/auth/status'),
            reason: 'refused',
          ),
        ),
      );

      await controller().probe(_baseUrl);

      expect(
        state().error,
        isA<NetworkException>()
            .having((e) => e.code, 'code', AppErrorCode.serverUnreachable),
      );
    });

    test('busy is cleared whichever way the probe ends', () async {
      mockAuthStatus('auth_status_enabled.json');
      await controller().probe(_baseUrl);
      expect(state().busy, isFalse);

      adapter.onGet('http://other.local:8000/api/v1/auth/status',
          (server) => server.reply(500, {'detail': 'boom'}));
      await controller().probe('http://other.local:8000');
      expect(state().busy, isFalse);
    });
  });

  group('SetupController.connectWithLogin', () {
    Future<void> probed() async {
      mockAuthStatus('auth_status_enabled.json');
      await controller().probe(_baseUrl);
    }

    void mockLogin(void Function(dynamic server) reply,
            {String password = 'sekret'}) =>
        adapter.onPost('$_baseUrl/api/v1/auth/login', reply,
            data: {'username': 'tester', 'password': password});

    test('valid credentials → profile saved as jwt, token stored', () async {
      await probed();
      mockLogin((s) => s.reply(200, readFixture('login_response_ok.json')));

      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: false);

      expect(state().error, isNull);
      expect(savedProfile()?.authMode, AuthMode.jwt);
      expect(savedProfile()?.baseUrl, _baseUrl);
      expect(credentials.jwt, startsWith('eyJ'));
      expect(await credentials.readRememberedLogin(), isNull);
    });

    test('remember=true also stores the credentials for silent re-login',
        () async {
      await probed();
      mockLogin((s) => s.reply(200, readFixture('login_response_ok.json')));

      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: true);

      expect((await credentials.readRememberedLogin())?.username, 'tester');
    });

    test('wrong password → error, nothing saved, form usable again', () async {
      await probed();
      mockLogin(
          (s) => s.reply(401, {'detail': 'Incorrect username or password'}),
          password: 'zle');

      await controller().connectWithLogin(
          username: 'tester', password: 'zle', remember: true);

      expect(
        state().error,
        isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.invalidCredentials),
      );
      expect(state().busy, isFalse);
      expect(savedProfile(), isNull);
      expect(credentials.jwt, isNull);
      expect(await credentials.readRememberedLogin(), isNull);
    });

    test('rate-limited → "too many attempts", not "wrong password"', () async {
      // Ten wrong passwords in fifteen minutes and the server stops checking
      // them; the app has to say so or the user keeps trying and stays locked.
      await probed();
      mockLogin((s) => s.reply(429,
          {'detail': 'Too many failed attempts. Please try again later.'}));

      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: false);

      expect(
        state().error,
        isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts),
      );
      expect(savedProfile(), isNull);
    });

    test('2FA account → the code step, nothing saved yet', () async {
      await probed();
      mockLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));

      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: true);

      expect(state().error, isNull);
      expect(state().busy, isFalse);
      expect(state().twoFactor?.preAuthToken, 'pre-auth-xyz');
      expect(savedProfile(), isNull, reason: 'the login is not finished yet');
      expect(credentials.jwt, isNull);
      expect(await credentials.readRememberedLogin(), isNull,
          reason: 'a password that cannot renew a 2FA session is not kept');
    });

    test('empty fields → missingCredentials, no request', () async {
      await probed();

      await controller().connectWithLogin(
          username: '', password: 'sekret', remember: false);
      expect(state().error, SetupErrorCode.missingCredentials);

      await controller().connectWithLogin(
          username: 'tester', password: '', remember: false);
      expect(state().error, SetupErrorCode.missingCredentials);
      expect(savedProfile(), isNull);
    });

    test('without a successful probe it does nothing', () async {
      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: false);

      expect(savedProfile(), isNull);
      expect(state().error, isNull);
    });

    test('signing in answers the "sign in again" warning', () async {
      // Set when the server rejected the remembered login; the dashboard warns
      // on every app open until it is cleared, and getting here is what clears
      // it. A failed attempt must leave it standing.
      final settings = container.read(settingsRepositoryProvider);
      await settings.saveSignInRequired(true);
      await probed();

      mockLogin(
          (s) => s.reply(401, {'detail': 'Incorrect username or password'}),
          password: 'zle');
      await controller().connectWithLogin(
          username: 'tester', password: 'zle', remember: false);
      expect(settings.loadSignInRequired(), isTrue);

      mockLogin((s) => s.reply(200, readFixture('login_response_ok.json')));
      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: true);
      expect(settings.loadSignInRequired(), isFalse);
    });
  });

  group('SetupController.connectWithApiKey', () {
    Future<void> probed() async {
      mockAuthStatus('auth_status_enabled.json');
      await controller().probe(_baseUrl);
    }

    void mockPrinters(void Function(dynamic server) reply, String key) =>
        adapter.onGet('$_baseUrl/api/v1/printers/', reply,
            headers: {'X-API-Key': key});

    test('accepted key → profile saved as apiKey, key stored', () async {
      await probed();
      mockPrinters(
          (s) => s.reply(200, readFixture('printers_list.json')), 'bb_dobry');

      await controller().connectWithApiKey('bb_dobry');

      expect(state().error, isNull);
      expect(savedProfile()?.authMode, AuthMode.apiKey);
      expect(credentials.apiKey, 'bb_dobry');
      expect(credentials.jwt, isNull);
    });

    test('a key pasted with whitespace is trimmed before it is sent', () async {
      // A scanned or copied key routinely arrives with a trailing newline; the
      // header must carry the key alone or the server rejects a correct key.
      await probed();
      mockPrinters(
          (s) => s.reply(200, readFixture('printers_list.json')), 'bb_dobry');

      await controller().connectWithApiKey('  bb_dobry \n');

      expect(state().error, isNull);
      expect(credentials.apiKey, 'bb_dobry');
    });

    test('rejected key → error, nothing saved', () async {
      await probed();
      mockPrinters(
          (s) => s.reply(403, {'detail': 'Missing permission'}), 'bb_slaby');

      await controller().connectWithApiKey('bb_slaby');

      expect(
        state().error,
        isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.apiKeyRejected),
      );
      expect(state().busy, isFalse);
      expect(savedProfile(), isNull);
      expect(credentials.apiKey, isNull);
    });

    test('blank key → missingApiKey, no request', () async {
      await probed();

      await controller().connectWithApiKey('   ');

      expect(state().error, SetupErrorCode.missingApiKey);
      expect(savedProfile(), isNull);
    });

    test('without a successful probe it does nothing', () async {
      await controller().connectWithApiKey('bb_dobry');

      expect(savedProfile(), isNull);
      expect(state().error, isNull);
    });
  });

  group('SetupController — the 2FA step', () {
    // The countdown is real time, so the group runs it at 50 ms instead of the
    // server's five minutes.
    setUp(() {
      container = buildContainer([
        twoFactorLifetimeProvider
            .overrideWithValue(const Duration(milliseconds: 50)),
      ]);
    });

    Future<void> probed() async {
      mockAuthStatus('auth_status_enabled.json');
      await controller().probe(_baseUrl);
    }

    void mockLogin(void Function(dynamic server) reply) =>
        adapter.onPost('$_baseUrl/api/v1/auth/login', reply,
            data: {'username': 'tester', 'password': 'sekret'});

    void mockVerify(void Function(dynamic server) reply,
            {String code = '123456', String method = 'totp'}) =>
        adapter.onPost('$_baseUrl/api/v1/auth/2fa/verify', reply, data: {
          'pre_auth_token': 'pre-auth-xyz',
          'code': code,
          'method': method,
        });

    /// Signs in as far as the code step, against a server offering [methods].
    Future<void> atCodeStep({List<String> methods = const ['totp']}) async {
      await probed();
      mockLogin((s) => s.reply(200, {
            'requires_2fa': true,
            'pre_auth_token': 'pre-auth-xyz',
            'two_fa_methods': methods,
          }));
      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: false);
    }

    test('the right code finishes the sign-in', () async {
      await atCodeStep();
      mockVerify((s) => s.reply(200, readFixture('login_response_ok.json')));

      await controller()
          .verifyTwoFactor(method: TwoFactorMethod.totp, code: '123456');

      expect(state().error, isNull);
      expect(savedProfile()?.authMode, AuthMode.jwt);
      expect(credentials.jwt, startsWith('eyJ'));
    });

    test('a wrong code keeps the step so the next one can be typed', () async {
      // The server does not spend the pre-auth token on a failed check, so
      // dropping back to the password form here would throw away a live
      // challenge and cost the user a whole round trip.
      await atCodeStep();
      mockVerify((s) => s.reply(401, {'detail': 'Invalid TOTP code'}),
          code: '000000');

      await controller()
          .verifyTwoFactor(method: TwoFactorMethod.totp, code: '000000');

      expect(
        state().error,
        isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.twoFactorCodeRejected),
      );
      expect(state().twoFactor?.preAuthToken, 'pre-auth-xyz');
      expect(state().busy, isFalse);
      expect(savedProfile(), isNull);
    });

    test('an expired challenge drops back to the password form', () async {
      // Only a fresh login can mint another pre-auth token; leaving the code
      // field up would let the user type into something already dead.
      await atCodeStep();
      mockVerify(
          (s) => s.reply(401, {'detail': 'Invalid or expired pre-auth token'}));

      await controller()
          .verifyTwoFactor(method: TwoFactorMethod.totp, code: '123456');

      expect(state().twoFactor, isNull);
      expect(
        state().error,
        isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorChallengeExpired),
      );
    });

    test('an empty code is refused without a request', () async {
      await atCodeStep();

      await controller()
          .verifyTwoFactor(method: TwoFactorMethod.totp, code: '   ');

      expect(state().error, SetupErrorCode.missingTwoFactorCode);
      expect(state().twoFactor, isNotNull);
    });

    test('an e-mail-only account gets its code without being asked', () async {
      // There is nothing to type until one has been sent, so the extra tap
      // could only ever go one way.
      adapter.onPost(
        '$_baseUrl/api/v1/auth/2fa/email/send',
        (s) => s.reply(200, {'message': 'sent', 'pre_auth_token': 'pre-auth-2'}),
        data: {'pre_auth_token': 'pre-auth-xyz'},
      );

      await atCodeStep(methods: ['email']);

      expect(state().emailCodeSent, isTrue);
      expect(state().twoFactor?.preAuthToken, 'pre-auth-2',
          reason: 'the send consumes the old token and issues a new one');
    });

    test('an account with a choice is not mailed a code it did not ask for',
        () async {
      // The send is rate-limited (3 per 15 minutes) and reaches the user's
      // inbox — spending it on a method they may not use is not ours to do.
      await atCodeStep(methods: ['totp', 'email', 'backup']);

      expect(state().emailCodeSent, isFalse);
      expect(state().twoFactor?.preAuthToken, 'pre-auth-xyz');
    });

    test('a failed send keeps the step usable', () async {
      adapter.onPost(
        '$_baseUrl/api/v1/auth/2fa/email/send',
        (s) => s.reply(500, {'detail': 'Email service is not configured'}),
        data: {'pre_auth_token': 'pre-auth-xyz'},
      );

      await atCodeStep(methods: ['email']);

      expect(
        state().error,
        isA<ApiException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorEmailUnavailable),
      );
      expect(state().twoFactor?.preAuthToken, 'pre-auth-xyz');
      expect(state().emailCodeSent, isFalse);
      expect(state().busy, isFalse);
    });

    test('an untouched step gives way once the token has run out', () async {
      // The pre-auth token dies after five minutes and the server announces
      // that nowhere; left alone, the code field would keep accepting input for
      // a challenge that stopped existing, and a correct code would come back
      // as "wrong". Verified live: an 8-minute wait used to leave the step up.
      await atCodeStep();
      expect(state().twoFactor, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(state().twoFactor, isNull);
      expect(
        state().error,
        isA<AuthException>().having(
            (e) => e.code, 'code', AppErrorCode.twoFactorChallengeExpired),
      );
    });

    test('a mailed code restarts the countdown', () async {
      // `/2fa/email/send` hands back a brand-new token, so the step it belongs
      // to has the full window again — expiring on the first one's clock would
      // throw away a challenge the user just refreshed.
      adapter.onPost(
        '$_baseUrl/api/v1/auth/2fa/email/send',
        (s) => s.reply(200, {'message': 'sent', 'pre_auth_token': 'pre-auth-2'}),
        data: {'pre_auth_token': 'pre-auth-xyz'},
      );
      await atCodeStep(methods: ['totp', 'email']);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await controller().sendTwoFactorEmailCode();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(state().twoFactor?.preAuthToken, 'pre-auth-2',
          reason: 'the old challenge\'s timer must not take the new one down');
    });

    test('signing in stops the countdown', () async {
      // Otherwise the timer fires minutes later, on a screen the user has long
      // left, and writes an error into a setup that already succeeded.
      await atCodeStep();
      mockVerify((s) => s.reply(200, readFixture('login_response_ok.json')));

      await controller()
          .verifyTwoFactor(method: TwoFactorMethod.totp, code: '123456');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(state().error, isNull);
      expect(savedProfile()?.authMode, AuthMode.jwt);
    });

    test('backing out returns to the login form', () async {
      await atCodeStep();

      controller().cancelTwoFactor();

      expect(state().twoFactor, isNull);
      expect(state().error, isNull);
      expect(state().needsAuth, isTrue, reason: 'the probe result survives');
    });
  });
}
