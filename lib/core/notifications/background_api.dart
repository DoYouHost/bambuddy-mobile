import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/maintenance_repository.dart';
import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';

/// Action ID for "Mark Done" in maintenance notifications.
/// The notification payload carries a comma-separated list of item IDs to reset.
const String maintenancePerformActionId = 'maint_perform';

String maintenancePayload(Iterable<int> itemIds) => itemIds.join(',');

List<int> parseMaintenancePayload(String? payload) {
  if (payload == null || payload.isEmpty) return const [];
  final ids = <int>[];
  for (final part in payload.split(',')) {
    final id = int.tryParse(part.trim());
    if (id != null) ids.add(id);
  }
  return ids;
}

/// Builds an authenticated [ApiClient] without Riverpod — usable in the
/// background isolate (foreground service) and notification callback isolate
/// where providers are unavailable. Mirrors `apiClientProvider` logic.
/// Returns `null` if no server profile is configured.
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

/// Entry point for the notification callback isolate (app may be closed).
/// Must be top-level and marked with `@pragma('vm:entry-point')` —
/// the plugin launches it in a separate Dart engine.
@pragma('vm:entry-point')
void maintenanceNotificationBackgroundHandler(NotificationResponse response) {
  handleMaintenanceAction(response);
}

/// Handles tapping the "Mark Done" action on a maintenance notification.
/// Called from the plugin's callback isolate (app may be closed), so it rebuilds
/// everything from scratch: prefs, API client, repository. Resets the item counter,
/// removes items from the dedup set (re-arm for future alerts), and dismisses
/// the notification. All errors are swallowed — the callback must not throw.
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
        // Isolate callback cannot crash.
      }
    }
    final settings = SettingsRepository(prefs);
    final notified = settings.loadNotifiedMaintenanceDueIds()
      ..removeAll(itemIds);
    await settings.saveNotifiedMaintenanceDueIds(notified);
    // Signal to UI: server state changed outside the app.
    // Maintenance screen will fetch fresh data on return instead of polling.
    if (anyPerformed) await settings.setMaintenanceDirty(true);

    final id = response.id;
    if (id != null) {
      await FlutterLocalNotificationsPlugin().cancel(id);
    }
  } on Object {
    // Prevent callback isolate crash.
  }
}
