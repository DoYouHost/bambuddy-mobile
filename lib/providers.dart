import 'dart:async';
import 'package:app_util/app_util.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:app_report_client/app_report_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'core/api/api_client.dart';
import 'core/api/api_exceptions.dart';
import 'core/api/camera_token.dart';
import 'core/api/media_auth.dart';
import 'core/api/cached_token_service.dart';
import 'core/api/observed_capability.dart';
import 'core/api/server_version.dart';
import 'core/api/server_version_service.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/credentials_store.dart';
import 'core/auth/token_refresher.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import 'core/diagnostics/diagnostics_wiring.dart';
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
import 'core/models/cost_center.dart';
import 'core/models/current_user.dart';
import 'core/models/makerworld.dart';
import 'data/account_repository.dart';
import 'data/ams_history_repository.dart';
import 'data/api_keys_repository.dart';
import 'data/archive_repository.dart';
import 'data/cloud_repository.dart';
import 'data/discovery_repository.dart';
import 'data/finance_repository.dart';
import 'data/firmware_repository.dart';
import 'data/groups_repository.dart';
import 'data/heater_history_repository.dart';
import 'data/location_sensors_repository.dart';
import 'data/printer_locations_repository.dart';
import 'data/suppliers_repository.dart';
import 'data/makerworld_repository.dart';
import 'data/announcements_repository.dart';
import 'data/manyfold_repository.dart';
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
import 'data/batch_repository.dart';
import 'data/queue_repository.dart';
import 'data/scheduled_drying_repository.dart';
import 'data/server_settings_repository.dart';
import 'data/skip_objects_repository.dart';
import 'data/slicer_repository.dart';
import 'data/smart_plugs_repository.dart';
import 'data/stats_repository.dart';
import 'data/timelapse_repository.dart';
import 'data/users_repository.dart';

/// Riverpod 3 retries a provider that throws an `Exception` up to ten times with
/// a growing delay, and `ApiException` is one. Here a failed read is an answer to
/// show (an error view with a refresh button, a gate that stays closed), so it
/// would hold every screen on a spinner for ~13 s instead. Every root scope and
/// container passes this; nested ones inherit it.
Duration? neverRetry(int retryCount, Object error) => null;

/// Overridden in main() after SharedPreferences.getInstance().
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in ProviderScope'),
);

/// Overridden in main() with initialized instance (init requires plugin).
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Override in ProviderScope'),
);

final credentialsStoreProvider = Provider<CredentialsStore>(
  (ref) => SecureCredentialsStore(),
);

/// Wear OS Data Layer bridge. Cheap to construct on any platform; on the phone
/// with no paired watch its calls simply no-op.
final watchConnectivityProvider = Provider<WatchConnectivity>(
  (ref) => WatchConnectivity(),
);

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
final backgroundMonitorProvider = Provider<BackgroundMonitor>(
  (ref) => ForegroundServiceMonitor(),
);

/// Background monitoring enabled (user toggle, default true).
final bgMonitoringEnabledProvider =
    NotifierProvider<BgMonitoringNotifier, bool>(BgMonitoringNotifier.new);

class BgMonitoringNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(settingsRepositoryProvider).loadBgMonitoringEnabled();

  Future<void> set(bool enabled) async {
    await ref.read(settingsRepositoryProvider).saveBgMonitoringEnabled(enabled);
    if (!ref.mounted) return;
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
    if (!ref.mounted) return;
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
/// A provider rather than a closure inside the recorder: a change or feature
/// request needs the same versions and has no recording to read them off.
final sessionFactsProvider = Provider<Future<SessionFacts> Function()>(
  (ref) =>
      () => loadSessionFacts(
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
    sessions: ref.watch(settingsRepositoryProvider).diagnosticsSessions,
    redactor: bambuddyRedactor,
    loadFacts: ref.watch(sessionFactsProvider),
    sessionDuration: recordingLimit,
    sessionBytes: recordingSizeLimit,
    // The socket probe is bambuddy's own, so the recorder cannot know to open
    // and flush it; it is handed over here instead.
    listeners: const [WsSessionListener()],
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

final reportOutboxProvider = Provider<ReportOutbox>(
  (ref) => const ReportOutbox(),
);

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

/// Silent re-login just before the token expires, so REST and the WS handshake do
/// not hit a 401 we only retry reactively; `null` for the other two auth modes.
/// Does not run itself: the UI drives it per lifecycle (docs/providers.md, "Token refreshers").
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

/// Proactive camera-token refresh: re-mints the camera stream token just before
/// its client TTL lapses, so the live view doesn't hit a 401 first. Reactive
/// re-mint on 401 stays the safety net ([CameraView]). Kept alive +
/// lifecycle-controlled by the dashboard, like [tokenRefresherProvider]. Demo
/// mode has no token to refresh.
final cameraTokenRefresherProvider = Provider<ProactiveTokenRefresher?>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null || profile.isDemo) return null;
  final service = ref.watch(cameraTokenServiceProvider);
  final refresher = imageTokenRefresher(
    readExpiry: () async => service.expiresAt,
    remint: () => service.token(forceRefresh: true),
    // Consumers read the token via cameraTokenProvider, so push the fresh one
    // to them.
    onRefreshed: () => ref.invalidate(cameraTokenProvider),
  );
  ref.onDispose(refresher.stop);
  return refresher;
});

