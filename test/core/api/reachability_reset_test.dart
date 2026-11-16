import 'package:app_util/app_util.dart';
import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// What the app has learnt about whether the server answers belongs to the
/// server, so a new one starts from nothing. A client built for a notification
/// button tapped with the app open is not a new server, and must leave it be.
void main() {
  final reachable = ServerReachability.instance.reachable;

  setUp(() => reachable.value = true);
  tearDown(ServerReachability.instance.forget);

  test('a bare Dio, as a button tap builds, leaves what was learnt', () {
    createBareDio();
    expect(reachable.value, isTrue);
  });

  test('so does an ApiClient made around one', () {
    ApiClient(
      profile: const ServerProfile(
        baseUrl: fakeServerBaseUrl,
        authMode: AuthMode.none,
      ),
      credentials: InMemoryCredentialsStore(),
    );
    expect(reachable.value, isTrue);
  });

  group('the profile notifier', () {
    late ProviderContainer container;
    late InMemoryCredentialsStore credentials;

    ServerProfile profile(String url) =>
        ServerProfile(baseUrl: url, authMode: AuthMode.none);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      credentials = InMemoryCredentialsStore();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          credentialsStoreProvider.overrideWithValue(credentials),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(serverProfileProvider.notifier)
          .save(profile('http://a.test'));
      reachable.value = true;
    });

    test('forgets when the server changes', () async {
      await container
          .read(serverProfileProvider.notifier)
          .save(profile('http://b.test'));
      expect(reachable.value, isNull);
    });

    test('keeps what was learnt for the same server', () async {
      await container
          .read(serverProfileProvider.notifier)
          .save(
            const ServerProfile(
              baseUrl: 'http://a.test',
              authMode: AuthMode.apiKey,
            ),
          );
      expect(reachable.value, isTrue);
    });

    test('forgets on logging out', () async {
      await container.read(serverProfileProvider.notifier).clear();
      expect(reachable.value, isNull);
    });
  });
}
