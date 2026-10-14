import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_util/app_util.dart';
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
import 'launch_relay.dart';
import 'outcome_alert.dart';
import '../diagnostics/diagnostics_wiring.dart';

/// The server a notification's payload belongs to, as a digest rather than in
/// the clear. A payload names rows by id — a printer, an archive — and an id
/// means something only on the server that sent it, while the notification
/// outlives a switch to another server, where the same id is somebody else's.
String serverTag(String baseUrl) => stableDigest(baseUrl).toRadixString(16);

/// Action ID for "Mark Done" in maintenance notifications.
/// The notification payload carries a comma-separated list of item IDs to reset.
const String maintenancePerformActionId = 'maint_perform';

/// Action IDs on an HMS alert are `hms:<HMSAction>`; the fault they apply to
/// travels in the payload, since Android hands back only these two strings.
const String hmsActionIdPrefix = 'hms:';

/// Payload of an HMS alert: `hms:<printerId>:<full_code>:<job_id>:<server>`.
/// The job id is a bare `subtask_id`, the full code and the [serverTag] are
/// hex, so none can contain the separator.
String hmsPayload({
  required int printerId,
  required String fullCode,
  required String serverUrl,
  String? jobId,
}) => 'hms:$printerId:$fullCode:${jobId ?? ''}:${serverTag(serverUrl)}';

/// The fault an HMS notification action refers to, or null when the payload is
/// not one — including the four-part form builds before the server tag wrote:
/// such a notification cannot say which server's printer it means, and a
/// resume sent to the wrong one is worse than a button that does nothing.
({int printerId, String fullCode, String? jobId, String server})?
parseHmsPayload(String? payload) {
  if (payload == null || !payload.startsWith('hms:')) return null;
  final parts = payload.split(':');
  if (parts.length != 5 || parts[4].isEmpty) return null;
  final printerId = int.tryParse(parts[1]);
  if (printerId == null || parts[2].isEmpty) return null;
  return (
    printerId: printerId,
    fullCode: parts[2],
    jobId: parts[3].isEmpty ? null : parts[3],
    server: parts[4],
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

/// The [AuthService] the isolates without Riverpod build; both leave the same mark in
/// prefs when a rejection is noticed (docs/notification-delivery.md, "Button taps").
AuthService backgroundAuthService(
  SharedPreferences prefs,
  CredentialsStore credentials,
) => AuthService(
  bareDio: createBareDio(),
  credentials: credentials,
  onSignInRequired: (reason) =>
      SettingsRepository(prefs).saveSignInRequired(true, reason: reason),
);

/// Builds an authenticated [ApiClient] without Riverpod, mirroring
/// `apiClientProvider`; `null` if no server profile is configured. A caller that also
/// opens a socket or a token refresher passes its own [credentials] and [auth]: silent
/// re-login is single-flight per [AuthService].
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

/// Good or Reject tapped on an outcome question, or the notification itself. The
/// body opens the app; the two buttons record the verdict from here (a reject without
/// a cause) and take the notification away once the answer landed or no retry can land
/// it (docs/notification-delivery.md, "Button taps").
Future<void> handleOutcomeAction(NotificationResponse response) async {
  final target = parseOutcomePayload(response.payload);
  if (target == null) return;
  final actionId = response.actionId;
  final verdict = outcomeActionVerdict(actionId);
  if (verdict == null || actionId == null) {
    if (response.notificationResponseType ==
            NotificationResponseType.selectedNotification &&
        await _asksThisServer(target.server)) {
      outcomePrompts.post(target.archiveId);
    }
    return;
  }

  await _runAction(
    actionId,
    items: 1,
    failedItems: 1,
    run: (prefs, api) async {
      if (!_isServer(prefs, target.server)) {
        NotifProbe.actionFailed(const ServerChanged(), items: 1);
        await _dismiss(response.id, target.archiveId);
        return;
      }
      final bool applied;
      try {
        applied = (await ArchiveRepository(
          api.dio,
        ).setVerdict(target.archiveId, verdict)).applied;
      } on AppApiException catch (error) {
        // On the record before the dismissal's awaits, which the engine may
        // not outlive. Only a refusal makes the button pointless.
        NotifProbe.actionFailed(error, items: 1);
        if (_isRefusal(error)) await _dismiss(response.id, target.archiveId);
        return;
      }
      // A server older than the feature answers 200 and keeps nothing; the
      // tap did not do what the button said, and no second tap will.
      if (!applied) {
        NotifProbe.actionFailed(const VerdictNotStored(), items: 1);
      }
      await _dismiss(response.id, target.archiveId);
    },
  );
}

/// One button tap, run in whichever isolate the plugin delivered it to: recording
/// first, client from preferences re-read off disk, every failure recorded rather than
/// thrown. [failedItems] is what the failure record says was still pending; null where
/// [run] records its items one by one (docs/notification-delivery.md, "Button taps").
Future<void> _runAction(
  String actionId, {
  required int items,
  int? failedItems,
  required Future<void> Function(SharedPreferences prefs, ApiClient api) run,
}) async {
  BackgroundRecording? recording;
  try {
    recording = await startActionRecording();
    NotifProbe.action(id: actionId, items: items);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final api = await buildBackgroundApiClient(prefs);
    if (api == null) {
      NotifProbe.noClient();
      return;
    }
    await run(prefs, api);
  } on Object catch (error) {
    NotifProbe.actionFailed(error, items: failedItems);
  } finally {
    // Best effort: the plugin's entry point cannot await this handler (its
    // signature returns void), so the engine may go away first. It costs at
    // most the last line — every one before it was flushed as it was written.
    await recording?.stop();
  }
}

/// A notification gone already is not a failed action: the command it
/// carried went out.
Future<void> _cancel(int? id) async {
  if (id == null) return;
  try {
    await FlutterLocalNotificationsPlugin().cancel(id: id);
  } on Object {
    // Gone already, or no plugin to ask.
  }
}

/// Whether the saved profile is the server a payload's [tag] names.
Future<bool> _asksThisServer(String tag) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _isServer(prefs, tag);
  } on Object {
    return false;
  }
}

