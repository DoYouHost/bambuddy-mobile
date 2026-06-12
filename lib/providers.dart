import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/camera_token.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/credentials_store.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/server_profile.dart';
import 'core/settings/settings_repository.dart';
import 'data/printer_commands_repository.dart';
import 'data/printers_repository.dart';

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
