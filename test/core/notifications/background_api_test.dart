import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Counts the re-logins it is asked for instead of performing any.
class _CountingAuth extends AuthService {
  _CountingAuth(InMemoryCredentialsStore store)
    : super(bareDio: Dio(), credentials: store);

  int reLogins = 0;

  @override
  Future<String?> silentReLogin(String baseUrl) async {
    reLogins++;
    return null;
  }
}

void main() {
  test(
    'the REST client re-logs in through the AuthService it was given',
    () async {
      // The foreground service shares one AuthService between the socket, the
      // refresher and this client; a client that built its own would log in a
      // second time, in parallel, on the same expiry.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await SettingsRepository(prefs).saveProfile(
        const ServerProfile(baseUrl: fakeServerBaseUrl, authMode: AuthMode.jwt),
      );
      final store = InMemoryCredentialsStore()..jwt = 'expired';
      final auth = _CountingAuth(store);

      final api = await buildBackgroundApiClient(
        prefs,
        credentials: store,
        auth: auth,
      );
      DioAdapter(dio: api!.dio).onGet(
        '/api/v1/printers/',
        (server) => server.reply(401, {'detail': 'expired'}),
      );
      await expectLater(
        api.dio.get<dynamic>('/api/v1/printers/'),
        throwsA(isA<DioException>()),
      );

      expect(auth.reLogins, 1);
    },
  );

  test('an AuthService without its store is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await expectLater(
      buildBackgroundApiClient(
        prefs,
        auth: _CountingAuth(InMemoryCredentialsStore()),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