/// The same for the media credential behind thumbnails, covers, photos and
/// timelapses. UI-only, and a no-op while the credential is a header, which does
/// not expire (docs/providers.md, "Token refreshers").
final mediaAuthRefresherProvider = Provider<ProactiveTokenRefresher?>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null || profile.isDemo) return null;
  final service = ref.watch(mediaAuthServiceProvider);
  final refresher = imageTokenRefresher(
    readExpiry: () async => service.expiresAt,
    remint: () => service.auth(forceRefresh: true),
    onRefreshed: () => ref.invalidate(mediaAuthProvider),
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
  ServerProfile? build() => ref.watch(settingsRepositoryProvider).loadProfile();

  Future<void> save(ServerProfile profile) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.saveProfile(profile);
    // Signing in is what the warning asks for, so getting here answers it.
    await settings.saveSignInRequired(false);
    await settings.markTourDue();
    if (ref.mounted) state = profile;
  }

  /// "Logout / change server": clear profile and all secrets.
  Future<void> clear() async {
    // Both stores are read first: logging out clears the secrets even if this
    // provider is gone by the time the first write returns.
    final settings = ref.read(settingsRepositoryProvider);
    final credentials = ref.read(credentialsStoreProvider);
    await settings.clearProfile();
    await credentials.clearAll();
    if (ref.mounted) state = null;
  }
}

/// Most recently built client, for the transient frame between "change server"
/// clearing the profile and the router redirecting to /setup. Never used for a
/// request (docs/providers.md, "The client and the teardown frame").
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
    throw StateError('apiClientProvider used without a server profile');
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

/// The signed-in account (`GET /auth/me`).
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider).dio),
);

/// Who is signed in, and what they are allowed to do. `null` = nobody known: no
/// profile yet, auth switched off, or a `/auth/me` that didn't answer. Login hands
/// its `user` over through [CurrentUserNotifier.adopt] (docs/providers.md, "Identity and
/// permissions").
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
    state = const AsyncLoading<CurrentUser?>();
    final next = await AsyncValue.guard(() async {
      final profile = ref.read(serverProfileProvider);
      if (profile == null) return null;
      if (profile.authMode == AuthMode.none && !profile.isDemo) return null;
      return ref.read(accountRepositoryProvider).me();
    });
    if (!ref.mounted) return;
    state = next;
  }
}

/// Whether the current user may do [permission] — see [Permissions] for the strings.
/// **Answers `true` whenever the identity is unknown**: the server is the only
/// enforcer, and an empty `permissions` list is *not* unknown. **Not the gate for
/// anything administrative**: use [identifiedPermissionProvider] (docs/providers.md, "Identity
/// and permissions").
final permissionProvider = Provider.family<bool, String>(
  (ref, permission) =>
      ref.watch(currentUserProvider).value?.can(permission) ?? true,
);

/// Whether the current user is an admin. Unknown identity answers `true`, as in
/// [permissionProvider], and an API-key session answers `true` here while being
/// refused every administrative route — pair it with
/// [identifiedPermissionProvider].
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider).value?.isAdmin ?? true,
);

/// Whether a *known* identity holds [permission] — the gate on the entry points into
/// administration. The opposite of [permissionProvider] on an unknown identity, and
/// an API-key session is refused outright, [CurrentUser.isAdmin] or not
/// (docs/providers.md, "Identity and permissions").
final identifiedPermissionProvider = Provider.family<bool, String>((ref, p) {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  final user = ref.watch(currentUserProvider).value;
  return user != null && user.can(p);
});

