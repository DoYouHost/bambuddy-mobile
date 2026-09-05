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
import 'background_sync.dart';
import 'finish_alert_memory.dart';
import 'finish_photo_image.dart';
import 'finish_photo_notifier.dart';
import 'hms_catalog.dart';
import 'notification_prefs.dart';
import '../../data/archive_repository.dart';
import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../api/camera_token.dart';
import '../api/ws_client.dart';
import '../api/ws_messages.dart';
import '../api/ws_token.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../auth/token_refresher.dart';
import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';
import '../diagnostics/notif_probe.dart';
import '../diagnostics/session_facts.dart';
import '../demo/demo_ws.dart';
import '../format/datetime_format.dart';
import '../models/printer_status.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';
import '../watch/wear_relay_claim.dart';
import '../watch/wear_relay_handler.dart';
import '../widget/home_widget_publisher.dart';
import '../widget/multi_widget_publisher.dart';
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
  FinishPhotoNotifier? _finishPhoto;
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
  // This isolate's diagnostic stream, when the user is recording a bug report.
  // Null the rest of the time, which is why every use of it is `?.`.
  BackgroundRecording? _recording;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final SharedPreferences prefs;
    final SettingsRepository settings;
    final ServerProfile? profile;
    try {
      prefs = await SharedPreferences.getInstance();
      settings = SettingsRepository(prefs);
      profile = settings.loadProfile();
    } on Object {
      // Was outside any guard: a throw from the preferences channel or from a
      // corrupt profile left the service running with nothing behind it, because
      // the plugin reports success even when the Dart side of `onStart` throws.
      await FlutterForegroundTask.stopService();
      return;
    }

    // This engine hosts no view, so nobody ever told it what the 12/24-hour
    // switch says and `DateTimeFormats.system()` would spell every ETA in AM/PM.
    // The UI writes the switch down for exactly this read.
    DateTimeFormats.rememberSystemClock(settings.loadUse24HourClock());

    // Before `_startMonitoring`, so the token mint and the WebSocket handshake —
    // the two things a report about background notifications most often turns out
    // to be — are inside the recording. Cannot throw and cannot block for long by
    // construction; null when no recording is running, which is the normal case.
    _recording = await DiagnosticRecorder.startBackground(
      settings: settings,
      stream: LogStream.fgs,
      // The header comes off disk, but the secrets cannot: an empty redactor would
      // let the user's own hostname through in the first socket error.
      loadSecrets: () => sessionSecrets(
        profile: profile,
        credentials: SecureCredentialsStore(),
      ),
    );
    _recording?.store.add(
      LogSource.fgs,
      'start',
      fields: {
        // `developer` = the app asked for it (going into the background);
        // `system` = Android restarted us after a swipe or a kill. Until now this
        // argument was unused, and it is the only thing that tells the two apart.
        'starter': starter.name,
        'bg_enabled': settings.loadBgMonitoringEnabled(),
        // Which clock the ETAs in this run are spelled on, resolved the same way
        // they are — a report about a time reading otherwise cannot say whether
        // the setting or the formatting was at fault.
        'clock_24h': DateTimeFormats.system().use24Hour,
      },
    );

    if (profile == null) {
      // Nothing to monitor (e.g. profile cleared while backgrounded) — don't
      // leave an idle FGS + "monitoring active" notification running.
      // Recorded before the stop, with nothing awaited in between: `onDestroy` is
      // delivered on the same channel without waiting for us to return, and a
      // closed sink drops whatever comes after it.
      _recording?.store.add(LogSource.fgs, 'no_profile', lvl: LogLevel.warn);
      await FlutterForegroundTask.stopService();
      return;
    }

    try {
      await _startMonitoring(prefs, profile);
    } catch (error) {
      // A failure anywhere here (keystore access on some OEMs, Dio/client
      // construction, HMS catalog load, ...) would otherwise abort startup
      // right before `ws.start()` while the FGS notification still claims
      // "monitoring active" — the worst failure mode for this feature: it
      // looks fine but nothing is actually watched. Stop the service instead
      // so the lie isn't left running silently. The exception used to be
      // discarded here, which made that failure unreportable.
      _recording?.store.add(
        LogSource.fgs,
        'start_failed',
        lvl: LogLevel.error,
        fields: {'type': error.runtimeType.toString()},
      );
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _startMonitoring(
    SharedPreferences prefs,
    ServerProfile profile,
  ) async {
    final l10n = systemAppLocalizations();
    final alerts = LocalNotificationService();
    // Awaited: the cascade that used to stand here dropped the future, so the
    // channel could still be uncreated when the first alert fired (the immediate
    // maintenance check is the shortest path to that), and a failed init was an
    // unobservable rejection — every alert would fail while the service kept
    // claiming it monitors. Both failure modes are silent, which is exactly what
    // the diagnostic log exists to remove.
    try {
      await alerts.init();
    } on Object catch (error) {
      NotifProbe.initFailed(error);
    }
    final fgs = _FgsNotificationService(alerts, l10n);
    _fgs = fgs;
    // What the monitors talk to: the decorator records every alert handed to the
    // platform. Outside `_FgsNotificationService`, not inside it — the ongoing
    // notification there does not delegate to [alerts], so a decorator underneath
    // would never see it. `_fgs` itself stays raw for [repost].
    // Wrapped so a print-ended alert leaves a record the finish photo can find
    // its way back to — including from the UI isolate, after this one is gone.
    final notify = RememberingNotifications(
      LoggingNotifications(fgs),
      FinishAlertMemory(prefs),
      DateTime.now,
    );
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
    _setUpMaintenance(api, notify, prefs, notifPrefs);

    _monitor = PrintMonitor(
      notify,
      prefs: notifPrefs,
      hmsDescribe: catalog.describe,
      // `catchError`, because a throw inside the reminder used to become an
      // uncaught error in this isolate with nothing to show for it: the repo lets
      // auth failures out on purpose and nobody is awaiting this.
      onPrintEnded: (printerId) => unawaited(
        _maintenance?.remindOnPrintEnd(printerId).catchError((Object error) {
              NotifProbe.suppressed(
                NotifSkip.fetchFailed,
                printerId: printerId,
                event: NotifEvent.maintenanceDue,
                fields: {'cause': error.runtimeType.toString()},
              );
            }) ??
            Future.value(),
      ),
    );

    final creds = SecureCredentialsStore();
    // Shared by the socket below and the proactive refresh: both recover a
    // lapsed session the same way, and building two would mean two independent
    // silent re-logins racing against the server's failed-attempt budget.
    final auth = backgroundAuthService(prefs, creds);
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
            // Without this a handshake rejected for a lapsed JWT has nothing to
            // recover with, and the socket retries the expired token for as long
            // as the service lives. Only JWT can re-mint: an API key is static
            // and a server without auth never rejects.
            refreshAuth: profile.authMode == AuthMode.jwt
                ? () async => await auth.silentReLogin(profile.baseUrl) != null
                : null,
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
      } on Object catch (error) {
        // Swallow-and-continue, consistent with the publish guard below — but no
        // longer in silence: this frame produced no alerts at all, and from the
        // outside that is indistinguishable from a frame that warranted none.
        _recording?.store.add(
          LogSource.fgs,
          'frame_dropped',
          lvl: LogLevel.error,
          fields: {'type': error.runtimeType.toString()},
        );
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
      unawaited(
        MultiWidgetPublisher.publish(Map.of(_statuses), l10n).catchError((_) {}),
      );
    });
    // "Plate not empty" event arrives as a separate frame (not in status) —
    // a real trigger distinct from `awaiting_plate_clear` in status.
    _plateSub = ws.plateAlerts.listen((e) {
      _monitor?.onPlateNotEmpty(e.printerId, e.printerName);
    });
    // The finish photo turns up long after the print-ended alert went out, and
    // the server only announces some of them — hence both the socket and the
    // notifier's own poll. Needs the authenticated client either way: without it
    // there is no archive to read the photo from.
    if (api != null) {
      final archives = ArchiveRepository(api.dio);
      _finishPhoto = FinishPhotoNotifier(
        updates: ws.archiveUpdates,
        fetchArchive: archives.byId,
        recentArchives: (printerId) => archives.list(
          limit: FinishPhotoNotifier.archiveLookback,
          printerId: printerId,
        ),
        fetchPicture: (archiveId, filename) =>
            _fetchFinishPhoto(profile.baseUrl, archiveId, filename),
        notifications: notify,
        memory: FinishAlertMemory(prefs),
        isEnabled: () => notifPrefs.finishPhoto,
      )..start();
    }
    ws.start();

    // After `ws.start()` on purpose: two platform reads must never sit between
    // this isolate waking up and its socket dialling. It is a state snapshot, so
    // where it lands on the timeline does not matter — and it answers the whole
    // "I got no notification" class from configuration alone, which no per-event
    // record can do for a print that started before the recording did.
    unawaited(
      NotifProbe.openSession(
        notifPrefs,
        permission: alerts.notificationsEnabled,
        channelImportance: alerts.alertsChannelImportance,
      ),
    );

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
      claim: WearRelayClaim(SettingsRepository(prefs)),
      plateGateAcknowledged: (id) =>
          _rawStatuses[id]?['awaiting_plate_clear'] = false,
    );
    unawaited(_wearRelay!.start());

    // Foreground service may live longer than JWT validity (e.g., multi-hour print) —
    // proactively refresh the token so WS handshake doesn't fail with 401.
    _setUpTokenRefresh(profile, creds, auth);
  }

  /// Starts proactive JWT refresh in the background isolate (JWT mode only).
  void _setUpTokenRefresh(
    ServerProfile profile,
    CredentialsStore creds,
    AuthService auth,
  ) {
    if (profile.authMode != AuthMode.jwt) return;
    final refresher = jwtTokenRefresher(
      credentials: creds,
      auth: auth,
      baseUrl: profile.baseUrl,
    );
    _tokenRefresher = refresher;
    refresher.start();
  }

  /// Builds [MaintenanceMonitor] on the shared authenticated client (if
  /// `maintenanceDue` event is enabled) and starts periodic REST polling.
  /// Dedup set stored in SharedPreferences (re-armed after perform).
  void _setUpMaintenance(
    ApiClient? api,
    NotificationService notify,
    SharedPreferences prefs,
    NotificationPrefs notifPrefs,
  ) {
    // The one place `maintenanceDue` being off is decided: the monitor is never
    // built, so its own gates can never report it. The session snapshot in
    // [NotifProbe.openSession] is what answers "why no maintenance alert".
    if (!notifPrefs.isOn(NotifEvent.maintenanceDue) || api == null) return;

    final settings = SettingsRepository(prefs);
    final maintenance = MaintenanceMonitor(
      notify,
      repo: MaintenanceRepository(api.dio),
      prefs: notifPrefs,
      initialNotified: settings.loadNotifiedMaintenanceDueIds(),
      persist: settings.saveNotifiedMaintenanceDueIds,
      // The point of this callback: "Mark Done" runs in another isolate, so its
      // removal only exists on disk, and this handle would keep serving the set
      // this isolate started with — the re-arm would be invisible here.
      reload: () async =>
          (await settings.reloaded()).loadNotifiedMaintenanceDueIds(),
    );
    _maintenance = maintenance;
    // `check()` guards its own fetch, but the dedup-set persistence and the alert
    // it posts can still throw — and with nothing awaiting the future that lands
    // as an uncaught error in this isolate, which used to leave no trace.
    Future<void> checkQuietly() =>
        maintenance.check().catchError((Object error) {
          NotifProbe.suppressed(
            NotifSkip.fetchFailed,
            event: NotifEvent.maintenanceDue,
            fields: {'cause': error.runtimeType.toString()},
          );
        });
    unawaited(checkQuietly()); // First check immediately after startup
    _maintenanceTimer = Timer.periodic(
      _maintenanceCheckInterval,
      (_) => unawaited(checkQuietly()),
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

  /// Downloads a finished print's photo to files the notification can carry.
  /// Same auth shape as the cover above: camera token in `?token=`, bare Dio.
  Future<AlertPicture?> _fetchFinishPhoto(
    String baseUrl,
    int archiveId,
    String filename,
  ) {
    final tokenSvc = _cameraToken;
    final dio = _coverDio;
    if (tokenSvc == null || dio == null) return Future.value(null);
    return FinishPhotoImage.store(
      baseUrl: baseUrl,
      archiveId: archiveId,
      filename: filename,
      dio: dio,
      token: ({bool forceRefresh = false}) =>
          tokenSvc.token(forceRefresh: forceRefresh),
    );
  }

  // Events are driven by the WS stream, not by periodic ticking — but
  // the method is required by the TaskHandler contract.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// The app asking this isolate to re-read which bug report it should log into.
  ///
  /// [onStart] reads that once, which covers the case where the service starts
  /// *because* the app went to the background. It does not cover the opposite
  /// order: a service Android restarted after the app was swiped away keeps
  /// running across the next launch, so `startService` is a no-op and this isolate
  /// would never hear that a recording began. Measured on device — the background
  /// half of the log was simply missing, which reads as "the service did nothing".
  @override
  void onReceiveData(Object data) {
    switch (BackgroundSync.parse(data)) {
      case BackgroundSync.diagnostics:
        unawaited(_syncDiagnostics());
      case BackgroundSync.clock:
        unawaited(_syncClockFormat());
      case null:
        break;
    }
  }

  /// The 24-hour switch as the app last saw it. Same reason as above: a service
  /// that was already running when the setting changed read the old value at its
  /// own start-up and would keep spelling ETAs that way for as long as it lives —
  /// which, after a swipe, is across every later launch.
  Future<void> _syncClockFormat() async {
    try {
      final settings = await SettingsRepository.opened();
      DateTimeFormats.rememberSystemClock(settings.loadUse24HourClock());
    } on Object {
      // Keep whatever this isolate started with; a stale clock is not worth
      // taking the service down for.
    }
  }

  Future<void> _syncDiagnostics() async {
    try {
      final settings = await SettingsRepository.opened();
      final wanted = settings.loadDiagnosticsSession();
      if (wanted == _recording?.store.header.session) return;

      // A recording that ended, or was replaced by a newer one: close the old
      // stream first so two of them can never share this heap's one static.
      final previous = _recording;
      _recording = null;
      await previous?.stop();
      if (wanted == null) return;

      _recording = await DiagnosticRecorder.startBackground(
        settings: settings,
        stream: LogStream.fgs,
        loadSecrets: () => sessionSecrets(
          profile: settings.loadProfile(),
          credentials: SecureCredentialsStore(),
        ),
      );
      // `attach`, not `start`: this service was already up, so it did not prime
      // itself for this recording — its monitor still holds edges it latched
      // earlier, and nothing here reconnected. A reader has to know that.
      _recording?.store.add(LogSource.fgs, 'attach');
    } on Object {
      // Monitoring goes on regardless; a recorder is never worth a service.
    }
  }

  /// Android 14+ allows swiping the foreground service notification ("Clear All"),
  /// which does NOT stop the service — it keeps running but becomes invisible.
  /// We re-post it with the last content to maintain the invariant:
  /// "service alive ⇔ notification visible".
  @override
  void onNotificationDismissed() {
    _recording?.store.add(LogSource.fgs, 'notification_dismissed');
    final fgs = _fgs;
    if (fgs != null) unawaited(fgs.repost());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _maintenanceTimer?.cancel();
    _tokenRefresher?.stop();
    _monitor?.dispose();
    // Awaited like the rest: the claim release is a prefs write, and this
    // isolate is about to be torn down — an unawaited one may never land, and
    // a claim left behind is a request nobody answers.
    await _wearRelay?.stop();
    await _connSub?.cancel();
    await _sub?.cancel();
    await _plateSub?.cancel();
    // Before the socket goes: a photo update already in flight still gets to
    // finish, and what it was doing is on the record below rather than cut off.
    await _finishPhoto?.stop();
    await _ws?.dispose();
    // Last, and after `_ws.dispose()` on purpose: that call writes the socket's
    // final records (why it disconnected, and any frames still being counted)
    // through the same static this stream owns. `isTimeout` says whether Android
    // took the service away rather than the app releasing it.
    final recording = _recording;
    if (recording != null) {
      _recording = null;
      recording.store.add(
        LogSource.fgs,
        'destroy',
        fields: {'timeout': isTimeout},
      );
      await recording.stop();
    }
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
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
  }) =>
      _alerts.showAlert(
        event: event,
        printerId: printerId,
        id: id,
        title: title,
        body: body,
        payload: payload,
        actions: actions,
        picture: picture,
      );

  @override
  Future<bool> isAlertActive(int id) => _alerts.isAlertActive(id);
}
