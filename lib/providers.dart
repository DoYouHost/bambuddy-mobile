import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:app_report_client/app_report_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'core/api/api_client.dart';
import 'core/api/camera_token.dart';
import 'core/api/server_version.dart';
import 'core/api/server_version_service.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/credentials_store.dart';
import 'core/auth/token_refresher.dart';
import 'core/diagnostics/diagnostic_recorder.dart';
import 'core/diagnostics/report_config.dart';
import 'core/diagnostics/session_facts.dart';
import 'core/notifications/background_monitor.dart';
import 'core/notifications/notification_prefs.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/gcode_snippets.dart';
import 'core/settings/server_profile.dart';
import 'core/settings/server_settings.dart';
import 'core/settings/settings_repository.dart';
import 'core/watch/watch_config_sync.dart';
import 'core/watch/wear_relay_claim.dart';
import 'core/watch/wear_relay_handler.dart';
import 'core/models/cloud_auth.dart';
import 'core/models/current_user.dart';
import 'core/models/makerworld.dart';
import 'data/account_repository.dart';
import 'data/ams_history_repository.dart';
import 'data/api_keys_repository.dart';
import 'data/archive_repository.dart';
import 'data/cloud_repository.dart';
import 'data/discovery_repository.dart';
import 'data/firmware_repository.dart';
import 'data/groups_repository.dart';
import 'data/heater_history_repository.dart';
import 'data/location_sensors_repository.dart';
import 'data/makerworld_repository.dart';
import 'data/pipelines_repository.dart';
import 'data/inventory_repository.dart';
import 'data/inventory_source.dart';
import 'data/library_repository.dart';
import 'data/ams_slot_config_repository.dart';
import 'data/printer_commands_repository.dart';
import 'data/printer_files_repository.dart';
import 'data/maintenance_repository.dart';
import 'data/print_log_repository.dart';
import 'data/printers_repository.dart';
import 'data/projects_repository.dart';
import 'data/queue_repository.dart';
import 'data/scheduled_drying_repository.dart';
import 'data/skip_objects_repository.dart';
import 'data/slicer_repository.dart';
import 'data/smart_plugs_repository.dart';
import 'data/stats_repository.dart';
import 'data/timelapse_repository.dart';
import 'data/users_repository.dart';
import 'features/common/currency_symbol.dart';

/// Overridden in main() after SharedPreferences.getInstance().
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in ProviderScope'),
);

/// Overridden in main() with initialized instance (init requires plugin).
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Override in ProviderScope'),
);

final credentialsStoreProvider =
    Provider<CredentialsStore>((ref) => SecureCredentialsStore());

/// Wear OS Data Layer bridge. Cheap to construct on any platform; on the phone
/// with no paired watch its calls simply no-op.
final watchConnectivityProvider =
    Provider<WatchConnectivity>((ref) => WatchConnectivity());

