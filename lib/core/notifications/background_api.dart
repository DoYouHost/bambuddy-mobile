import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/maintenance_repository.dart';
import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';

/// Identyfikator akcji „Oznacz wykonane" w powiadomieniach konserwacji.
/// `payload` notyfikacji niesie listę id (`1,2,3`) do zresetowania.
const String maintenancePerformActionId = 'maint_perform';

/// Składa payload notyfikacji konserwacji z listy id pozycji.
String maintenancePayload(Iterable<int> itemIds) => itemIds.join(',');

/// Parsuje payload notyfikacji konserwacji na listę id pozycji (tolerancyjnie).
List<int> parseMaintenancePayload(String? payload) {
  if (payload == null || payload.isEmpty) return const [];
  final ids = <int>[];
  for (final part in payload.split(',')) {
    final id = int.tryParse(part.trim());
    if (id != null) ids.add(id);
  }
  return ids;
}

/// Buduje uwierzytelnione [ApiClient] BEZ Riverpod — używalne w isolacie tła
/// (foreground service) i w isolacie callbacku powiadomień, gdzie nie ma
/// dostępu do providerów. Wzorzec 1:1 z `apiClientProvider`. `null`, gdy nie ma
/// skonfigurowanego profilu serwera.
Future<ApiClient?> buildBackgroundApiClient(SharedPreferences prefs) async {
  final profile = SettingsRepository(prefs).loadProfile();
  if (profile == null) return null;
  final creds = SecureCredentialsStore();
  final auth = AuthService(bareDio: createBareDio(), credentials: creds);
  return ApiClient(
    profile: profile,
    credentials: creds,
    refreshAuth: profile.authMode == AuthMode.jwt
        ? () => auth.silentReLogin(profile.baseUrl)
        : null,
  );
}

/// Wejście isolate'u callbacku powiadomień (apka zamknięta). MUSI być top-level
/// i `@pragma('vm:entry-point')` — plugin uruchamia je w osobnym silniku Dart.
@pragma('vm:entry-point')
void maintenanceNotificationBackgroundHandler(NotificationResponse response) {
  handleMaintenanceAction(response);
}

/// Obsługa tapnięcia akcji „Oznacz wykonane" na powiadomieniu konserwacji —
/// wołana z isolate'u callbacku pluginu (apka może być zamknięta), więc
/// odtwarza całość od zera: prefs, klient API, repo. Resetuje licznik dla
/// każdej pozycji z payloadu, zdejmuje je z dedup-zbioru (re-arm) i kasuje
/// notyfikację. Wszystkie błędy łykane — callback pluginu nie może rzucić.
Future<void> handleMaintenanceAction(NotificationResponse response) async {
  if (response.actionId != maintenancePerformActionId) return;
  final itemIds = parseMaintenancePayload(response.payload);
  if (itemIds.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final api = await buildBackgroundApiClient(prefs);
    if (api == null) return;
    final repo = MaintenanceRepository(api.dio);
    var anyPerformed = false;
    for (final id in itemIds) {
      try {
        await repo.perform(id);
        anyPerformed = true;
      } on Object {
        // Pojedyncza porażka nie blokuje pozostałych.
      }
    }
    final settings = SettingsRepository(prefs);
    final notified = settings.loadNotifiedMaintenanceDueIds()
      ..removeAll(itemIds);
    await settings.saveNotifiedMaintenanceDueIds(notified);
    // Sygnał dla UI: stan serwera się zmienił poza nim. Ekran konserwacji
    // dociągnie świeże dane przy powrocie do apki zamiast czekać na pull-to-refresh.
    if (anyPerformed) await settings.setMaintenanceDirty(true);

    final id = response.id;
    if (id != null) {
      await FlutterLocalNotificationsPlugin().cancel(id);
    }
  } on Object {
    // Brak crasha isolate'u callbacku.
  }
}
