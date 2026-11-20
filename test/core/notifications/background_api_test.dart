import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
      mockServer(api!.dio).onGet(
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

  group('tagged payloads', () {
    const url = 'http://printers.test:8000';
    final tag = serverTag(url);

    test('a payload is its kind, its fields and the server, in that order', () {
      expect(
        taggedPayload('thing', [4, 'ab', ''], serverUrl: url),
        'thing:4:ab::$tag',
      );
    });

    test('and reads back into the same fields and tag', () {
      final parsed = parseTaggedPayload(
        taggedPayload('thing', [4, 'ab', ''], serverUrl: url),
        'thing',
        fieldCount: 3,
      );
      expect(parsed?.fields, ['4', 'ab', '']);
      expect(parsed?.server, tag);
    });

    test('nothing else reads: another kind, a count that differs, no tag', () {
      final payload = taggedPayload('thing', [4], serverUrl: url);
      expect(parseTaggedPayload(payload, 'other', fieldCount: 1), isNull);
      expect(parseTaggedPayload(payload, 'thing', fieldCount: 2), isNull);
      expect(parseTaggedPayload(payload, 'thing', fieldCount: 0), isNull);
      expect(parseTaggedPayload('thing:4:', 'thing', fieldCount: 1), isNull);
      expect(parseTaggedPayload('thing:4', 'thing', fieldCount: 1), isNull);
      expect(parseTaggedPayload('', 'thing', fieldCount: 1), isNull);
      expect(parseTaggedPayload(null, 'thing', fieldCount: 1), isNull);
      // A kind is the whole word before the first colon.
      expect(
        parseTaggedPayload('things:4:$tag', 'thing', fieldCount: 1),
        isNull,
      );
    });

    test('the three kinds are written as they always were', () {
      expect(
        hmsPayload(
          printerId: 3,
          fullCode: '0500400E',
          serverUrl: url,
          jobId: '77',
        ),
        'hms:3:0500400E:77:$tag',
      );
      expect(
        hmsPayload(printerId: 3, fullCode: '0500400E', serverUrl: url),
        'hms:3:0500400E::$tag',
      );
      expect(maintenancePayload([1, 2, 9], serverUrl: url), 'maint:1,2,9:$tag');
      expect(maintenancePayload(const [], serverUrl: url), 'maint::$tag');
    });
  });
}