/// Phone→watch config handoff. Phone pushes the active profile; the watch entry
/// point overrides this with a `settings`-backed instance to apply it.
final watchConfigSyncProvider = Provider<WatchConfigSync>(
  (ref) => WatchConfigSync(
    watch: ref.watch(watchConnectivityProvider),
    credentials: ref.watch(credentialsStoreProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// PHONE side of the watch relay: answers watch RPCs (fleet/commands) over the
/// Data Layer using this phone's authenticated client. Started once from the
/// phone app root; never read by the wear entry point. Reads (not watches) the
/// profile/client so a server change doesn't tear the listener down.
final wearRelayHandlerProvider = Provider<WearRelayHandler>((ref) {
  final handler = WearRelayHandler(
    watch: ref.watch(watchConnectivityProvider),
    dio: () => ref.read(serverProfileProvider) == null
        ? null
        : ref.read(apiClientProvider).dio,
    claim: WearRelayClaim(ref.watch(settingsRepositoryProvider)),
  );
  ref.onDispose(handler.stop);
  return handler;
});

/// Background monitoring mechanism. Currently always foreground service; gate
/// for push = swap implementation here (see [BackgroundMonitor]).
final backgroundMonitorProvider =
    Provider<BackgroundMonitor>((ref) => ForegroundServiceMonitor());

/// Background monitoring enabled (user toggle, default true).
final bgMonitoringEnabledProvider =
    NotifierProvider<BgMonitoringNotifier, bool>(BgMonitoringNotifier.new);

class BgMonitoringNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(settingsRepositoryProvider).loadBgMonitoringEnabled();

  Future<void> set(bool enabled) async {
    await ref.read(settingsRepositoryProvider).saveBgMonitoringEnabled(enabled);
    state = enabled;
  }
}

/// Notification preferences (which events, which thresholds). Persisted via
/// [SettingsRepository]; background isolate reads same prefs independently on
/// startup.
final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
  NotificationPrefsNotifier.new,
);

class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() =>
      ref.watch(settingsRepositoryProvider).loadNotificationPrefs();

  Future<void> _save(NotificationPrefs prefs) async {
    await ref.read(settingsRepositoryProvider).saveNotificationPrefs(prefs);
    state = prefs;
  }

  Future<void> setAlertsEnabled(bool on) =>
      _save(state.copyWith(alertsEnabled: on));

  Future<void> setEvent(NotifEvent event, bool on) =>
      _save(state.withEvent(event, on));

  Future<void> setFinishPhoto(bool on) =>
      _save(state.copyWith(finishPhoto: on));

  Future<void> setBedCooledTemp(int value) =>
      _save(state.copyWith(bedCooledTemp: value));

  Future<void> setAmsHumidityThreshold(int value) =>
      _save(state.copyWith(amsHumidityThreshold: value));

  Future<void> setLowFilamentThreshold(int value) =>
      _save(state.copyWith(lowFilamentThreshold: value));
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// Describes the session for a report: app and server version, the device, the
/// display settings.
///
/// A provider rather than a closure inside the recorder, because a change or
/// feature request needs the same versions and has no recording to read them
/// off — and two copies of this argument list would be two places for the
/// server version to be fetched differently.
final sessionFactsProvider = Provider<Future<SessionFacts> Function()>(
  (ref) => () => loadSessionFacts(
        profile: ref.read(serverProfileProvider),
        credentials: ref.read(credentialsStoreProvider),
        // Read through the provider only when a profile exists: without one
        // [apiClientProvider] throws by design, and a recording started from
        // the setup screen has no server to ask anyway.
        readServerVersion: ref.read(serverProfileProvider) == null
            ? null
            : () => ref.read(serverVersionServiceProvider).reportedVersion(),
      ),
);

/// Bug-report log recorder. Holding it in a provider keeps one instance per
/// app, which matters: [DiagnosticRecorder.active] is process-wide state and
/// two recorders would fight over it.
final diagnosticRecorderProvider = Provider<DiagnosticRecorder>(
  (ref) => DiagnosticRecorder(
    settings: ref.watch(settingsRepositoryProvider),
    loadFacts: ref.watch(sessionFactsProvider),
  ),
);

/// Sends bug reports to the relay.
///
/// On the bare Dio on purpose: the relay is not the bambuddy server, so it must
/// see none of the auth interceptors, none of the credentials and none of the
/// base URL the user configured.
final relayClientProvider = Provider<RelayClient>(
  (ref) => RelayClient(ref.watch(bareDioProvider), baseUrl: relayBaseUrl),
);

final reportOutboxProvider = Provider<ReportOutbox>((ref) => const ReportOutbox());

/// One per app: it owns the single outbox slot and a timer, and two of them
/// would race each other over both.
final reportSenderProvider = Provider<ReportSender>((ref) {
  final sender = ReportSender(
    client: ref.watch(relayClientProvider),
    outbox: ref.watch(reportOutboxProvider),
    installId: () => installId(ref.read(sharedPreferencesProvider)),
    // Read, not watched: rebuilding this provider on a profile change would
    // hand out a second sender over the same outbox slot.
    demoMode: () => ref.read(serverProfileProvider)?.isDemo ?? false,
    formatVersion: reportLogSchema,
  );
  ref.onDispose(sender.dispose);
  return sender;
});

final bareDioProvider = Provider<Dio>((ref) => createBareDio());

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    bareDio: ref.watch(bareDioProvider),
    credentials: ref.watch(credentialsStoreProvider),
    // Nothing on screen otherwise says why the app went quiet: the rejection
    // happens in an interceptor or a background timer, and every request after
    // it just fails as unauthorized. The dashboard turns this flag into one
    // warning on the next app open.
    onSignInRequired: (reason) => ref
        .read(settingsRepositoryProvider)
        .saveSignInRequired(true, reason: reason),
  ),
);