/// Whether this session may change a printer — its settings, or the location it
/// stands in. **An API-key session never may** (`printers:update` is outside the key
/// scope allowlist); an unknown identity answers yes, as in [permissionProvider]
/// (docs/providers.md, "Identity and permissions").
final canUpdatePrintersProvider = Provider<bool>((ref) {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  return ref.watch(permissionProvider(Permissions.printersUpdate));
});

/// The accounts on the server (`GET /users/`).
final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(apiClientProvider).dio),
);

/// The groups on the server (`GET /groups/`).
final groupsRepositoryProvider = Provider<GroupsRepository>(
  (ref) => GroupsRepository(ref.watch(apiClientProvider).dio),
);

final apiKeysRepositoryProvider = Provider<ApiKeysRepository>(
  (ref) => ApiKeysRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether the key form may offer "Send notifications". See
/// `ApiKeysRepository.notificationScopeCapability`.
final apiKeyNotificationScopeProvider = capabilityGate(
  (ref) => ref.watch(apiKeysRepositoryProvider).notificationScopeCapability,
);

final printersRepositoryProvider = Provider<PrintersRepository>(
  (ref) => PrintersRepository(ref.watch(apiClientProvider).dio),
);

/// Whether the server can hold a user's jobs for review (#1620). See
/// `PrintersRepository.reviewGateCapability`; who is held is
/// `awaitingReviewProvider`.
final queueReviewGateProvider = capabilityGate(
  (ref) => ref.watch(printersRepositoryProvider).reviewGateCapability,
);

/// Network discovery (SSDP + subnet scan) for the Add-Printer flow.
final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => DiscoveryRepository(ref.watch(apiClientProvider).dio),
);

final skipObjectsRepositoryProvider = Provider<SkipObjectsRepository>(
  (ref) => SkipObjectsRepository(ref.watch(apiClientProvider).dio),
);

final printerCommandsRepositoryProvider = Provider<PrinterCommandsRepository>(
  (ref) => PrinterCommandsRepository(ref.watch(apiClientProvider).dio),
);

/// Filament presets and the two slot-configuration commands.
final amsSlotConfigRepositoryProvider = Provider<AmsSlotConfigRepository>(
  (ref) => AmsSlotConfigRepository(ref.watch(apiClientProvider).dio),
);

/// AMS sensor history (temperature + humidity charts).
final amsHistoryRepositoryProvider = Provider<AmsHistoryRepository>(
  (ref) => AmsHistoryRepository(ref.watch(apiClientProvider).dio),
);