/// [_asksThisServer] on preferences already re-read.
bool _isServer(SharedPreferences prefs, String tag) {
  final profile = SettingsRepository(prefs).loadProfile();
  return profile != null && serverTag(profile.baseUrl) == tag;
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

/// A notification button tapped after the app was switched to another server
/// than the one whose printer or print it names.
class ServerChanged implements Exception {
  const ServerChanged();
}

/// Runs the remediation action the user tapped on an HMS alert. Stopping a print
/// never runs from here: it brings the app up to confirm, parked in
/// [hmsStopRequests] (docs/notification-delivery.md, "Button taps").
Future<void> handleHmsAction(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null || !actionId.startsWith(hmsActionIdPrefix)) return;
  final action = actionId.substring(hmsActionIdPrefix.length);
  final fault = parseHmsPayload(response.payload);
  if (fault == null) return;
  if (action == hmsStopAction) {
    // Checked here too: the shell confirms and sends the stop to whichever
    // server the app is on now.
    if (!await _asksThisServer(fault.server)) {
      NotifProbe.actionFailed(const ServerChanged(), items: 1);
      await _cancel(response.id);
      return;
    }
    hmsStopRequests.post(
      HmsStopRequest(
        printerId: fault.printerId,
        fullCode: fault.fullCode,
        jobId: fault.jobId,
      ),
    );
    return;
  }

  // From the user's side a failure here is "I pressed Resume and the printer
  // stayed paused" — a 502 too: the command went out, the printer never
  // answered.
  await _runAction(
    actionId,
    items: 1,
    failedItems: 1,
    run: (prefs, api) async {
      if (!_isServer(prefs, fault.server)) {
        NotifProbe.actionFailed(const ServerChanged(), items: 1);
        await _cancel(response.id);
        return;
      }
      await PrinterCommandsRepository(api.dio).executeHmsAction(
        fault.printerId,
        printError: fault.fullCode,
        action: action,
        jobId: fault.jobId,
      );
      await _cancel(response.id);
    },
  );
}

/// Handles tapping "Mark Done" on a maintenance notification, from the plugin's
/// callback isolate: rebuilds everything, resets the item counter, re-arms the dedup
/// set, dismisses. Errors are swallowed (docs/notification-delivery.md, "Button taps").
Future<void> handleMaintenanceAction(NotificationResponse response) async {
  if (response.actionId != maintenancePerformActionId) return;
  final itemIds = parseMaintenancePayload(response.payload);
  if (itemIds.isEmpty) return;

  await _runAction(
    maintenancePerformActionId,
    items: itemIds.length,
    run: (prefs, api) async {
      final repo = MaintenanceRepository(api.dio);
      var anyPerformed = false;
      for (final id in itemIds) {
        try {
          await repo.perform(id);
          anyPerformed = true;
        } on Object catch (error) {
          // The request itself is in the HTTP lane; this says the counter the
          // user tapped was not reset.
          NotifProbe.actionFailed(error, items: 1);
        }
      }
      // Read-modify-write on a set the service isolate also writes.
      final settings = await SettingsRepository(prefs).reloaded();
      // Failed resets are re-armed too: being *in* this set suppresses the
      // alert, and the button already took the notification away
      // (`cancelNotification: true`), so a re-alert is the only way the user
      // learns the counter never reset.
      final notified = settings.loadNotifiedMaintenanceDueIds()
        ..removeAll(itemIds);
      await settings.saveNotifiedMaintenanceDueIds(notified);
      // Signal to UI: server state changed outside the app.
      // Maintenance screen will fetch fresh data on return instead of polling.
      if (anyPerformed) await settings.setMaintenanceDirty(true);
      await _cancel(response.id);
    },
  );
}