/// Proactive JWT refresh for active profile: schedules silent re-login just
/// before token expiry so REST and WS handshake don't hit 401s (which we only
/// retry reactively). Only for [AuthMode.jwt] — API key is static and no-auth
/// server doesn't expire; those modes return `null`.
///
/// Doesn't run itself — lazy provider; UI keeps it alive and controls it per
/// lifecycle (background taken over by foreground service isolate, see
/// [PrintMonitorTaskHandler]). Rebuilt on profile change.
final tokenRefresherProvider = Provider<ProactiveTokenRefresher?>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null || profile.authMode != AuthMode.jwt) return null;
  final creds = ref.watch(credentialsStoreProvider);
  final auth = ref.watch(authServiceProvider);
  final refresher = jwtTokenRefresher(
    credentials: creds,
    auth: auth,
    baseUrl: profile.baseUrl,
  );
  ref.onDispose(refresher.stop);
  return refresher;
});

/// Proactive camera-token refresh: re-mints the shared camera token
/// (thumbnails, covers, camera stream) just before its client TTL lapses, so
/// foreground image loads don't hit a 401 first. Reactive re-mint on 401 stays
/// the safety net ([PrintThumbnail], [CameraView]). UI-only (background cover
/// fetch in the FGS isolate re-mints reactively); kept alive +
/// lifecycle-controlled by the dashboard, like [tokenRefresherProvider]. Demo
/// mode has no token to refresh.
final cameraTokenRefresherProvider =
    Provider<ProactiveTokenRefresher?>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null || profile.isDemo) return null;
  final service = ref.watch(cameraTokenServiceProvider);
  final refresher = ProactiveTokenRefresher(
    readExpiry: () async => service.expiresAt,
    refresh: () async {
      try {
        await service.token(forceRefresh: true);
      } catch (_) {
        return null; // Fall back; reactive 401 recovery still covers it.
      }
      // Consumers read the token via cameraTokenProvider, so push the fresh one
      // to them. gaplessPlayback keeps already-shown thumbnails from
      // flickering.
      ref.invalidate(cameraTokenProvider);
      return service.expiresAt;
    },
  );
  ref.onDispose(refresher.stop);
  return refresher;
});

/// Active server profile; `null` = unconfigured (router → /setup).
final serverProfileProvider =
    NotifierProvider<ServerProfileNotifier, ServerProfile?>(
  ServerProfileNotifier.new,
);

class ServerProfileNotifier extends Notifier<ServerProfile?> {
  @override
  ServerProfile? build() =>
      ref.watch(settingsRepositoryProvider).loadProfile();

  Future<void> save(ServerProfile profile) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.saveProfile(profile);
    // Signing in is what the warning asks for, so getting here answers it.
    await settings.saveSignInRequired(false);
    state = profile;
  }

  /// "Logout / change server": clear profile and all secrets.
  Future<void> clear() async {
    await ref.read(settingsRepositoryProvider).clearProfile();
    await ref.read(credentialsStoreProvider).clearAll();
    state = null;
  }
}

