import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Kontrakt powiadomień widziany przez [PrintMonitor]. Wydzielony, by w testach
/// wstrzyknąć fake i sprawdzić same przejścia (bez pluginu/Androida).
///
/// Stringi przychodzą już zlokalizowane — serwis jest „głupi", nie zna l10n.
abstract class NotificationService {
  Future<void> init();

  /// Prosi o uprawnienie powiadomień (Android 13+). `true` = przyznane.
  Future<bool> requestPermission();

  /// Pokazuje/aktualizuje JEDNO wiszące powiadomienie wydruku z paskiem
  /// postępu (zwykła notyfikacja). Podtrzymywaniem procesu w tle zajmuje się
  /// foreground service z `flutter_foreground_task` (osobny isolate), nie ten
  /// serwis — tu zostaje tylko warstwa „pokaż powiadomienie".
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  });

  /// Zdejmuje wiszące powiadomienie.
  Future<void> clearOngoing();

  /// Jednorazowy alert (zakończenie/błąd) — przeżywa tło, bo plugin sam budzi
  /// apkę po tapnięciu.
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

/// Produkcyjna implementacja na `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Stałe id wiszącego powiadomienia — `show` z tym samym id aktualizuje
  /// istniejące powiadomienie zamiast tworzyć nowe. Nie może być 0.
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
    await _plugin.initialize(settings);

    final android = _android;
    if (android == null) return;
    // Kanały tworzone z góry: wiszący cichy (LOW), alerty głośne (HIGH).
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
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertsChannelId,
        'Print alerts',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
      ),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }
}
