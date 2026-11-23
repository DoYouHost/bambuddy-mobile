import 'dart:convert';

import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/core/watch/watch_push.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import '../../helpers/fake_watch_connectivity.dart';

// What the phone hands the watch (#72): the Cloudflare Access credential rides
// with the rest, because the watch has no screen to set it up with.

void main() {
  const profile = ServerProfile(
    baseUrl: 'https://printers.example.com',
    authMode: AuthMode.none,
  );
  final token = ServiceToken(
    host: 'printers.example.com',
    clientId: 'abc.access',
    clientSecret: 's3cret',
  );

  Future<Map<String, dynamic>?> pushed({EdgeAccess? edge}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final watch = FakeWatchConnectivity();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverProfileOverride(profile),
        initialEdgeAccessProvider.overrideWithValue(edge),
        watchConfigSyncProvider.overrideWithValue(
          WatchConfigSync(
            watch: watch,
            credentials: InMemoryCredentialsStore(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    pushConfigToWatch(container.read);
    await Future<void>.delayed(Duration.zero);
    return watch.contexts.isEmpty ? null : watch.contexts.single;
  }

  test('sends the credential the phone presents', () async {
    final map = (await pushed(edge: token))!;
    final back = jsonDecode(map['edge']! as String) as Map<String, dynamic>;
    expect(back['clientId'], 'abc.access');
  });

  test('sends none when the phone has none', () async {
    final map = (await pushed())!;
    expect(map.keys, isNot(contains('edge')));
  });
}