/// Most recently built client. Survives the transient frame between "change
/// server" clearing the profile and the router redirecting to /setup: the many
/// non-autoDispose repository providers that `watch` [apiClientProvider] stay
/// alive while the dashboard is still mounted under the drawer, so on clear
/// they rebuild and would hit the null-profile throw before the redirect
/// unmounts them. Returning the last client keeps them from crashing; it's
/// never used for requests (its consumers are guarded / about to unmount) and
/// is replaced as soon as a new profile is set. Safe to cache — [ApiClient]
/// holds no resources needing disposal.
ApiClient? _lastApiClient;

/// API client for active profile. Requires configured profile — routes without
/// profile redirect to /setup, so UI should never touch this when null.
final apiClientProvider = Provider<ApiClient>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) {
    final cached = _lastApiClient;
    if (cached != null) {
      // Expected only during the teardown frame on "change server". If it fires
      // elsewhere, a consumer is reading the client without a null-profile
      // guard and would hit the previous server — surface it in debug.
      assert(() {
        debugPrint('apiClientProvider: reusing last client (profile is null)');
        return true;
      }());
      return cached;
    }
    throw StateError('apiClientProvider użyty bez profilu serwera');
  }
  final auth = ref.watch(authServiceProvider);
  return _lastApiClient = ApiClient(
    profile: profile,
    credentials: ref.watch(credentialsStoreProvider),
    refreshAuth: profile.authMode == AuthMode.jwt
        ? () => auth.silentReLogin(profile.baseUrl)
        : null,
  );
});

/// The signed-in account (`GET /auth/me`). Shares authenticated Dio.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider).dio),
);

/// Who is signed in, and what they are allowed to do. `null` = nobody known:
/// no profile yet, a server with auth switched off, or a `/auth/me` that
/// didn't answer.
///
/// Login hands its own `user` over through [CurrentUserNotifier.adopt] before
/// saving the profile, so signing in costs no extra request; a session
/// restored at startup (profile loaded from settings, no login) is what the
/// `GET /auth/me` here is for.
final currentUserProvider =
    AsyncNotifierProvider<CurrentUserNotifier, CurrentUser?>(
  CurrentUserNotifier.new,
);

class CurrentUserNotifier extends AsyncNotifier<CurrentUser?> {
  /// Set by [adopt] and consumed by the very next [build]. Saving the profile
  /// is what rebuilds this notifier, and the login that just saved it already
  /// holds the answer — without this hand-off the rebuild would ask the server
  /// for what we were handed a moment ago.
  CurrentUser? _handedOver;

  @override
  Future<CurrentUser?> build() async {
    final profile = ref.watch(serverProfileProvider);
    final handed = _handedOver;
    _handedOver = null;
    if (profile == null) return null;
    if (handed != null) return handed;
    // A no-auth server answers 401 here (`auth.py::get_current_user_info`) —
    // there is no identity behind an anonymous session, and nothing it could be
    // restricted from. The demo backend does serve `/auth/me`, so it stays
    // included.
    if (profile.authMode == AuthMode.none && !profile.isDemo) return null;
    try {
      return await ref.read(accountRepositoryProvider).me();
    } on Object {
      // An identity we failed to read is an unknown one, not a restricted one
      // — see [permissionProvider]. The server keeps enforcing either way.
      return null;
    }
  }

  /// Takes the `user` object a fresh login already carries.
  void adopt(CurrentUser user) {
    _handedOver = user;
    state = AsyncData(user);
  }

  /// Re-reads `GET /auth/me`. Group membership and permissions can change on
  /// the server while the app is open.
  Future<void> refresh() async {
    state = const AsyncLoading<CurrentUser?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final profile = ref.read(serverProfileProvider);
      if (profile == null) return null;
      if (profile.authMode == AuthMode.none && !profile.isDemo) return null;
      return ref.read(accountRepositoryProvider).me();
    });
  }
}