/// Delayed AMS drying runs. The version service answers whether to offer
/// scheduling until the listing itself has.
final scheduledDryingRepositoryProvider = Provider<ScheduledDryingRepository>(
  (ref) => ScheduledDryingRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Filament suppliers — one route family for both inventory backends.
final suppliersRepositoryProvider = Provider<SuppliersRepository>(
  (ref) => SuppliersRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether this server has filament suppliers. Read by the Filaments tab and by
/// the statistics screen's supplier card.
final suppliersSupportedProvider = capabilityGate(
  (ref) => ref.watch(suppliersRepositoryProvider).capability,
);

/// Whether this server stores a material number on a spool. Whether the
/// number can also be written is the backend's call: Spoolman's is read-only.
final materialNumberSupportedProvider = capabilityGate(
  (ref) => ref.watch(inventoryRepositoryProvider).materialNumberCapability,
);

/// Whether this server records when a spool was last dried. Every control that
/// *writes* the date rests on this: both update schemas drop `last_dried_at`
/// on an older server and answer 200.
final lastDriedSupportedProvider = capabilityGate(
  (ref) => ref.watch(inventoryRepositoryProvider).lastDriedCapability,
);

final printerLocationsRepositoryProvider = Provider<PrinterLocationsRepository>(
  (ref) => PrinterLocationsRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether this server has the managed Printer Locations. Read by the printer
/// form, which holds the way in and offers their names, and by the locations
/// screen. See `PrinterLocationsRepository.capability`.
final printerLocationsSupportedProvider = capabilityGate(
  (ref) => ref.watch(printerLocationsRepositoryProvider).capability,
);

/// Home Assistant sensors bound to a storage location — read-only. The version
/// service answers whether the route family is there until the listing itself
/// has.
final locationSensorsRepositoryProvider = Provider<LocationSensorsRepository>(
  (ref) => LocationSensorsRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Printer heater history (nozzle / bed / chamber charts). The version service
/// answers whether to offer the chart until the route itself has.
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

/// How many times contact with the server has been regained — the signal for
/// asking again what an unreachable server could not answer. Bumped by
/// `PrinterStatusesNotifier`, whose idea of "the line is up" (a WebSocket
/// frame or a poll after a gap, including every return from the background)
/// is the app's only one.
final serverContactEpochProvider = NotifierProvider<Epoch, int>(Epoch.new);

/// How many times the user has asked the dashboard to refresh — the signal for
/// every capability gate to drop the refusals its latch recorded before it. A
/// control a 403 hid never calls its route again, so a permission granted on
/// the server since would otherwise wait for a restart.
final refusalsForgottenProvider = NotifierProvider<Epoch, int>(Epoch.new);

/// A counter that only goes up. Never reset, not even for a new server: what
/// it paces lives in the repositories and the version service, which a new
/// server rebuilds anyway.
class Epoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Bumped whenever the server says an archived print changed — a timelapse
/// attached, a finish photo added, metadata edited elsewhere.
final archiveChangedProvider = NotifierProvider<Epoch, int>(Epoch.new);

/// Bumped whenever the server says the spool inventory changed — a spool
/// edited on the web, a scale reporting a weight, a tray loaded. The screen
/// reading it re-fetches when it is the tab being looked at.
final inventoryChangedProvider = NotifierProvider<Epoch, int>(Epoch.new);

/// Bumped when the server says its announcements changed.
final announcementsChangedProvider = NotifierProvider<Epoch, int>(Epoch.new);

/// The connected server's version, for a synchronous reader. Warmed by the shell at
/// start and asked again on every regained contact; `null` is "the server did not
/// say" (docs/providers.md, "Versions").
final serverVersionProvider = FutureProvider<ServerVersion?>((ref) {
  final service = ref.watch(serverVersionServiceProvider);
  if (ref.watch(serverContactEpochProvider) > 0) service.forgetFailure();
  return service.current();
});

/// This app's own build, as `version+buildNumber`. A provider rather than a future
/// in each widget's `State`, which re-enters `waiting` on every call
/// (docs/providers.md, "Versions").
final appVersionProvider = FutureProvider<String>((ref) => readAppVersion());

/// The connected server's version string, for the drawer footer. `null` is "nobody
/// knows". `autoDispose` **with a link kept on success** (docs/providers.md, "Versions").
final serverVersionLabelProvider = FutureProvider.autoDispose<String?>((ref) {
  // Synchronous on purpose: with no server configured there is nothing to wait
  // for, and handing back a future would put a loading frame in front of an
  // answer that is already known.
  if (ref.watch(serverProfileProvider) == null) return null;
  // Taken here rather than after the await: `keepAlive` belongs to the build,
  // and the provider may be disposed while the read is in flight — closing a
  // link afterwards is safe, taking one is not.
  final keep = ref.keepAlive();
  return ref.watch(serverVersionServiceProvider).reportedVersion().then((
    version,
  ) {
    if (version == null) keep.close();
    return version;
  });
});

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether the server stores the three calibration options as `off`/`on`/`auto`.
/// While loading or unknown the print form stays on two states, so no `auto` reaches
/// a server that would reject it (docs/providers.md, "Versions").
final triStateCalibrationProvider = capabilityGate(
  (ref) => ref.watch(queueRepositoryProvider).triStateCapability,
);

/// Whether a queued job can ask for its outcome (#1898) — the print form's
/// "Ask for outcome" switch. See `QueueRepository.outcomeCapability`.
final queueOutcomeProvider = capabilityGate(
  (ref) => ref.watch(queueRepositoryProvider).outcomeCapability,
);

/// What the server's own print dialog starts the switch at
/// (`default_confirm_outcome`, Settings → Workflow on the web). A new job here
/// starts from the same answer rather than from one this phone remembers.
final defaultConfirmOutcomeProvider = serverGate<bool>(
  (settings) => settings.settingBool('default_confirm_outcome'),
);

/// Highest chamber target the connected server accepts, in °C — 65 from 1.2.6, 60
/// before it and whenever the version is not known yet. A value, not a gate
/// (docs/providers.md, "Versions").
final chamberMaxTargetProvider = Provider<int>(
  (ref) =>
      ref.watch(serverVersionProvider).value?.chamberMaxTargetC ??
      ServerVersion.chamberMaxTargetLegacyC,
);

/// Whether library files can be grouped as cross-model alternatives and queued
/// as one job (server #671). Asks the library repository, which prefers what a
/// file listing actually contained over the version number.
final crossModelVariantsProvider = capabilityGate(
  (ref) => ref.watch(libraryRepositoryProvider).variantsCapability,
);

/// Whether the slice sheet may offer `auto_orient` / `auto_arrange`.
final sliceLayoutOptionsProvider = capabilityGate(
  (ref) => ref.watch(slicerRepositoryProvider).layoutOptionsCapability,
);

/// Whether the slice sheet may offer the process-override panel. Asks the
/// slicer repository, which prefers what `/slicer/preset-values` answered over
/// the version number.
final processOverridesProvider = capabilityGate(
  (ref) => ref.watch(slicerRepositoryProvider).processOverridesCapability,
);

/// Whether the label sheet may ask where on the sheet to start printing
/// (server #2879). Version-only: see [ServerFeature.labelStartingPosition] for
/// why a PDF response cannot answer it.
final labelStartingPositionProvider = capabilityGate(
  (ref) =>
      ref.watch(inventoryRepositoryProvider).labelStartingPositionCapability,
);

/// Whether the label sheet may choose the printed lines and a PNG output
/// (server #2981). Version-only, like the start position: an older server takes
/// the fields and answers a PDF with every default line on it.
final labelFieldsProvider = capabilityGate(
  (ref) => ref.watch(inventoryRepositoryProvider).labelFieldsCapability,
);

/// Whether "Add to queue" in the file manager may ask which printer or model
/// the files are for (server #3112). Version-only, like the label sheet's.
final libraryQueueTargetProvider = capabilityGate(
  (ref) => ref.watch(libraryRepositoryProvider).queueTargetCapability,
);

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Timelapse metadata, filmstrip, server-side re-encode and download.
final timelapseRepositoryProvider = Provider<TimelapseRepository>(
  (ref) => TimelapseRepository(ref.watch(apiClientProvider).dio),
);

/// Projects (group prints toward a goal + BOM/stats/timeline).
final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(ref.watch(apiClientProvider).dio),
);

final smartPlugsRepositoryProvider = Provider<SmartPlugsRepository>(
  (ref) => SmartPlugsRepository(ref.watch(apiClientProvider).dio),
);

/// Print log — one row per run, in a table that outlives the archives it
/// points at. The version service gates the cost/energy columns and the sort
/// control.
final printLogRepositoryProvider = Provider<PrintLogRepository>(
  (ref) => PrintLogRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Whether this server sends per-run cost and energy, and honours a sort order
/// (server #2636). Below it both are silent, so the columns and the sort
/// control stay off rather than showing blanks and an order nobody applied.
final printLogCostEnergyProvider = capabilityGate(
  (ref) => ref.watch(printLogRepositoryProvider).costEnergyCapability,
);

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(apiClientProvider).dio),
);

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(apiClientProvider).dio),
);

