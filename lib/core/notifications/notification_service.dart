import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_api.dart';
import 'notification_prefs.dart';

/// Room reserved per event type. The offsets added to a base are server row ids
/// (a printer, a maintenance task, an archive), which grow without bound and
/// are never reused after a delete — so the band has to be wide enough that no
/// realistic install reaches the next event type's numbers and starts replacing
/// its notifications.
const int alertBandWidth = 1000000;

/// Notification action button (e.g., "Mark Done" for maintenance).
/// Independent of the plugin so tests can inject a fake and assert.
class NotificationAction {
  const NotificationAction({
    required this.id,
    required this.title,
    this.opensApp = false,
    this.dismisses = true,
  });

  final String id;
  final String title;

  /// Whether the tap takes the notification away before the action has run.
  /// False for an answer that may fail: the notification is then still there
  /// to try again, and the handler takes it away once the answer landed.
  final bool dismisses;

  /// Bring the app up instead of running the action where it was tapped. For
  /// the one action that cannot be taken back — stopping a print — the app is
  /// the only place a confirmation can be shown.
  final bool opensApp;
}

/// Photo attached to an alert that was already posted — the finish shot the server
/// takes when a print ends. Both are paths to files on this device, read at post
/// time, so the photo survives the trip to a paired watch (docs/notification-delivery.md).
class AlertPicture {
  const AlertPicture({required this.photoPath, this.thumbnailPath});

  /// Full-size shot, shown when the notification is expanded.
  final String photoPath;

  /// Small square shown while the notification is collapsed.
  final String? thumbnailPath;
}

/// Notification contract seen by [PrintMonitor]. Extracted so tests can inject
/// a fake and verify state transitions alone (without plugin/Android).
///
/// Strings are already localized — the service is "dumb" and knows nothing of l10n.
abstract class NotificationService {
  Future<void> init();

  /// Requests notification permission (Android 13+). Returns `true` if granted.
  Future<bool> requestPermission();

  /// Shows/updates ONE ongoing print notification with a progress bar. A null
  /// [progress] draws the indeterminate bar (running, position unknown); that is not
  /// [clearOngoing]. The record is written by `PrintMonitor._updateOngoing`, not here
  /// (docs/notification-delivery.md, "The alert contract").
  Future<void> showOngoing({
    required String title,
    required String body,
    required int? progress,
  });

  /// Removes the ongoing notification.
  Future<void> clearOngoing();

  /// One-shot alert — survives backgrounding because the plugin itself wakes the app
  /// on tap. Optional [actions] add buttons handled in the background.
  ///
  /// [event] and [printerId] exist for the diagnostic log and are required so the
  /// compiler refuses a new notification without a name. [picture] marks an **update**
  /// of an alert already on screen and re-posts silently, as does [quiet]
  /// (docs/notification-delivery.md, "The alert contract").
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
    bool quiet = false,
  });

  /// Whether the notification [id] is still on screen. False for one the user
  /// swiped away — re-posting that one to add a photo would resurrect a
  /// notification they already dealt with.
  Future<bool> isAlertActive(int id);
}

/// Production implementation using `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _alertsChannelId = 'print_alerts';

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
    );
    await _plugin.initialize(
      settings: settings,
      // Tapping an action button — "Mark Done" on maintenance, a remediation on
      // an HMS alert: foreground and background (app closed) route to the same
      // dispatcher.
      onDidReceiveNotificationResponse: handleNotificationAction,
      onDidReceiveBackgroundNotificationResponse:
          maintenanceNotificationBackgroundHandler,
    );

    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertsChannelId,
        'Print alerts',
        description: 'Print finished or failed',
        importance: Importance.high,
      ),
    );
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

  // No-ops: the only production monitor runs against `FgsNotificationService`, whose
  // ongoing notification is the foreground service's own (docs/notification-delivery.md, "The alert contract").
  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int? progress,
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
    AlertPicture? picture,
    bool quiet = false,
  }) async {
    final photo = picture;
    final thumbnail = photo?.thumbnailPath;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertsChannelId,
        'Print alerts',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        // A picture only ever arrives late, on an alert that already rang.
        onlyAlertOnce: photo != null || quiet,
        largeIcon: thumbnail == null ? null : FilePathAndroidBitmap(thumbnail),
        styleInformation: photo == null
            ? null
            : BigPictureStyleInformation(
                FilePathAndroidBitmap(photo.photoPath),
                contentTitle: title,
                summaryText: body,
                // The thumbnail is the collapsed state's; expanded, the photo
                // itself is already there and the duplicate only takes room.
                hideExpandedLargeIcon: true,
              ),
        actions: [
          if (actions != null)
            for (final a in actions)
              AndroidNotificationAction(
                a.id,
                a.title,
                // Most actions are handled in the background (counter reset,
                // HMS remediation) without opening UI; the notification
                // dismisses after the tap either way.
                showsUserInterface: a.opensApp,
                cancelNotification: a.dismisses,
              ),
        ],
      ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  @override
  Future<bool> isAlertActive(int id) async {
    try {
      final active = await _plugin.getActiveNotifications();
      return active.any((n) => n.id == id);
    } on Object {
      // A platform that will not answer must not stop the photo: treating the
      // notification as gone would drop it for everyone on such a device.
      return true;
    }
  }
}
