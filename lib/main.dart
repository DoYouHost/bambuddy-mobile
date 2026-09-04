import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/notifications/hms_catalog.dart';
import 'core/notifications/notification_service.dart';
import 'core/watch/wear_relay_engine.dart';
import 'features/notifications/print_monitor.dart' show systemLocale;
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final notifications = LocalNotificationService();
  await notifications.init();
  // HMS description catalog for UI (printer card). Background isolate loads its own.
  await HmsCatalog.instance.load(systemLocale());

  // UI↔background isolate communication port + foreground service options.
  // Service starts only when app goes to background (see dashboard_screen).
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'bg_monitoring',
      channelName: 'Background monitoring',
      channelDescription: 'Keeps watching prints while the app is closed',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Events come from WS stream, not periodic tick.
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const BambuddyApp(),
    ),
  );
}

/// Entry point of the headless engine that answers the watch when this app's
/// process is dead — `WearRelayListenerService` (Kotlin) launches it by name.
///
/// **It has to live in this library, next to `main`.** The pragma keeps a
/// declaration the Dart program never calls, but it cannot keep a *library*
/// nothing imports: with this function in `wear_relay_engine.dart` alone, the
/// name was absent from the release AOT snapshot (verified by grepping
/// `libapp.so` — `startCallback` was there, this was not), so the engine
/// started and never installed its channel handler. A debug build hides it,
/// and CI only builds debug.
@pragma('vm:entry-point')
void wearRelayMain() => serveWearRelay();
