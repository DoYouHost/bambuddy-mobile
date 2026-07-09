import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../../data/maintenance_repository.dart';
import '../../features/dashboard/ws_providers.dart' show wsUrlFor, wsAuthHeaders;
import '../../features/notifications/maintenance_monitor.dart';
import '../../features/notifications/print_monitor.dart';
import 'background_api.dart';
import 'hms_catalog.dart';
import 'notification_prefs.dart';
import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../api/camera_token.dart';
import '../api/ws_client.dart';
import '../api/ws_messages.dart';
import '../api/ws_token.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../auth/token_refresher.dart';
import '../demo/demo_ws.dart';
import '../models/printer_status.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';
import '../watch/wear_relay_handler.dart';
import '../widget/home_widget_publisher.dart';
import '../widget/widget_cover_cache.dart';
import 'notification_service.dart';

/// How often to poll REST for maintenance status. Operating hours only accumulate
/// during printing, so infrequent checks suffice and don't burden the server.
const Duration _maintenanceCheckInterval = Duration(minutes: 30);

/// Entry point for the background isolate. Must be top-level and marked
/// with `@pragma('vm:entry-point')` — flutter_foreground_task launches it
/// in a separate Dart engine, so tree-shaking can't remove it.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PrintMonitorTaskHandler());
}

/// The brain of background monitoring: lives in the foreground service isolate,
/// independent from the UI (survives activity swiping from recents). Rebuilds
/// everything from scratch here: profile from SharedPreferences, secrets from Keystore,
/// own [WsClient] and [PrintMonitor]. Shares no memory or providers with the UI isolate.
class PrintMonitorTaskHandler extends TaskHandler {
  WsClient? _ws;
  StreamSubscription<WsPrinterStatus>? _sub;
  StreamSubscription<WsPlateNotEmpty>? _plateSub;
  PrintMonitor? _monitor;
  _FgsNotificationService? _fgs;
  MaintenanceMonitor? _maintenance;
  Timer? _maintenanceTimer;
  ProactiveTokenRefresher? _tokenRefresher;
  final Map<int, PrinterStatus> _statuses = {};
  // Watch relay (plan 05 M-R4): while the app is backgrounded/swiped away this
  // isolate is the phone-side responder. Raw WS frames are cached so getFleet
  // answers from memory (server JSON pass-through) instead of a REST fan-out.
  WearRelayHandler? _wearRelay;
  StreamSubscription<WsConnectionState>? _connSub;
  final Map<int, Map<String, dynamic>> _rawStatuses = {};
  var _wsUp = false;
  // HMS catalog + cover fetch path for widget (separate from UI isolate).
  HmsCatalog? _hmsCatalog;
  CameraTokenService? _cameraToken;
  Dio? _coverDio;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final profile = SettingsRepository(prefs).loadProfile();
    if (profile == null) {
      // Nothing to monitor (e.g. profile cleared while backgrounded) — don't
      // leave an idle FGS + "monitoring active" notification running.
      await FlutterForegroundTask.stopService();
      return;
    }