final firmwareRepositoryProvider = Provider<FirmwareRepository>(
  (ref) => FirmwareRepository(ref.watch(apiClientProvider).dio),
);

/// File manager / library.
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Printer on-device storage (file manager).
final printerFilesRepositoryProvider = Provider<PrinterFilesRepository>(
  (ref) => PrinterFilesRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Server-side slicing (sidecar).
final slicerRepositoryProvider = Provider<SlicerRepository>(
  (ref) => SlicerRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(serverVersionServiceProvider),
  ),
);

/// Slicer pipelines — reusable preset bundles and their runs. Not `autoDispose`: it
/// caches whether the routes are there at all (docs/providers.md, "Repositories that must not
/// be autoDispose").
final pipelinesRepositoryProvider = Provider<PipelinesRepository>(
  (ref) => PipelinesRepository(ref.watch(apiClientProvider).dio),
);

/// The server's shared configuration (`AppSettings`). Not `autoDispose`: it carries
/// the 403 latch the queue settings screen reads (docs/providers.md, "Repositories that must not
/// be autoDispose").
final serverSettingsRepositoryProvider = Provider<ServerSettingsRepository>(
  (ref) => ServerSettingsRepository(ref.watch(apiClientProvider).dio),
);

/// Raw server `AppSettings` (best-effort, cached per session). Feature flags
/// derive from this so we fetch `/settings` once.
final serverSettingsProvider =
    AsyncNotifierProvider<ServerSettingsNotifier, Map<String, dynamic>>(
      ServerSettingsNotifier.new,
    );

/// [Endpoints.uiFlags]. autoDispose, so each screen that asks reads it afresh: billing can be
/// switched on in the web while the app runs, and a read that failed must not
/// stand for the rest of the session.
final serverUiFlagsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(serverSettingsRepositoryProvider).fetchUiFlags(),
);