/// Whether the current user may do [permission] — see [Permissions] for the
/// strings.
///
/// **Answers `true` whenever the identity is unknown** (no profile, still
/// loading, auth switched off server-side, a `/auth/me` that failed, or a
/// response without a `permissions` field). The server is the only enforcer —
/// it answers 403 regardless of what this says — so a permissive unknown
/// leaves a screen reachable rather than hiding one the user is entitled to.
///
/// An empty `permissions` list is *not* unknown: it is a user whose groups
/// grant nothing, and this answers `false` for them.
///
/// **Not the gate for anything administrative.** The server refuses an
/// API-key session every users/groups/api-keys route no matter what `/auth/me`
/// said about it — use [identifiedPermissionProvider] there, which knows that.
///
/// A screen that would rather not flash a drawer entry and take it away again
/// should watch [currentUserProvider] and handle `loading` itself, instead of
/// this being made restrictive for everyone.
final permissionProvider = Provider.family<bool, String>(
  (ref, permission) =>
      ref.watch(currentUserProvider).valueOrNull?.can(permission) ?? true,
);

/// Whether the current user is an admin. Unknown identity answers `true`, for
/// the reasons in [permissionProvider] — and, like it, this is not enough on
/// its own for a write to users, groups or API keys: an API-key session
/// answers `true` here and is refused all three server-side. Pair it with
/// [identifiedPermissionProvider].
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? true,
);

/// Whether a *known* identity holds [permission] — the gate on the entry
/// points into administration.
///
/// Deliberately the opposite of [permissionProvider] on an unknown identity:
/// this answers `false`. Nothing administrative is offered when we cannot say
/// who is signed in — with authentication switched off server-side there is no
/// account to attribute an edit to, and an entry that leads straight to a 401
/// is worse than no entry at all.
///
/// An API-key session is refused outright, [CurrentUser.isAdmin] or not: the
/// server denies a key **every** administrative permission
/// (`_check_apikey_permissions`, `backend/app/core/auth.py` — anything outside
/// the scope allowlist is a 403, and users/groups/api-keys are all outside
/// it). What `/auth/me` says about a key never described that gate: up to
/// 1.2.5.x it claimed admin with every permission, and from 1.2.6 it reports
/// the key's real, non-administrative set. Both are answered here the same
/// way, on the auth mode rather than on the payload.
final identifiedPermissionProvider = Provider.family<bool, String>((ref, p) {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  final user = ref.watch(currentUserProvider).valueOrNull;
  return user != null && user.can(p);
});

/// The accounts on the server (`GET /users/`). Shares the authenticated Dio.
final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(apiClientProvider).dio),
);

/// The groups on the server (`GET /groups/`). Shares the authenticated Dio.
final groupsRepositoryProvider = Provider<GroupsRepository>(
  (ref) => GroupsRepository(ref.watch(apiClientProvider).dio),
);

/// The API keys issued on the server. Shares the authenticated Dio.
final apiKeysRepositoryProvider = Provider<ApiKeysRepository>(
  (ref) => ApiKeysRepository(ref.watch(apiClientProvider).dio),
);

final printersRepositoryProvider = Provider<PrintersRepository>(
  (ref) => PrintersRepository(ref.watch(apiClientProvider).dio),
);

/// Network discovery (SSDP + subnet scan) for the Add-Printer flow.
final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => DiscoveryRepository(ref.watch(apiClientProvider).dio),
);

/// Printer commands (M4). Shares authenticated Dio with rest — rebuilt on
/// profile change with [apiClientProvider].
final skipObjectsRepositoryProvider = Provider<SkipObjectsRepository>(
  (ref) => SkipObjectsRepository(ref.watch(apiClientProvider).dio),
);

final printerCommandsRepositoryProvider = Provider<PrinterCommandsRepository>(
  (ref) => PrinterCommandsRepository(ref.watch(apiClientProvider).dio),
);

