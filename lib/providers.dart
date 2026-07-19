import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'core/api/api_client.dart';
import 'core/api/camera_token.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/credentials_store.dart';
import 'core/auth/jwt.dart';
import 'core/auth/token_refresher.dart';
import 'core/notifications/background_monitor.dart';
import 'core/notifications/notification_prefs.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/server_profile.dart';
import 'core/settings/settings_repository.dart';
import 'core/watch/watch_config_sync.dart';
import 'core/watch/wear_relay_handler.dart';
import 'core/models/cloud_auth.dart';
import 'core/models/makerworld.dart';
import 'data/ams_history_repository.dart';
import 'data/archive_repository.dart';
import 'data/cloud_repository.dart';
import 'data/discovery_repository.dart';
import 'data/firmware_repository.dart';
import 'data/makerworld_repository.dart';
import 'data/inventory_repository.dart';
import 'data/inventory_source.dart';
import 'data/library_repository.dart';
import 'data/printer_commands_repository.dart';
import 'data/printer_files_repository.dart';
import 'data/maintenance_repository.dart';
import 'data/printers_repository.dart';
import 'data/projects_repository.dart';
import 'data/queue_repository.dart';
import 'data/skip_objects_repository.dart';
import 'data/slicer_repository.dart';
import 'data/smart_plugs_repository.dart';
import 'data/stats_repository.dart';

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
  );
  ref.onDispose(handler.stop);
  return handler;
});

/// Background monitoring mechanism. Currently always foreground service; gate for
/// push = swap implementation here (see [BackgroundMonitor]).
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
/// [SettingsRepository]; background isolate reads same prefs independently on startup.
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

final bareDioProvider = Provider<Dio>((ref) => createBareDio());

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    bareDio: ref.watch(bareDioProvider),
    credentials: ref.watch(credentialsStoreProvider),
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
  final refresher = ProactiveTokenRefresher(
    readExpiry: () async => jwtExpiry(await creds.readJwt()),
    refresh: () async => jwtExpiry(await auth.silentReLogin(profile.baseUrl)),
  );
  ref.onDispose(refresher.stop);
  return refresher;
});

/// Proactive camera-token refresh: re-mints the shared camera token (thumbnails,
/// covers, camera stream) just before its client TTL lapses, so foreground image
/// loads don't hit a 401 first. Reactive re-mint on 401 stays the safety net
/// ([PrintThumbnail], [CameraView]). UI-only (background cover fetch in the FGS
/// isolate re-mints reactively); kept alive + lifecycle-controlled by the
/// dashboard, like [tokenRefresherProvider]. Demo mode has no token to refresh.
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
      // to them. gaplessPlayback keeps already-shown thumbnails from flickering.
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
    await ref.read(settingsRepositoryProvider).saveProfile(profile);
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
/// alive while the dashboard is still mounted under the drawer, so on clear they
/// rebuild and would hit the null-profile throw before the redirect unmounts
/// them. Returning the last client keeps them from crashing; it's never used for
/// requests (its consumers are guarded / about to unmount) and is replaced as
/// soon as a new profile is set. Safe to cache — [ApiClient] holds no resources
/// needing disposal.
ApiClient? _lastApiClient;

/// API client for active profile. Requires configured profile — routes without
/// profile redirect to /setup, so UI should never touch this when null.
final apiClientProvider = Provider<ApiClient>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) {
    final cached = _lastApiClient;
    if (cached != null) {
      // Expected only during the teardown frame on "change server". If it fires
      // elsewhere, a consumer is reading the client without a null-profile guard
      // and would hit the previous server — surface it in debug.
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

/// AMS sensor history (temperature + humidity charts). Shares authenticated Dio.
final amsHistoryRepositoryProvider = Provider<AmsHistoryRepository>(
  (ref) => AmsHistoryRepository(ref.watch(apiClientProvider).dio),
);

/// Print queue (M5). Shares authenticated Dio.
final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(ref.watch(apiClientProvider).dio),
);

/// Archive of prints (M5). Shares authenticated Dio.
final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(ref.watch(apiClientProvider).dio),
);

/// Projects (group prints toward a goal + BOM/stats/timeline). Shares authenticated Dio.
final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(ref.watch(apiClientProvider).dio),
);

/// Smart plugs (M7). Shares authenticated Dio.
final smartPlugsRepositoryProvider = Provider<SmartPlugsRepository>(
  (ref) => SmartPlugsRepository(ref.watch(apiClientProvider).dio),
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
  (ref) => LibraryRepository(ref.watch(apiClientProvider).dio),
);

/// Printer on-device storage (file manager). Shares authenticated Dio.
final printerFilesRepositoryProvider = Provider<PrinterFilesRepository>(
  (ref) => PrinterFilesRepository(ref.watch(apiClientProvider).dio),
);

/// Server-side slicing (sidecar). Shares authenticated Dio.
final slicerRepositoryProvider = Provider<SlicerRepository>(
  (ref) => SlicerRepository(ref.watch(apiClientProvider).dio),
);

/// Raw server `AppSettings` (best-effort, cached per session). Feature flags
/// derive from this so we fetch `/settings` once.
final serverSettingsProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(slicerRepositoryProvider).serverSettings(),
);

/// Whether the scheduler requires per-printer plate-clear confirmation before
/// starting queued prints. Gates the plate badge / "clear plate" button and the
/// pre-start confirmation.
final requirePlateClearProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(serverSettingsProvider.future))['require_plate_clear'] ==
      true,
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
  (ref) => InventoryRepository(ref.watch(inventorySourceProvider)),
);

/// Service minting camera stream token (print cover; from M2 also camera preview).
/// Rebuilt with client on profile change.
final cameraTokenServiceProvider = Provider<CameraTokenService>(
  (ref) => CameraTokenService(ref.watch(apiClientProvider).dio),
);

/// Camera token for widgets (cover). Service holds cache; this future provides
/// current token for building image URL. Invalidate: `ref.invalidate(cameraTokenProvider)`
/// after 401 from protected resource.
final cameraTokenProvider = FutureProvider<String>(
  (ref) => ref.watch(cameraTokenServiceProvider).token(),
);