/// Whether the server enforces cost-center billing, which makes every queue
/// create, edit and start need a `cost_center_id` (maziggy/bambuddy #3256),
/// chosen in the print form from [printableCostCentersProvider]. Read from the
/// UI flags any user may see, else from the full
/// settings on a server too old to have them — the flags win when present,
/// being the only source a non-admin can read; false until either answers.
final billingEnabledProvider = Provider.autoDispose<bool>(
  (ref) => _billingFrom(
    ref.watch(serverUiFlagsProvider).value,
    ref.watch(serverSettingsProvider).value,
  ),
);

/// [billingEnabledProvider] for an action outside a build, once the flags have
/// answered.
Future<bool> settledBillingEnabled(ProviderContainer container) async {
  final flags = container.listen(serverUiFlagsProvider.future, (_, _) {});
  try {
    return _billingFrom(
      await flags.read(),
      await container
          .read(serverSettingsProvider.future)
          .catchError((Object _) => const <String, dynamic>{}),
    );
  } finally {
    flags.close();
  }
}

bool _billingFrom(
  Map<String, dynamic>? flags,
  Map<String, dynamic>? settings,
) =>
    ((flags ?? const {})['billing_enabled'] ??
        (settings ?? const {})['billing_enabled']) ==
    true;

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(apiClientProvider).dio),
);

/// The cost centers the print form can book a job to, in the server's order. Empty
/// without billing, and **`null` when this session may not list them** — an API
/// key on a server before #3256 is answered 401, and so is a server with
/// authentication off — which is not the same thing as "none": the first is
/// solved in a browser, the second by an administrator. A password login's 401
/// is a lost session and stays an error.
/// autoDispose, so each form opens on the budget as it stands.
final printableCostCentersProvider =
    FutureProvider.autoDispose<List<CostCenter>?>((ref) async {
      if (!ref.watch(billingEnabledProvider)) return const [];
      try {
        return printableCostCenters(
          await ref.watch(financeRepositoryProvider).myCostCenters(),
        );
      } on AuthException {
        // Only a session with no signed-in user is refused for good. A JWT that
        // got a 401 has lost its session, which the form's retry — and every
        // other request — will say, not "use a browser".
        if (ref.watch(serverProfileProvider)?.authMode == AuthMode.jwt) rethrow;
        return null;
      }
    });

class ServerSettingsNotifier extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() =>
      ref.watch(serverSettingsRepositoryProvider).fetch();

  /// Takes the map a write answered with, instead of asking for it again: the reply
  /// to `PUT /settings/` is the whole of `AppSettings`, and a second `GET` could fail
  /// (docs/providers.md, "Server settings").
  void adopt(Map<String, dynamic> settings) =>
      state = AsyncValue.data(settings);

  /// Re-reads the settings, keeping what is known if the read fails: an empty map can
  /// only mean the read did not land (docs/providers.md, "Server settings").
  Future<void> refresh() async {
    final fresh = await ref.read(serverSettingsRepositoryProvider).fetch();
    if (!ref.mounted) return;
    if (fresh.isNotEmpty || (state.value ?? const {}).isEmpty) {
      state = AsyncValue.data(fresh);
    }
  }
}

/// One value derived from the server's settings, for a caller that must tell "not
/// answered yet" from "answered, and the answer is no". For a **gate**: a flag that
/// decides whether a control exists. Derived synchronously; a caller outside a build
/// wants [settledGate] (docs/providers.md, "Server settings").
Provider<AsyncValue<T>> serverGate<T>(T Function(Map<String, dynamic>) read) =>
    Provider<AsyncValue<T>>(
      (ref) => ref.watch(serverSettingsProvider).whenData(read),
    );

