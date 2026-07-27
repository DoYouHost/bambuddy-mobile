import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_api.dart';
import 'notification_prefs.dart';

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
  ///
  /// Unlike [showAlert] this takes no diagnostic arguments: the record is written
  /// by `PrintMonitor._updateOngoing`, which is the only place that holds the
  /// printer, percentage, ETA and print count as separate values — here they are
  /// already baked into [title] and [body], which never enter a log.
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
  ///
  /// [event] and [printerId] exist for the diagnostic log and are required so the
  /// compiler refuses a new notification without a name — the same reason the
  /// printer card's shared buttons take a mandatory id. Neither can be recovered
  /// from the arguments that were already here: [title] and [body] are the user's
  /// own file and printer names and never enter a log, and [id] is a one-way hash
  /// for HMS alerts (see `_errorAlertId` in `print_monitor.dart`).
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
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

  /// Whether the OS lets this app post notifications at all, **asked** rather
  /// than requested — safe in the background, where prompting is impossible.
  /// Null when the platform does not answer.
  Future<bool?> notificationsEnabled() async =>
      _android?.areNotificationsEnabled();

  /// Importance the alerts channel currently has, or null if the channel or the
  /// answer is missing. App-level permission is not the whole story: a user can
  /// mute this one channel and keep everything else, which looks like a granted
  /// permission and delivers nothing. `Importance.none` is 0.
  Future<int?> alertsChannelImportance() async {
    final channels = await _android?.getNotificationChannels();
    if (channels == null) return null;
    for (final channel in channels) {
      if (channel.id == _alertsChannelId) return channel.importance.value;
    }
    return null;
  }

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

  /// [event] and [printerId] are for the diagnostic log, which wraps this class
  /// from the outside (see `LoggingNotifications`); the platform call itself has
  /// no use for them.
  @override
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
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
