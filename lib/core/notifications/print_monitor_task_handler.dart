import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dashboard/ws_providers.dart' show wsUrlFor, wsAuthHeaders;
import '../../features/notifications/print_monitor.dart';
import 'hms_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../api/ws_client.dart';
import '../auth/credentials_store.dart';
import '../models/printer_status.dart';
import '../settings/settings_repository.dart';
import 'notification_service.dart';

/// Punkt wejścia isolate'u tła. MUSI być top-level i oznaczony
/// `@pragma('vm:entry-point')` — flutter_foreground_task uruchamia go w osobnym
/// silniku Dart, więc tree-shaking nie może go wyciąć.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PrintMonitorTaskHandler());
}

/// Mózg monitoringu w tle: żyje w isolacie foreground service'u, niezależnym od
/// UI (przeżywa zmiecenie aktywności z recentów). Odtwarza tu cały tor: profil z
/// SharedPreferences, sekrety z Keystore, własny [WsClient] i [PrintMonitor].
/// Nie współdzieli pamięci ani providerów z isolatem UI — wszystko budowane od zera.
class PrintMonitorTaskHandler extends TaskHandler {
  WsClient? _ws;
  StreamSubscription<PrinterStatus>? _sub;
  PrintMonitor? _monitor;
  _FgsNotificationService? _fgs;
  final Map<int, PrinterStatus> _statuses = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final profile = SettingsRepository(prefs).loadProfile();
    // Bez profilu nie ma czego monitorować — serwis zostaje (UI go zatrzyma),
    // ale nic nie subskrybujemy.
    if (profile == null) return;

    final l10n = systemAppLocalizations();
    final alerts = LocalNotificationService()..init();
    final fgs = _FgsNotificationService(alerts, l10n);
    _fgs = fgs;
    // Katalog opisów HMS wczytujemy raz (asset działa też w isolacie tła).
    final catalog = HmsCatalog();
    await catalog.load(systemLocale());
    // Preferencje zdarzeń czytamy raz przy starcie serwisu; zmiana w UI
    // obowiązuje od następnego wejścia w tło (wtedy serwis startuje na nowo).
    final notifPrefs = SettingsRepository(prefs).loadNotificationPrefs();
    _monitor = PrintMonitor(fgs, prefs: notifPrefs, hmsDescribe: catalog.describe);

    final creds = SecureCredentialsStore();
    final ws = WsClient(
      url: wsUrlFor(profile.baseUrl),
      authHeaders: () => wsAuthHeaders(profile.authMode, creds),
    );
    _ws = ws;
    _sub = ws.statuses.listen((status) {
      _statuses[status.id] = status;
      _monitor?.update(Map.of(_statuses));
    });
    ws.start();
  }

  // Sterujemy zdarzeniami przez strumień WS, nie cyklicznym tickiem — ale
  // metoda jest wymagana przez kontrakt TaskHandler.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// Android 14+ pozwala zsunąć powiadomienie foreground service'u
  /// („usuń wszystkie"), co NIE zatrzymuje serwisu — zostałby działający, ale
  /// niewidoczny. Ponawiamy je z ostatnią treścią, by trzymać niezmiennik
  /// „serwis żyje ⇔ powiadomienie widoczne".
  @override
  void onNotificationDismissed() {
    final fgs = _fgs;
    if (fgs != null) unawaited(fgs.repost());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _sub?.cancel();
    await _ws?.dispose();
  }
}

/// [NotificationService] dla isolate'u tła: wiszący postęp kieruje do
/// powiadomienia samego foreground service'u (jest jedno i obowiązkowe, więc nie
/// mnożymy notyfikacji), a głośne alerty „skończone/błąd" puszcza zwykłym
/// kanałem przez [LocalNotificationService].
class _FgsNotificationService implements NotificationService {
  _FgsNotificationService(this._alerts, AppLocalizations l10n)
      : _l10n = l10n,
        _title = l10n.bgServiceTitle,
        _text = l10n.bgServiceText;

  final NotificationService _alerts;
  final AppLocalizations _l10n;

  // Ostatnio pokazana treść wiszącego powiadomienia — by odtworzyć je 1:1 po
  // zsunięciu przez użytkownika ([repost]).
  String _title;
  String _text;

  @override
  Future<void> init() => _alerts.init();

  @override
  Future<bool> requestPermission() => _alerts.requestPermission();

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {
    _title = title;
    _text = body;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  @override
  Future<void> clearOngoing() async {
    // Nic nie drukuje → powiadomienie FGS wraca do neutralnego „monitoruję".
    _title = _l10n.bgServiceTitle;
    _text = _l10n.bgServiceText;
    await FlutterForegroundTask.updateService(
      notificationTitle: _title,
      notificationText: _text,
    );
  }

  /// Ponawia wiszące powiadomienie z ostatnią treścią — po zsunięciu przez
  /// użytkownika (FGS na Androidzie 14+ jest usuwalny, a serwis dalej żyje).
  Future<void> repost() => FlutterForegroundTask.updateService(
        notificationTitle: _title,
        notificationText: _text,
      );

  @override
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) =>
      _alerts.showAlert(id: id, title: title, body: body, payload: payload);
}
