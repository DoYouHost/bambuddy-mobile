import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/camera_token.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/credentials_store.dart';
import 'core/auth/token_refresher.dart';
import 'core/notifications/background_monitor.dart';
import 'core/notifications/notification_prefs.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/server_profile.dart';
import 'core/settings/settings_repository.dart';
import 'core/models/cloud_auth.dart';
import 'core/models/makerworld.dart';
import 'data/ams_history_repository.dart';
import 'data/archive_repository.dart';
import 'data/cloud_repository.dart';
import 'data/firmware_repository.dart';
import 'data/makerworld_repository.dart';
import 'data/inventory_repository.dart';
import 'data/inventory_source.dart';
import 'data/library_repository.dart';
import 'data/printer_commands_repository.dart';
import 'data/maintenance_repository.dart';
import 'data/printers_repository.dart';
import 'data/projects_repository.dart';
import 'data/queue_repository.dart';
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
    readJwt: creds.readJwt,
    refresh: () => auth.silentReLogin(profile.baseUrl),
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

/// API client for active profile. Requires configured profile — routes without
/// profile redirect to /setup, so UI should never touch this when null.
final apiClientProvider = Provider<ApiClient>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) {
    throw StateError('apiClientProvider użyty bez profilu serwera');
  }
  final auth = ref.watch(authServiceProvider);
  return ApiClient(
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

/// Printer commands (M4). Shares authenticated Dio with rest — rebuilt on
/// profile change with [apiClientProvider].
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
