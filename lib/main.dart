import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/notifications/hms_catalog.dart';
import 'core/notifications/notification_service.dart';
import 'features/notifications/print_monitor.dart' show systemLocale;
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final notifications = LocalNotificationService();
  await notifications.init();
  // Katalog opisów HMS dla UI (karta drukarki). Isolate tła ładuje własny.
  await HmsCatalog.instance.load(systemLocale());

  // Port komunikacji UI↔isolate tła + opcje foreground service'u. Sam serwis
  // startuje dopiero, gdy apka idzie w tło (patrz dashboard_screen).
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
      // Zdarzenia dostajemy ze strumienia WS, nie z cyklicznego ticka.
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
      child: const BambuBuddyApp(),
    ),
  );
}