/// A server capability as a gate a screen can read on its first frame — the
/// [serverGate] of an [ObservedCapability], decided in the latch's order: what
/// the server said, then the version row, then [ObservedCapability.whenUnknown].
/// The whole path, and how to read a gate, is in `docs/server-gates.md` ("From
/// latch to screen").
Provider<AsyncValue<bool>> capabilityGate(
  ObservedCapability Function(Ref ref) latchOf,
) => Provider<AsyncValue<bool>>((ref) {
  // A repository that cannot be built (no server profile yet) is an error the
  // reader folds into "no", as it was while every gate was a FutureProvider —
  // not an exception thrown into the widget's build.
  final ObservedCapability latch;
  try {
    latch = latchOf(ref);
  } on Object catch (error, stack) {
    return AsyncError(error, stack);
  }
  final epoch = ref.watch(serverContactEpochProvider);
  latch.forgetRefusalsBefore(ref.watch(refusalsForgottenProvider));
  void heard() => ref.invalidateSelf();
  latch.addListener(heard);
  ref.onDispose(() => latch.removeListener(heard));

  final inFlight = latch.whenUnknown
      ? const AsyncData(true)
      : const AsyncLoading<bool>();

  if (latch.observedAnswer case final answer?) return AsyncData(answer);
  if (latch.canProbe) {
    latch.probeIfUnknown(epoch: epoch);
    return latch.probeFailed ? AsyncData(latch.whenUnknown) : inFlight;
  }
  final feature = latch.feature;
  if (feature == null) return AsyncData(latch.whenUnknown);
  final version = ref.watch(serverVersionProvider);
  if (!version.hasValue && !version.hasError) return inFlight;
  return AsyncData(version.value?.supports(feature) ?? latch.whenUnknown);
});

extension AsyncGate on AsyncValue<bool> {
  /// Both must hold. A settled "no" on either side is final even while the
  /// other is unanswered, and an error is handed on rather than turned into
  /// loading — [settledGate] would wait on that forever. Both sides are
  /// evaluated (see "Combining" in `docs/server-gates.md`).
  AsyncValue<bool> and(AsyncValue<bool> other) {
    if (value == false || other.value == false) {
      return const AsyncData(false);
    }
    if (hasError) return this;
    if (other.hasError) return other;
    return hasValue && other.hasValue
        ? const AsyncData(true)
        : const AsyncLoading();
  }
}

/// The settled answer of [gate], for code running outside a build, which gets
/// no second look when the settings land. It waits on the gate rather than on
/// `/settings`, so overriding the gate decides the answer.
Future<T> settledGate<T>(
  ProviderContainer providers,
  ProviderListenable<AsyncValue<T>> gate,
) {
  final settled = Completer<T>();
  void offer(AsyncValue<T> answer) {
    if (settled.isCompleted) return;
    if (answer.hasError) {
      settled.completeError(answer.error!, answer.stackTrace);
    } else if (answer.hasValue) {
      settled.complete(answer.requireValue);
    }
  }

  final subscription = providers.listen<AsyncValue<T>>(
    gate,
    (_, answer) => offer(answer),
    fireImmediately: true,
  );
  return settled.future.whenComplete(subscription.close);
}

/// One value derived from the server's settings, resolved immediately against the
/// fallback the server itself would have used. For a **value**, not a gate: nothing
/// is hidden while the settings are in flight (docs/providers.md, "Server settings").
Provider<T> serverValue<T>(T Function(Map<String, dynamic>) read) =>
    Provider<T>(
      (ref) => read(ref.watch(serverSettingsProvider).value ?? const {}),
    );

/// Highest `copies` a pipeline run accepts (`pipeline_max_copies`). The server
/// answers **422** above it rather than clamping, so the stepper has to know.
/// 50 is the server's own fallback for an unset or unparseable value
/// (`routes/pipeline_runs.py::run_pipeline`).
final pipelineMaxCopiesProvider = serverValue<int>((settings) {
  final parsed = settings.settingDouble('pipeline_max_copies', 50).toInt();
  return parsed > 0 ? parsed : 50;
});

/// The symbol for the currency the server keeps prices in, or `''` when it has
/// not said. Reads the settings the app already fetches once per session.
final currencySymbolProvider = serverValue<String>((settings) {
  final code = settings.settingString('currency');
  return currencySymbol(code is String ? code : null);
});

/// What a kilogram of filament costs where no spool says otherwise
/// (`default_filament_cost`, 25 on a fresh server), which prices a job's preview.
final defaultFilamentCostProvider = serverValue<double>(
  (settings) => settings.settingDouble('default_filament_cost', 25),
);

/// Whether the scheduler requires per-printer plate-clear confirmation before
/// starting queued prints. Gates the plate badge / "clear plate" button and the
/// pre-start confirmation.
final requirePlateClearProvider = serverGate<bool>(
  (settings) => settings.settingBool('require_plate_clear'),
);

/// "Prefer lowest remaining filament": among equal matches the mapping picks
/// the emptiest spool, as the web's (`effectivePreferLowest`).
final preferLowestFilamentProvider = serverGate<bool>(
  (settings) => settings.settingBool('prefer_lowest_filament'),
);

