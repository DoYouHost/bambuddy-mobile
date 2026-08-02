import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/maintenance_repository.dart';
import '../api/api_client.dart';
import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';
import '../diagnostics/notif_probe.dart';
import '../diagnostics/session_facts.dart';
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
  final settings = SettingsRepository(prefs);
  final profile = settings.loadProfile();
  if (profile == null) return null;
  final creds = SecureCredentialsStore();
  final auth = AuthService(
    bareDio: createBareDio(),
    credentials: creds,
    // The rejection can just as easily happen here, hours before the user opens
    // the app; the flag is in prefs so the UI still finds it when they do.
    onSignInRequired: (reason) =>
        settings.saveSignInRequired(true, reason: reason),
  );
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

  BackgroundRecording? recording;
  try {
    final prefs = await SharedPreferences.getInstance();
    // Three isolates run this function, and two of them may already own a
    // recording — the UI's when the app is open, the service's when it is
    // backgrounded. Only the dedicated callback engine, where nothing else is
    // logging, opens a stream of its own; in the other two the records land in
    // the stream they belong to, for free.
    if (!DiagnosticRecorder.isRecording) {
      recording = await DiagnosticRecorder.startBackground(
        settings: SettingsRepository(prefs),
        stream: LogStream.action,
        loadSecrets: () => sessionSecrets(
          profile: SettingsRepository(prefs).loadProfile(),
          credentials: SecureCredentialsStore(),
        ),
        // Short-lived and already wrapped end to end; the failures worth a record
        // are the ones named below, not the ones the framework would report.
        attachErrors: false,
      );
    }
    NotifProbe.action(id: maintenancePerformActionId, items: itemIds.length);

    final api = await buildBackgroundApiClient(prefs);
    if (api == null) {
      NotifProbe.noClient();
      return;
    }
    final repo = MaintenanceRepository(api.dio);
    var anyPerformed = false;
    for (final id in itemIds) {
      try {
        await repo.perform(id);
        anyPerformed = true;
      } on Object catch (error) {
        // Isolate callback cannot crash. The request itself is in the HTTP lane;
        // this says the counter the user tapped was not reset.
        NotifProbe.actionFailed(error, items: 1);
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
  } on Object catch (error) {
    // Prevent callback isolate crash — but say so, because from the user's side
    // this is "I pressed Mark Done and nothing happened".
    NotifProbe.actionFailed(error);
  } finally {
    // Best effort: the plugin's entry point cannot await this handler (its
    // signature returns void), so the engine may go away first. It costs at most
    // the last line — every one before it was flushed as it was written.
    await recording?.stop();
  }
}