/// Filament presets and the two slot-configuration commands. Shares the
/// authenticated Dio.
final amsSlotConfigRepositoryProvider = Provider<AmsSlotConfigRepository>(
  (ref) => AmsSlotConfigRepository(ref.watch(apiClientProvider).dio),
);

/// AMS sensor history (temperature + humidity charts). Shares authenticated
/// Dio.
final amsHistoryRepositoryProvider = Provider<AmsHistoryRepository>(
  (ref) => AmsHistoryRepository(ref.watch(apiClientProvider).dio),
);

/// Delayed AMS drying runs. Shares authenticated Dio; the version service
/// answers whether to offer scheduling until the listing itself has.
final scheduledDryingRepositoryProvider = Provider<ScheduledDryingRepository>(
  (ref) => ScheduledDryingRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Home Assistant sensors bound to a storage location — read-only. Shares
/// authenticated Dio; the version service answers whether the route family is
/// there until the listing itself has.
final locationSensorsRepositoryProvider = Provider<LocationSensorsRepository>(
  (ref) => LocationSensorsRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Printer heater history (nozzle / bed / chamber charts). Shares authenticated
/// Dio; the version service answers whether to offer the chart until the route
/// itself has.
final heaterHistoryRepositoryProvider = Provider<HeaterHistoryRepository>(
  (ref) => HeaterHistoryRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Connected server's version, read once per profile. Rebuilt with
/// [apiClientProvider] so switching servers cannot carry the old answer over.
final serverVersionServiceProvider = Provider<ServerVersionService>(
  (ref) => ServerVersionService(ref.watch(apiClientProvider).dio),
);

/// Print queue (M5). Shares authenticated Dio.
final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether the server stores the three calibration options as `off`/`on`/`auto`
/// rather than as booleans. Drives whether the print form offers an `auto`
/// position — while this is loading, or when nothing knows, the form stays on
/// two states and no `auto` is ever sent to a server that would reject it.
///
/// Asks the queue repository rather than the version service directly: it has
/// seen the server's own payloads, and that beats reasoning from a version
/// number (see `QueueRepository.supportsTriStateCalibration`). `autoDispose` so
/// each time the print form opens it asks again — a queue fetch between two
/// openings is exactly what turns "unknown" into a real answer.
final triStateCalibrationProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(queueRepositoryProvider).supportsTriStateCalibration(),
);

/// Highest chamber target the connected server accepts, in °C — 65 from 1.2.6,
/// 60 before it and whenever the version is not known yet.
///
/// Not `autoDispose`: the dashboard reads this on every gauge rebuild, and the
/// underlying version is cached in the service anyway. Rebuilt when
/// [serverVersionServiceProvider] is, so switching servers cannot carry the old
/// ceiling over.
///
/// One of the two gates with nothing to observe — see
/// [ServerVersion.chamberMaxTargetC]; [labelStartingPositionProvider] is the
/// other. Every other capability provider here asks a repository instead,
/// because a repository has seen the server's own answers and that outranks
/// reasoning from a version number.
final chamberMaxTargetProvider = FutureProvider<int>(
  (ref) => ref.watch(serverVersionServiceProvider).chamberMaxTargetC(),
);

/// Whether library files can be grouped as cross-model alternatives and queued
/// as one job (server #671). Asks the library repository, which prefers what a
/// file listing actually contained over the version number.
///
/// `autoDispose` so each time a library screen opens it asks again — a listing
/// fetched in between is exactly what turns "unknown" into a real answer.
final crossModelVariantsProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(libraryRepositoryProvider).supportsCrossModelVariants(),
);

/// Whether the slice sheet may offer `auto_orient` / `auto_arrange`.
final sliceLayoutOptionsProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(slicerRepositoryProvider).supportsLayoutOptions(),
);

/// Whether the slice sheet may offer the process-override panel. Asks the
/// slicer repository, which prefers what `/slicer/preset-values` answered over
/// the version number.
final processOverridesProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(slicerRepositoryProvider).supportsProcessOverrides(),
);