/// Printer models with an auto-print G-code snippet configured on the server.
/// Gates the print form's `gcode_injection` checkbox (see
/// [gcodeSnippetModels]): without snippets the flag does nothing, so the web
/// hides it too.
final gcodeSnippetModelsProvider = serverGate<Set<String>>(
  (settings) => gcodeSnippetModels(settings['gcode_snippets']),
);

/// MakerWorld integration (model import).
final makerworldRepositoryProvider = Provider<MakerWorldRepository>(
  (ref) => MakerWorldRepository(ref.watch(apiClientProvider).dio),
);

/// Bambu Cloud login (prerequisite for downloads).
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

/// Announcements from the Bambuddy maintainers.
final announcementsRepositoryProvider = Provider<AnnouncementsRepository>(
  (ref) => AnnouncementsRepository(ref.watch(apiClientProvider).dio),
);

/// Manyfold library (#1471).
final manyfoldRepositoryProvider = Provider<ManyfoldRepository>(
  (ref) => ManyfoldRepository(ref.watch(apiClientProvider).dio),
);

/// Whether this session may connect Manyfold — `settings:update`, which an API
/// key never holds; a server without auth refuses nobody.
final canConfigureManyfoldProvider = Provider<bool>((ref) {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  return ref.watch(permissionProvider(Permissions.settingsUpdate));
});

/// The filament inventory the server runs — asked once per server, the server
/// being where the choice is made. A failed ask is an error rather than a
/// guess; [inventoryRepositoryProvider] asks again on its next call.
final inventoryBackendProvider = FutureProvider<InventoryBackend>(
  (ref) => detectInventoryBackend(ref.watch(apiClientProvider).dio),
);

/// Inventory data source for the backend the server runs; rebuilt on profile or
/// backend change.
final inventorySourceProvider = FutureProvider<SpoolInventorySource>((
  ref,
) async {
  final dio = ref.watch(apiClientProvider).dio;
  return switch (await ref.watch(inventoryBackendProvider.future)) {
    InventoryBackend.native => NativeInventorySource(dio),
    InventoryBackend.spoolman => SpoolmanInventorySource(dio),
  };
});

/// Filament inventory. Facade over the chosen source, usable before the server has
/// said which one: its calls wait for the answer. A settled failure is not kept;
/// read [InventoryRepository.backend], never [inventoryBackendProvider]'s future
/// (docs/providers.md, "Repositories that must not be autoDispose").
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  void askAgainIfFailed() {
    final asked = ref.read(inventoryBackendProvider);
    if (asked.hasError && !asked.isLoading) {
      ref.invalidate(inventoryBackendProvider);
    }
  }

  return InventoryRepository.resolving(
    () {
      askAgainIfFailed();
      return ref.read(inventorySourceProvider.future);
    },
    () {
      askAgainIfFailed();
      return ref.read(inventoryBackendProvider.future);
    },
    ref.watch(serverVersionServiceProvider),
  );
});

/// Service minting the camera stream token (the live view; on servers older
/// than #3025 also every other `?token=` image). Rebuilt with client on profile
/// change.
final cameraTokenServiceProvider = Provider<CameraTokenService>(
  (ref) => CameraTokenService(ref.watch(apiClientProvider).dio),
);

/// Camera token for the live view. Service holds cache; this future provides
/// current token for building the stream URL. Invalidate:
/// `ref.invalidate(cameraTokenProvider)` after 401 from protected resource.
final cameraTokenProvider = FutureProvider<String>(
  (ref) => ref.watch(cameraTokenServiceProvider).token(),
);

/// Service minting the media token (#3025). Rebuilt with client on profile
/// change, like [cameraTokenServiceProvider].
final mediaTokenServiceProvider = Provider<MediaTokenService>(
  (ref) => MediaTokenService(ref.watch(apiClientProvider).dio),
);

/// Picks the credential this server accepts on the media routes — see
/// [MediaAuthService] for the three answers.
final mediaAuthServiceProvider = Provider<MediaAuthService>(
  (ref) => MediaAuthService(
    media: ref.watch(mediaTokenServiceProvider),
    camera: ref.watch(cameraTokenServiceProvider),
    authMode: ref.watch(serverProfileProvider)?.authMode ?? AuthMode.none,
    credentials: ref.watch(credentialsStoreProvider),
  ),
);

/// The credential every media URL is built with. Invalidate together with
/// `ref.read(mediaAuthServiceProvider).invalidate()` after a 401 — see
/// [MediaAuthImageRecovery].
final mediaAuthProvider = FutureProvider<MediaAuth>(
  (ref) => ref.watch(mediaAuthServiceProvider).auth(),
);
