import 'package:flutter/foundation.dart';
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
  /// postępu. Próbuje wystartować foreground service (podtrzymuje proces w
  /// tle); gdy system zabroni startu z tła — degraduje do zwykłego, wciąż
  /// wiszącego powiadomienia (awansuje do FGS przy najbliższej okazji).
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  });

  /// Zdejmuje wiszące powiadomienie i zatrzymuje foreground service.
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

  /// Stałe id wiszącego powiadomienia — startForegroundService wołane wielokrotnie
  /// z tym samym id aktualizuje istniejące powiadomienie. Nie może być 0.
  static const int _ongoingId = 1;

  static const String _ongoingChannelId = 'ongoing_print';
  static const String _alertsChannelId = 'print_alerts';

  /// Czy foreground service faktycznie ruszył — decyduje, czy [clearOngoing]
  /// woła stopForegroundService, czy zwykłe cancel (gdy zdegradowaliśmy).
  bool _fgsActive = false;

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

    try {
      await _android?.startForegroundService(
        _ongoingId,
        title,
        body,
        notificationDetails: details,
        foregroundServiceTypes: const {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _fgsActive = true;
    } catch (e) {
      // Start FGS z tła bywa zabroniony (Android 12+) — wtedy bez zwolnienia
      // z optymalizacji baterii. Powiadomienie i tak pokazujemy zwykłą drogą.
      _fgsActive = false;
      debugPrint('startForegroundService blocked, falling back to show(): $e');
      await _plugin.show(
        _ongoingId,
        title,
        body,
        NotificationDetails(android: details),
      );
    }
  }

  @override
  Future<void> clearOngoing() async {
    if (_fgsActive) {
      await _android?.stopForegroundService();
      _fgsActive = false;
    }
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
