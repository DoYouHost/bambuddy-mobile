import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/archive_repository.dart';
import '../../data/maintenance_repository.dart';
import '../../data/printer_commands_repository.dart';
import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import '../diagnostics/notif_probe.dart';
import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';
import 'finish_alert_memory.dart';
import 'hms_actions.dart';
import 'hms_stop_request.dart';
import 'outcome_alert.dart';
import 'outcome_prompt.dart';
import '../diagnostics/diagnostics_wiring.dart';

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
///
/// A caller that also opens a socket or a token refresher passes its own
/// [credentials] and [auth]: silent re-login is single-flight per
/// [AuthService], so a second instance for the REST lane is a second login
/// racing the first against the server's failed-attempt budget.
Future<ApiClient?> buildBackgroundApiClient(
  SharedPreferences prefs, {
  CredentialsStore? credentials,
  AuthService? auth,
}) async {
  // Both or neither: an [auth] given without its store would re-login through
  // one store while the client read tokens from another.
  assert(
    (credentials == null) == (auth == null),
    'pass credentials and auth together',
  );
  final settings = SettingsRepository(prefs);
  final profile = settings.loadProfile();
  if (profile == null) return null;
  final creds = credentials ?? SecureCredentialsStore();
  final reLogin = auth ?? backgroundAuthService(prefs, creds);
  return ApiClient(
    profile: profile,
    credentials: creds,
    refreshAuth: profile.authMode == AuthMode.jwt
        ? () => reLogin.silentReLogin(profile.baseUrl)
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
  await handleOutcomeAction(response);
}

/// Good or Reject tapped on an outcome question — its own notification or
/// the print-finished alert it was put on — or the notification itself.
///
/// The body opens the app, so it only ever arrives where the app is coming up
/// — the foreground handler or the launch details — and is handed to the
/// shell's sheet, where a reject can be given a cause. The two buttons record
/// the verdict from here, like "Mark Done": a reject without a cause, and
/// never touching one the print already carries.
///
/// The buttons do not dismiss the notification themselves (the server asks
/// once): it is taken away here once the answer landed, or once no retry can
/// land it — a refusal, or a question from a server the app has since been
/// switched away from, whose archive id names some other print here.
Future<void> handleOutcomeAction(NotificationResponse response) async {
  final target = parseOutcomePayload(response.payload);
  if (target == null) return;
  final actionId = response.actionId;
  final verdict = outcomeActionVerdict(actionId);
  if (verdict == null || actionId == null) {
    if (response.notificationResponseType ==
            NotificationResponseType.selectedNotification &&
        await _asksThisServer(target.server)) {
      postOutcomePrompt(target.archiveId);
    }
    return;
  }

  BackgroundRecording? recording;
  try {
    recording = await startActionRecording();
    NotifProbe.action(id: actionId, items: 1);
    final prefs = await SharedPreferences.getInstance();
    final profile = (await SettingsRepository(prefs).reloaded()).loadProfile();
    if (profile == null) {
      NotifProbe.noClient();
      return;
    }
    if (outcomeServerTag(profile.baseUrl) != target.server) {
      NotifProbe.actionFailed(const OutcomeServerChanged(), items: 1);
      await _dismiss(response.id, target.archiveId);
      return;
    }
    final api = await buildBackgroundApiClient(prefs);
    if (api == null) {
      NotifProbe.noClient();
      return;
    }
    final result = await ArchiveRepository(
      api.dio,
    ).setVerdict(target.archiveId, verdict);
    // A server older than the feature answers 200 and keeps nothing; the tap
    // did not do what the button said, and no second tap will.
    if (!result.applied) {
      NotifProbe.actionFailed(const VerdictNotStored(), items: 1);
    }
    await _dismiss(response.id, target.archiveId);
  } on AppApiException catch (error) {
    // "I pressed Good and the print still waits for a verdict" — on the record.
    NotifProbe.actionFailed(error, items: 1);
    if (_isRefusal(error)) await _dismiss(response.id, target.archiveId);
  } on Object catch (error) {
    NotifProbe.actionFailed(error, items: 1);
  } finally {
    await recording?.stop();
  }
}

/// Whether the saved profile is the server a payload's [tag] names.
Future<bool> _asksThisServer(String tag) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final profile = (await SettingsRepository(prefs).reloaded()).loadProfile();
    return profile != null && outcomeServerTag(profile.baseUrl) == tag;
  } on Object {
    return false;
  }
}

/// The server answered and said no; asking again would get the same answer.
/// A 5xx is not one — a proxy's 502 can arrive after the server stored it.
bool _isRefusal(AppApiException error) =>
    error.code == AppErrorCode.forbidden ||
    (error is ApiException && (error.statusCode ?? 500) < 500);

/// Takes the tapped notification away, and with it the memory entry that
/// would let a photo landing later bring an answered alert back.
Future<void> _dismiss(int? id, int archiveId) async {
  try {
    await cancelOutcomeAlert(
      archiveId,
      memory: FinishAlertMemory(await SharedPreferences.getInstance()),
    );
    if (id != null) await FlutterLocalNotificationsPlugin().cancel(id: id);
  } on Object {
    // Gone already, or no plugin to ask.
  }
}

/// The server answered a verdict with a row that does not carry it. Only its
/// class name reaches the log.
class VerdictNotStored implements Exception {
  const VerdictNotStored();
}

/// An outcome button tapped after the app was switched to another server.
class OutcomeServerChanged implements Exception {
  const OutcomeServerChanged();
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
    recording = await startActionRecording();
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
      await FlutterLocalNotificationsPlugin().cancel(id: id);
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
    recording = await startActionRecording();
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
      await FlutterLocalNotificationsPlugin().cancel(id: id);
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
