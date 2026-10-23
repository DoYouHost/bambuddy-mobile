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

  tearDown(() => plugin.cancelAll());

  /// The notifications with [id] once the shade agrees with [settled]. Android
  /// posts and cancels asynchronously — `show` returns before the system has
  /// the notification — so a single read right after it lost the race about one
  /// run in five. Gives up after three seconds and returns what it last saw.
  Future<List<ActiveNotification>> shade(
    int id,
    bool Function(List<ActiveNotification>) settled,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (true) {
      final found = (await android.getActiveNotifications())
          .where((n) => n.id == id)
          .toList();
      if (settled(found) || DateTime.now().isAfter(deadline)) return found;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

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

    final posted = await shade(4242, (n) => n.isNotEmpty);
    expect(posted, hasLength(1));
    expect(posted.single.title, 'Print finished');

    await plugin.cancel(id: 4242);
    expect(await shade(4242, (n) => n.isEmpty), isEmpty);
  });

  testWidgets('a notification carrying an action button still posts', (
    tester,
  ) async {
    // As far as an assertion reaches: `ActiveNotification` reports id, channel,
    // title, body, payload and tag — never the buttons. What this catches is a
    // plugin that refuses the action on the way in, which is how maintenance
    // alerts and HMS remediations would lose their buttons.
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

    expect(await shade(4243, (n) => n.isNotEmpty), hasLength(1));
    await plugin.cancel(id: 4243);
  });
}
