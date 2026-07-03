import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_api.dart';

/// Notification action button (e.g., "Mark Done" for maintenance).
/// Independent of the plugin so tests can inject a fake and assert.
class NotificationAction {
  const NotificationAction({required this.id, required this.title});

  final String id;
  final String title;
}

/// Notification contract seen by [PrintMonitor]. Extracted so tests can inject
/// a fake and verify state transitions alone (without plugin/Android).
///
/// Strings are already localized — the service is "dumb" and knows nothing of l10n.
abstract class NotificationService {
  Future<void> init();

  /// Requests notification permission (Android 13+). Returns `true` if granted.
  Future<bool> requestPermission();

  /// Shows/updates ONE ongoing print notification with a progress bar.
  /// The foreground service from `flutter_foreground_task` (separate isolate)
  /// handles keeping the process alive; this service just shows the notification.
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  });

  /// Removes the ongoing notification.
  Future<void> clearOngoing();

  /// One-shot alert (completion/failure) — survives backgrounding because the plugin
  /// itself wakes the app on tap. Optional [actions] add action buttons
  /// (handled in background without opening the app).
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
  });
}

/// Production implementation using `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _alertsChannelId = 'print_alerts';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      // Tapping "Mark Done" on maintenance notification: both foreground and background
      // (app closed) route to the same handler.
      onDidReceiveNotificationResponse: handleMaintenanceAction,
      onDidReceiveBackgroundNotificationResponse:
          maintenanceNotificationBackgroundHandler,
    );

    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _alertsChannelId,
      'Print alerts',
      description: 'Print finished or failed',
      importance: Importance.high,
    ));
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  // No-ops: the only production `PrintMonitor` runs in the background
  // isolate against `_FgsNotificationService` (see
  // `print_monitor_task_handler.dart`), which routes the ongoing
  // notification through `FlutterForegroundTask.updateService` instead — the
  // foreground service's own notification is the "ongoing" one, and having a
  // second, separate `ongoing_print`-channel notification alongside it would
  // just be a duplicate. Kept here (rather than dropped from the
  // [NotificationService] interface) only so this class still satisfies it.
  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {}

  @override
  Future<void> clearOngoing() async {}

  @override
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertsChannelId,
        'Print alerts',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        actions: [
          if (actions != null)
            for (final a in actions)
              AndroidNotificationAction(
                a.id,
                a.title,
                // Action handled in background (counter reset) without opening UI;
                // notification dismisses after tap.
                showsUserInterface: false,
                cancelNotification: true,
              ),
        ],
      ),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }
}
