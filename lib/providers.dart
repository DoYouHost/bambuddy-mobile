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
import 'data/archive_repository.dart';
import 'data/firmware_repository.dart';
import 'data/inventory_repository.dart';
import 'data/inventory_source.dart';
import 'data/printer_commands_repository.dart';
import 'data/maintenance_repository.dart';
import 'data/printers_repository.dart';
import 'data/queue_repository.dart';
import 'data/smart_plugs_repository.dart';

/// Nadpisywany w main() po SharedPreferences.getInstance().
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Nadpisz w ProviderScope'),
);

/// Nadpisywany w main() zainicjalizowaną instancją (init wymaga pluginu).
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Nadpisz w ProviderScope'),
);

final credentialsStoreProvider =
    Provider<CredentialsStore>((ref) => SecureCredentialsStore());

/// Mechanizm monitoringu w tle. Dziś zawsze foreground service; furtka na push
/// = podmiana implementacji tutaj (patrz [BackgroundMonitor]).
final backgroundMonitorProvider =
    Provider<BackgroundMonitor>((ref) => ForegroundServiceMonitor());

/// Czy monitoring w tle jest włączony (przełącznik użytkownika, domyślnie tak).
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

/// Preferencje powiadomień (które zdarzenia, jakie progi). Persystencja przez
/// [SettingsRepository]; isolate tła czyta te same prefs niezależnie przy starcie.
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

/// Proaktywna odnowa JWT dla aktywnego profilu: planuje cichy re-login tuż
/// przed wygaśnięciem tokenu, żeby REST i handshake WS nie trafiały na 401
/// (które dopiero reaktywnie ponawiamy). Tylko dla [AuthMode.jwt] — klucz API
/// jest stały, a serwer bez auth nie wygasa; w tych trybach provider daje `null`.
///
/// Sam się NIE uruchamia — to leniwy provider; UI utrzymuje go żywym i steruje
/// nim wg cyklu życia (w tle przejmuje isolate foreground service'u, patrz
/// [PrintMonitorTaskHandler]). Przebudowywany przy zmianie profilu.
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

/// Aktywny profil serwera; `null` = nieskonfigurowany (router → /setup).
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

  /// „Wyloguj / zmień serwer": czyści profil i wszystkie sekrety.
  Future<void> clear() async {
    await ref.read(settingsRepositoryProvider).clearProfile();
    await ref.read(credentialsStoreProvider).clearAll();
    state = null;
  }
}

/// Klient API dla aktywnego profilu. Wymaga skonfigurowanego profilu —
/// trasy bez profilu są przekierowywane do /setup, więc UI nigdy nie
/// powinno tego dotknąć przy null.
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

/// Komendy sterujące (M4). Współdzieli uwierzytelnione Dio z resztą —
/// przebudowywany przy zmianie profilu wraz z [apiClientProvider].
final printerCommandsRepositoryProvider = Provider<PrinterCommandsRepository>(
  (ref) => PrinterCommandsRepository(ref.watch(apiClientProvider).dio),
);

/// Kolejka wydruków (M5). Współdzieli uwierzytelnione Dio.
final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(ref.watch(apiClientProvider).dio),
);

/// Archiwum wydruków (M5). Współdzieli uwierzytelnione Dio.
final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(ref.watch(apiClientProvider).dio),
);

/// Smart gniazdka (M7). Współdzieli uwierzytelnione Dio.
final smartPlugsRepositoryProvider = Provider<SmartPlugsRepository>(
  (ref) => SmartPlugsRepository(ref.watch(apiClientProvider).dio),
);

/// Konserwacja drukarek (M7). Współdzieli uwierzytelnione Dio.
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(apiClientProvider).dio),
);

/// Firmware drukarek. Współdzieli uwierzytelnione Dio.
final firmwareRepositoryProvider = Provider<FirmwareRepository>(
  (ref) => FirmwareRepository(ref.watch(apiClientProvider).dio),
);

/// Wybrany backend magazynu filamentów (natywny domyślnie). Przełącznik
/// użytkownika; Spoolman to drop-in — patrz [SpoolInventorySource].
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

/// Źródło danych magazynu zależne od wybranego backendu. Współdzieli
/// uwierzytelnione Dio; przebudowywane przy zmianie profilu lub backendu.
final inventorySourceProvider = Provider<SpoolInventorySource>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return switch (ref.watch(inventoryBackendProvider)) {
    InventoryBackend.native => NativeInventorySource(dio),
    InventoryBackend.spoolman => SpoolmanInventorySource(dio),
  };
});

/// Magazyn filamentów. Fasada nad wybranym źródłem.
final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(inventorySourceProvider)),
);

/// Serwis mintujący token strumienia kamery (okładka wydruku; od M2 też
/// podgląd kamery). Przebudowywany wraz z klientem przy zmianie profilu.
final cameraTokenServiceProvider = Provider<CameraTokenService>(
  (ref) => CameraTokenService(ref.watch(apiClientProvider).dio),
);

/// Token kamery dla widżetów (okładka). Cache trzyma serwis; ten future
/// udostępnia bieżący token do budowy URL-a obrazka. Invalidacja:
/// `ref.invalidate(cameraTokenProvider)` po 401 z chronionego zasobu.
final cameraTokenProvider = FutureProvider<String>(
  (ref) => ref.watch(cameraTokenServiceProvider).token(),
);
