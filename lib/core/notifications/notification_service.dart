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

  /// Fixed ID for the ongoing notification — calling `show` with the same ID
  /// updates the existing notification instead of creating a new one. Cannot be 0.
  static const int _ongoingId = 1;

  static const String _ongoingChannelId = 'ongoing_print';
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
    // Create channels upfront: ongoing silent (LOW), alerts loud (HIGH).
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _ongoingChannelId,
      'Print progress',
      description: 'Ongoing notification with print progress and ETA',
      importance: Importance.low,
      showBadge: false,
    ));
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

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {
    final clamped = progress.clamp(0, 100);
    final details = AndroidNotificationDetails(
      _ongoingChannelId,
      'Print progress',
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.progress,
      showProgress: true,
      maxProgress: 100,
      progress: clamped,
    );

    await _plugin.show(
      _ongoingId,
      title,
      body,
      NotificationDetails(android: details),
    );
  }

  @override
  Future<void> clearOngoing() async {
    await _plugin.cancel(_ongoingId);
  }

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