/// Whether the label sheet may ask where on the sheet to start printing
/// (server #2879). Version-only: see [ServerFeature.labelStartingPosition] for
/// why a PDF response cannot answer it.
final labelStartingPositionProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(serverVersionServiceProvider)
      .supports(ServerFeature.labelStartingPosition),
);

/// Archive of prints (M5). Shares authenticated Dio.
final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Timelapse metadata, filmstrip, server-side re-encode and download. Shares
/// authenticated Dio.
final timelapseRepositoryProvider = Provider<TimelapseRepository>(
  (ref) => TimelapseRepository(ref.watch(apiClientProvider).dio),
);

/// Projects (group prints toward a goal + BOM/stats/timeline). Shares
/// authenticated Dio.
final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(ref.watch(apiClientProvider).dio),
);

/// Smart plugs (M7). Shares authenticated Dio.
final smartPlugsRepositoryProvider = Provider<SmartPlugsRepository>(
  (ref) => SmartPlugsRepository(ref.watch(apiClientProvider).dio),
);

/// Print log — one row per run, in a table that outlives the archives it
/// points at. Shares authenticated Dio; the version service gates the
/// cost/energy columns and the sort control.
final printLogRepositoryProvider = Provider<PrintLogRepository>(
  (ref) => PrintLogRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether this server sends per-run cost and energy, and honours a sort order
/// (server #2636). Below it both are silent, so the columns and the sort
/// control stay off rather than showing blanks and an order nobody applied.
final printLogCostEnergyProvider = FutureProvider<bool>(
  (ref) => ref.watch(printLogRepositoryProvider).supportsCostEnergy(),
);

/// Archive statistics. Shares authenticated Dio.
final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(apiClientProvider).dio),
);

/// Printer maintenance (M7). Shares authenticated Dio.
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(apiClientProvider).dio),
);

/// Printer firmware. Shares authenticated Dio.
final firmwareRepositoryProvider = Provider<FirmwareRepository>(
  (ref) => FirmwareRepository(ref.watch(apiClientProvider).dio),
);

/// File manager / library. Shares authenticated Dio.
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Printer on-device storage (file manager). Shares authenticated Dio.
final printerFilesRepositoryProvider = Provider<PrinterFilesRepository>(
  (ref) => PrinterFilesRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Server-side slicing (sidecar). Shares authenticated Dio.
final slicerRepositoryProvider = Provider<SlicerRepository>(
  (ref) => SlicerRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Slicer pipelines — reusable preset bundles and their runs. Shares
/// authenticated Dio.
///
/// Not `autoDispose`: it caches whether the routes are there at all, and
/// throwing that away between screens would put the entry point back to
/// guessing. Rebuilt with [apiClientProvider], so a new server or new
/// credentials get a fresh answer.
final pipelinesRepositoryProvider = Provider<PipelinesRepository>(
  (ref) => PipelinesRepository(ref.watch(apiClientProvider).dio),
);

/// Raw server `AppSettings` (best-effort, cached per session). Feature flags
/// derive from this so we fetch `/settings` once.
final serverSettingsProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(slicerRepositoryProvider).serverSettings(),
);

/// Highest `copies` a pipeline run accepts (`pipeline_max_copies`). The server
/// answers **422** above it rather than clamping, so the stepper has to know.
/// 50 is the server's own fallback for an unset or unparseable value
/// (`routes/pipeline_runs.py::run_pipeline`).
final pipelineMaxCopiesProvider = FutureProvider<int>((ref) async {
  final settings = await ref.watch(serverSettingsProvider.future);
  final parsed = settings.settingDouble('pipeline_max_copies', 50).toInt();
  return parsed > 0 ? parsed : 50;
});

/// The symbol for the currency the server keeps prices in, or `''` when it has
/// not said. Reads the settings the app already fetches once per session.
final currencySymbolProvider = Provider<String>((ref) {
  final code = (ref.watch(serverSettingsProvider).valueOrNull ?? const {})
      .settingString('currency');
  return currencySymbol(code is String ? code : null);
});

/// Whether the scheduler requires per-printer plate-clear confirmation before
/// starting queued prints. Gates the plate badge / "clear plate" button and the
/// pre-start confirmation.
final requirePlateClearProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(serverSettingsProvider.future))
          .settingBool('require_plate_clear'),
);

