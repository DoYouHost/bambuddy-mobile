import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Whether a notification actually reaches the shade is an Android answer, and
/// a host test never asks it: the plugin there is a channel with nothing behind
/// it. After a plugin upgrade this is the difference between "compiles" and
/// "the app still tells anyone their print finished".
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'integration_test',
      'Integration test',
      importance: Importance.low,
    ),
  );

  setUpAll(() async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    expect(
      await android.areNotificationsEnabled(),
      isTrue,
      reason:
          'grant POST_NOTIFICATIONS first — `just test-device` does it, an '
          'ad-hoc `flutter test` does not',
    );
  });

  testWidgets('a posted notification reaches the shade', (tester) async {
    await plugin.show(
      id: 4242,
      title: 'Print finished',
      body: 'benchy.3mf',
      notificationDetails: details,
      payload: 'printer:1',
    );

    final active = await android.getActiveNotifications();
    final posted = active.where((n) => n.id == 4242);
    expect(posted, hasLength(1));
    expect(posted.single.title, 'Print finished');

    await plugin.cancel(id: 4242);
    expect(
      (await android.getActiveNotifications()).where((n) => n.id == 4242),
      isEmpty,
    );
  });

  testWidgets('an action button survives the round trip', (tester) async {
    // Maintenance alerts and HMS remediations are buttons on the notification;
    // losing them is silent, since the notification itself still appears.
    await plugin.show(
      id: 4243,
      title: 'Maintenance due',
      body: 'Clean the nozzle',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'integration_test',
          'Integration test',
          importance: Importance.low,
          actions: [AndroidNotificationAction('done', 'Mark done')],
        ),
      ),
    );

    expect(
      (await android.getActiveNotifications()).where((n) => n.id == 4243),
      hasLength(1),
    );
    await plugin.cancel(id: 4243);
  });
}
