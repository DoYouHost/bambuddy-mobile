import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/maintenance_repository.dart';
import '../../data/printer_commands_repository.dart';
import '../api/api_client.dart';
import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/notif_probe.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';
import 'hms_actions.dart';
import 'hms_stop_request.dart';

/// Action ID for "Mark Done" in maintenance notifications.
/// The notification payload carries a comma-separated list of item IDs to reset.
const String maintenancePerformActionId = 'maint_perform';

/// Action IDs on an HMS alert are `hms:<HMSAction>`; the fault they apply to
/// travels in the payload, since Android hands back only these two strings.
const String hmsActionIdPrefix = 'hms:';

/// Payload of an HMS alert: `hms:<printerId>:<full_code>:<job_id>`. The job id
/// is a bare `subtask_id` and the full code is hex, so neither can contain the
/// separator.
String hmsPayload({
  required int printerId,
  required String fullCode,
  String? jobId,
}) => 'hms:$printerId:$fullCode:${jobId ?? ''}';

/// The fault an HMS notification action refers to, or null when the payload is
/// not one (or was written by a version that formatted it differently).
({int printerId, String fullCode, String? jobId})? parseHmsPayload(
  String? payload,
) {
  if (payload == null || !payload.startsWith('hms:')) return null;
  final parts = payload.split(':');
  if (parts.length != 4) return null;
  final printerId = int.tryParse(parts[1]);
  if (printerId == null || parts[2].isEmpty) return null;
  return (
    printerId: printerId,
    fullCode: parts[2],
    jobId: parts[3].isEmpty ? null : parts[3],
  );
}

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

/// The [AuthService] the isolates without Riverpod build.
///
/// A rejection noticed out here happens hours before the user next opens the
/// app, and the flag left in prefs is the only thing that lets the UI explain
/// the silence when they do — so both isolates have to leave the same mark.
AuthService backgroundAuthService(
  SharedPreferences prefs,
  CredentialsStore credentials,
) => AuthService(
  bareDio: createBareDio(),
  credentials: credentials,
  onSignInRequired: (reason) =>
      SettingsRepository(prefs).saveSignInRequired(true, reason: reason),
);

/// Builds an authenticated [ApiClient] without Riverpod — usable in the
/// background isolate (foreground service) and notification callback isolate
/// where providers are unavailable. Mirrors `apiClientProvider` logic.
/// Returns `null` if no server profile is configured.
Future<ApiClient?> buildBackgroundApiClient(SharedPreferences prefs) async {
  final settings = SettingsRepository(prefs);
  final profile = settings.loadProfile();
  if (profile == null) return null;
  final creds = SecureCredentialsStore();
  final auth = backgroundAuthService(prefs, creds);
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
  handleNotificationAction(response);
}

/// Every notification-button tap arrives here, from whichever isolate the
/// plugin happens to deliver it in. Each handler recognises its own action ids
/// and ignores the rest.
Future<void> handleNotificationAction(NotificationResponse response) async {
  await handleMaintenanceAction(response);
  await handleHmsAction(response);
}

/// Runs the remediation action the user tapped on an HMS alert.
///
/// Stopping a print is the exception: it never runs from here, because a tap
/// that abandons hours of printing has to be confirmed and a notification has
/// nowhere to ask. That button brings the app up instead, and the request is
/// parked in [postHmsStopRequest] for the shell to pick up.
Future<void> handleHmsAction(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null || !actionId.startsWith(hmsActionIdPrefix)) return;
  final action = actionId.substring(hmsActionIdPrefix.length);
  final fault = parseHmsPayload(response.payload);
  if (fault == null) return;
  if (action == hmsStopAction) {
    postHmsStopRequest(
      HmsStopRequest(
        printerId: fault.printerId,
        fullCode: fault.fullCode,
        jobId: fault.jobId,
      ),
    );
    return;
  }

  BackgroundRecording? recording;
  try {
    final prefs = await SharedPreferences.getInstance();
    recording = await DiagnosticRecorder.startAction();
    NotifProbe.action(id: actionId, items: 1);

    final api = await buildBackgroundApiClient(prefs);
    if (api == null) {
      NotifProbe.noClient();
      return;
    }
    await PrinterCommandsRepository(api.dio).executeHmsAction(
      fault.printerId,
      printError: fault.fullCode,
      action: action,
      jobId: fault.jobId,
    );
    final id = response.id;
    if (id != null) {
      await FlutterLocalNotificationsPlugin().cancel(id);
    }
  } on Object catch (error) {
    // The callback isolate cannot crash — but from the user's side this is "I
    // pressed Resume and the printer stayed paused", so it goes on the record.
    // A 502 lands here too: the command went out, the printer never answered.
    NotifProbe.actionFailed(error, items: 1);
  } finally {
    await recording?.stop();
  }
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
    recording = await DiagnosticRecorder.startAction();
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
    // Read-modify-write on a set the service isolate also writes.
    final settings = await SettingsRepository(prefs).reloaded();
    // Failed resets are re-armed too: being *in* this set suppresses the alert,
    // and the button already took the notification away
    // (`cancelNotification: true`), so a re-alert is the only way the user
    // learns the counter never reset.
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
