import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    adapter = DioAdapter(dio: dio);
    credentials = InMemoryCredentialsStore();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        credentialsStoreProvider.overrideWithValue(credentials),
        bareDioProvider.overrideWithValue(dio),
      ],
    );
    // AutoDispose provider: keep the controller alive across the awaits.
    container.listen(setupControllerProvider, (_, _) {});
    addTearDown(container.dispose);
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

    test('2FA account → its own message, nothing saved', () async {
      await probed();
      mockLogin((s) => s.reply(200, readFixture('login_response_2fa.json')));

      await controller().connectWithLogin(
          username: 'tester', password: 'sekret', remember: false);

      expect(
        state().error,
        isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.twoFactorUnsupported),
      );
      expect(savedProfile(), isNull);
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
}