/// Printer models with an auto-print G-code snippet configured on the server.
/// Gates the print form's `gcode_injection` checkbox (see
/// [gcodeSnippetModels]): without snippets the flag does nothing, so the web
/// hides it too.
final gcodeSnippetModelsProvider = FutureProvider<Set<String>>(
  (ref) async => gcodeSnippetModels(
    (await ref.watch(serverSettingsProvider.future))['gcode_snippets'],
  ),
);

/// MakerWorld integration (model import). Shares authenticated Dio.
final makerworldRepositoryProvider = Provider<MakerWorldRepository>(
  (ref) => MakerWorldRepository(ref.watch(apiClientProvider).dio),
);

/// Bambu Cloud login (prerequisite for downloads). Shares authenticated Dio.
final cloudRepositoryProvider = Provider<CloudRepository>(
  (ref) => CloudRepository(ref.watch(apiClientProvider).dio),
);

/// Bambu Cloud login status. Invalidated on login/logout.
final cloudAuthStatusProvider = FutureProvider.autoDispose<CloudAuthStatus>(
  (ref) => ref.watch(cloudRepositoryProvider).status(),
);

/// MakerWorld integration status (can download). Gates import buttons;
/// invalidated on cloud login change.
final makerworldStatusProvider = FutureProvider.autoDispose<MakerWorldStatus>(
  (ref) => ref.watch(makerworldRepositoryProvider).status(),
);

/// Recent MakerWorld imports. Invalidated on successful import.
final makerworldRecentImportsProvider =
    FutureProvider.autoDispose<List<MakerWorldRecentImport>>(
  (ref) => ref.watch(makerworldRepositoryProvider).recentImports(),
);

/// Chosen filament inventory backend (native by default). User toggle;
/// Spoolman is drop-in — see [SpoolInventorySource].
final inventoryBackendProvider =
    NotifierProvider<InventoryBackendNotifier, InventoryBackend>(
  InventoryBackendNotifier.new,
);

class InventoryBackendNotifier extends Notifier<InventoryBackend> {
  @override
  InventoryBackend build() {
    final raw = ref.watch(settingsRepositoryProvider).loadInventoryBackend();
    return InventoryBackend.values.firstWhere(
      (b) => b.name == raw,
      orElse: () => InventoryBackend.native,
    );
  }

  Future<void> set(InventoryBackend backend) async {
    await ref.read(settingsRepositoryProvider).saveInventoryBackend(backend.name);
    state = backend;
  }
}

/// Inventory data source dependent on chosen backend. Shares authenticated Dio;
/// rebuilt on profile or backend change.
final inventorySourceProvider = Provider<SpoolInventorySource>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return switch (ref.watch(inventoryBackendProvider)) {
    InventoryBackend.native => NativeInventorySource(dio),
    InventoryBackend.spoolman => SpoolmanInventorySource(dio),
  };
});

/// Filament inventory. Facade over chosen source.
final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(
    ref.watch(inventorySourceProvider),
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Service minting camera stream token (print cover; from M2 also camera
/// preview). Rebuilt with client on profile change.
final cameraTokenServiceProvider = Provider<CameraTokenService>(
  (ref) => CameraTokenService(ref.watch(apiClientProvider).dio),
);

/// Camera token for widgets (cover). Service holds cache; this future provides
/// current token for building image URL. Invalidate:
/// `ref.invalidate(cameraTokenProvider)` after 401 from protected resource.
final cameraTokenProvider = FutureProvider<String>(
  (ref) => ref.watch(cameraTokenServiceProvider).token(),
);
