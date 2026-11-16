import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/notifications/finish_photo_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The UI's finish-photo notifier and the service's must never run together
/// (they share one read-modify-write memory), so building this provider must
/// not be what starts it: on a cold start the dashboard builds it a frame
/// before it can stop a service that survived a swipe-away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('building the notifier does not start it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          credentialsStoreProvider.overrideWithValue(
            InMemoryCredentialsStore(),
          ),
          serverProfileOverride(
            const ServerProfile(
              baseUrl: 'http://192.168.1.10:8000',
              authMode: AuthMode.none,
            ),
          ),
          notificationServiceProvider.overrideWithValue(
            RecordingNotifications(),
          ),
        ],
      );

      expect(container.read(finishPhotoNotifierProvider), isNotNull);
      // Started, it holds the poll's periodic timer.
      expect(async.periodicTimerCount, 0);

      container.dispose();
      async.flushMicrotasks();
    });
  });
}