    try {
      await _startMonitoring(prefs, profile);
    } catch (_) {
      // A failure anywhere here (keystore access on some OEMs, Dio/client
      // construction, HMS catalog load, ...) would otherwise abort startup
      // right before `ws.start()` while the FGS notification still claims
      // "monitoring active" — the worst failure mode for this feature: it
      // looks fine but nothing is actually watched. Stop the service instead
      // so the lie isn't left running silently.
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _startMonitoring(
    SharedPreferences prefs,
    ServerProfile profile,
  ) async {
    final l10n = systemAppLocalizations();
    final alerts = LocalNotificationService()..init();
    final fgs = _FgsNotificationService(alerts, l10n);
    _fgs = fgs;
    // Load HMS catalog once (assets work in background isolate too).
    final catalog = HmsCatalog();
    await catalog.load(systemLocale());
    _hmsCatalog = catalog;
    // Single authenticated client for this isolate's session — shared by the
    // cover-token mint, the maintenance repo, and the WS handshake token
    // below, instead of each independently rebuilding Dio + interceptors +
    // a keystore read via its own `buildBackgroundApiClient` call.
    final api = await buildBackgroundApiClient(prefs);
    // Print cover fetch for the widget: camera token minted with authenticated Dio,
    // image fetched with bare Dio using `?token=`.
    _cameraToken = api != null ? CameraTokenService(api.dio) : null;
    _coverDio = createBareDio();
    // Load notification preferences once at startup; UI changes take effect
    // on the next background entry (service restarts from scratch then).
    final notifPrefs = SettingsRepository(prefs).loadNotificationPrefs();

    // Maintenance: REST monitor (if enabled) + reminder after print.
    // Set up before [PrintMonitor] to wire the `onPrintEnded` callback.
    _setUpMaintenance(api, prefs, notifPrefs);

    _monitor = PrintMonitor(
      fgs,
      prefs: notifPrefs,
      hmsDescribe: catalog.describe,
      onPrintEnded: (printerId) =>
          unawaited(_maintenance?.remindOnPrintEnd(printerId) ?? Future.value()),
    );

    final creds = SecureCredentialsStore();
    // WS handshake token (new server, GHSA-r2qv) minted with authenticated Dio;
    // null when the server lacks the endpoint → header-only fallback.
    final wsToken = api != null ? WsTokenService(api.dio) : null;
    final ws = profile.isDemo
        // Demo: fake connection fed from DemoBackend (its time-based print
        // simulation keeps this isolate consistent with the UI isolate).
        ? WsClient(
            url: wsUrlFor(profile.baseUrl),
            authHeaders: () async => const {},
            connect: demoWsConnector,
          )
        : WsClient(
            url: wsUrlFor(profile.baseUrl),
            authHeaders: () => wsAuthHeaders(profile.authMode, creds),
            queryToken: wsToken?.token,
            invalidateQueryToken: wsToken?.invalidate,
          );
    _ws = ws;
    _sub = ws.statusFrames.listen((frame) {
      final status = frame.status;
      _statuses[status.id] = status;
      _rawStatuses[status.id] = frame.raw;
      // Guard against a throw inside update (l10n / plugin call) escaping the
      // stream callback as an uncaught zone error, which would otherwise drop
      // processing of this frame's downstream effects (widget publish below).
      try {
        _monitor?.update(Map.of(_statuses));
      } on Object {
        // Swallow-and-continue, consistent with the publish guard below.
      }
      // Also feed the native home screen widget — background isolate may be the only
      // live source of status when the app is closed. Errors don't break the stream.
      unawaited(
        HomeWidgetPublisher.publish(
          Map.of(_statuses),
          l10n,
          describeHms: _hmsCatalog?.describe,
          fetchCover: (picked) => _fetchCover(profile.baseUrl, picked),
          resetCover: WidgetCoverCache.reset,
        ).catchError((_) {}),
      );
    });
    // "Plate not empty" event arrives as a separate frame (not in status) —
    // a real trigger distinct from `awaiting_plate_clear` in status.
    _plateSub = ws.plateAlerts.listen((e) {
      _monitor?.onPlateNotEmpty(e.printerId, e.printerName);
    });
    ws.start();

    // Watch relay: this isolate answers the watch while the app UI is gone
    // (backgrounded/swiped). The UI-engine handler is stopped on pause, so at
    // most one responder listens at a time (a command answered twice would
    // execute twice — e.g. a double startNext). Live frames are served only
    // while the socket is up; after a disconnect the cache may be stale, so
    // getFleet falls back to REST statuses.
    _connSub = ws.connectionStates.listen((s) {
      _wsUp = s == WsConnectionState.connected;
    });
    _wearRelay = WearRelayHandler(
      watch: WatchConnectivity(),
      dio: () => api?.dio,
      liveStatus: (id) => _wsUp ? _rawStatuses[id] : null,
    )..start();

    // Foreground service may live longer than JWT validity (e.g., multi-hour print) —
    // proactively refresh the token so WS handshake doesn't fail with 401.
    _setUpTokenRefresh(profile, creds);
  }

  /// Starts proactive JWT refresh in the background isolate (JWT mode only).
  void _setUpTokenRefresh(ServerProfile profile, CredentialsStore creds) {
    if (profile.authMode != AuthMode.jwt) return;
    final auth = AuthService(bareDio: createBareDio(), credentials: creds);
    final refresher = ProactiveTokenRefresher(
      readJwt: creds.readJwt,
      refresh: () => auth.silentReLogin(profile.baseUrl),
    );
    _tokenRefresher = refresher;
    refresher.start();
  }

  /// Builds [MaintenanceMonitor] on the shared authenticated client (if
  /// `maintenanceDue` event is enabled) and starts periodic REST polling.
  /// Dedup set stored in SharedPreferences (re-armed after perform).
  void _setUpMaintenance(
    ApiClient? api,
    SharedPreferences prefs,
    NotificationPrefs notifPrefs,
  ) {
    if (!notifPrefs.isOn(NotifEvent.maintenanceDue) || api == null) return;

    final settings = SettingsRepository(prefs);
    final maintenance = MaintenanceMonitor(
      _fgs!,
      repo: MaintenanceRepository(api.dio),
      prefs: notifPrefs,
      initialNotified: settings.loadNotifiedMaintenanceDueIds(),
      persist: settings.saveNotifiedMaintenanceDueIds,
      reload: () async => settings.loadNotifiedMaintenanceDueIds(),
    );
    _maintenance = maintenance;
    unawaited(maintenance.check()); // First check immediately after startup
    _maintenanceTimer = Timer.periodic(
      _maintenanceCheckInterval,
      (_) => unawaited(maintenance.check()),
    );
  }

  /// Fetches the current print cover image to a file for the widget (authenticated with
  /// camera token, cached by `cover_url` in [WidgetCoverCache]). Returns null if unavailable.
  Future<String?> _fetchCover(String baseUrl, PrinterStatus picked) {
    final cover = picked.coverUrl;
    final tokenSvc = _cameraToken;
    final dio = _coverDio;
    if (cover == null || tokenSvc == null || dio == null) {
      return Future.value(null);
    }
    return WidgetCoverCache.fetch(
      baseUrl: baseUrl,
      coverPath: cover,
      dio: dio,
      token: ({bool forceRefresh = false}) =>
          tokenSvc.token(forceRefresh: forceRefresh),
    );
  }

  // Events are driven by the WS stream, not by periodic ticking — but
  // the method is required by the TaskHandler contract.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// Android 14+ allows swiping the foreground service notification ("Clear All"),
  /// which does NOT stop the service — it keeps running but becomes invisible.
  /// We re-post it with the last content to maintain the invariant:
  /// "service alive ⇔ notification visible".
  @override
  void onNotificationDismissed() {
    final fgs = _fgs;
    if (fgs != null) unawaited(fgs.repost());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _maintenanceTimer?.cancel();
    _tokenRefresher?.stop();
    _monitor?.dispose();
    _wearRelay?.stop();
    await _connSub?.cancel();
    await _sub?.cancel();
    await _plateSub?.cancel();
    await _ws?.dispose();
  }
}

/// [NotificationService] for the background isolate: ongoing progress updates
/// are sent to the foreground service's notification itself (there's only one and it's
/// mandatory, so we don't multiply notifications). Loud alerts (finished/failed) are
/// sent via the regular channel through [LocalNotificationService].
class _FgsNotificationService implements NotificationService {
  _FgsNotificationService(this._alerts, AppLocalizations l10n)
      : _l10n = l10n,
        _title = l10n.bgServiceTitle,
        _text = l10n.bgServiceText;

  final NotificationService _alerts;
  final AppLocalizations _l10n;

  // Last shown content of the ongoing notification — to recreate it exactly
  // after the user swipes it ([repost]).
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
    // Nothing printing → FGS notification returns to neutral "monitoring".
    _title = _l10n.bgServiceTitle;
    _text = _l10n.bgServiceText;
    await FlutterForegroundTask.updateService(
      notificationTitle: _title,
      notificationText: _text,
    );
  }

  /// Re-posts the ongoing notification with the last content — after the user
  /// swipes it (FGS on Android 14+ is dismissible, but the service keeps running).
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
    List<NotificationAction>? actions,
  }) =>
      _alerts.showAlert(
        id: id,
        title: title,
        body: body,
        payload: payload,
        actions: actions,
      );
}
