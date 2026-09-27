import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_locale.dart';
import '../api/ws_messages.dart';
import '../diagnostics/notif_probe.dart';
import '../format/stable_digest.dart';
import '../models/archive.dart';
import 'alert_ids.dart';
import 'finish_alert_memory.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// The outcome question as a notification (#1898): what the foreground
/// service posts when the server's `print_confirm_request` arrives while the
/// app is in the background. The app on screen asks with a sheet instead
/// (`outcome_prompt.dart`), so the two never ask at once.

/// Band 14 of the alert ids (bands 1–13 are `print_monitor.dart` and
/// `maintenance_monitor.dart`).
/// Per archive, not per printer: a reprint of one file on two printers is two
/// questions, and the id is also how an answer given in the app takes the
/// notification away.
int outcomeAlertId(int archiveId) =>
    14 * alertBandWidth + archiveId % alertBandWidth;

/// Action ids are `outcome:<verdict wire>`; the archive travels in the payload.
const String outcomeActionIdPrefix = 'outcome:';

/// `outcome:<archiveId>:<server>`. An archive id means something only on the
/// server that sent it, and the notification outlives a switch to another
/// one — where the same id is somebody else's print. [serverUrl] goes in as
/// a digest, not in the clear.
String outcomePayload(int archiveId, String serverUrl) =>
    'outcome:$archiveId:${outcomeServerTag(serverUrl)}';

String outcomeServerTag(String serverUrl) =>
    stableDigest(serverUrl).toRadixString(16);

/// The archive and server an outcome notification is about, or null for any
/// other payload — including one written by a version that formatted it
/// differently.
({int archiveId, String server})? parseOutcomePayload(String? payload) {
  if (payload == null || !payload.startsWith('outcome:')) return null;
  final parts = payload.split(':');
  if (parts.length != 3 || parts[2].isEmpty) return null;
  final id = int.tryParse(parts[1]);
  return id != null && id > 0 ? (archiveId: id, server: parts[2]) : null;
}

/// The verdict an action id names, or null for any other action.
PrintVerdict? outcomeActionVerdict(String? actionId) =>
    actionId == null || !actionId.startsWith(outcomeActionIdPrefix)
    ? null
    : PrintVerdict.fromWire(actionId.substring(outcomeActionIdPrefix.length));

/// Puts the outcome buttons on a notification already asking, answering
/// whether it did; see `FinishPhotoNotifier.addOutcome`.
typedef AddOutcomeToFinished =
    Future<bool> Function({
      required int archiveId,
      required int printerId,
      required String payload,
      required List<NotificationAction> actions,
    });

/// Asks once per request the server sends: on the print-finished alert when
/// it is still on screen ([addToFinished]), otherwise with a notification of
/// its own — swiped away, switched off, or never posted. Good and Reject
/// answer from the notification itself; a tap on its body opens the sheet,
/// where a reject can be given a cause and a reprint.
StreamSubscription<WsPrintConfirmRequest> listenForOutcomeRequests(
  Stream<WsPrintConfirmRequest> requests, {
  required NotificationService notifications,
  required NotificationPrefs prefs,
  required String serverUrl,
  AddOutcomeToFinished? addToFinished,
  AppLocalizations Function() l10n = systemAppLocalizations,
}) => requests.listen((request) {
  if (!prefs.isOn(NotifEvent.outcomeRequest)) {
    NotifProbe.suppressed(
      prefs.alertsEnabled ? NotifSkip.typeOff : NotifSkip.alertsOff,
      printerId: request.printerId,
      event: NotifEvent.outcomeRequest,
    );
    return;
  }
  unawaited(_ask(request, notifications, serverUrl, addToFinished, l10n()));
});

Future<void> _ask(
  WsPrintConfirmRequest request,
  NotificationService notifications,
  String serverUrl,
  AddOutcomeToFinished? addToFinished,
  AppLocalizations l,
) async {
  final payload = outcomePayload(request.archiveId, serverUrl);
  final actions = [
    for (final verdict in PrintVerdict.values)
      NotificationAction(
        id: '$outcomeActionIdPrefix${verdict.wire}',
        title: switch (verdict) {
          PrintVerdict.good => l.outcomeGood,
          PrintVerdict.reject => l.outcomeReject,
        },
        // Kept until the answer has landed: the server asks once, so a tap
        // that failed must leave something to tap again.
        dismisses: false,
      ),
  ];
  final added =
      await addToFinished?.call(
        archiveId: request.archiveId,
        printerId: request.printerId,
        payload: payload,
        actions: actions,
      ) ??
      false;
  if (added) return;
  final name = request.printName;
  await notifications.showAlert(
    event: NotifEvent.outcomeRequest,
    printerId: request.printerId,
    id: outcomeAlertId(request.archiveId),
    title: name == null || name.isEmpty
        ? l.outcomeTitle
        : l.outcomeNotifTitle(name),
    body: l.outcomeNotifBody,
    payload: payload,
    actions: actions,
  );
}

/// Takes away whatever still asks about [archiveId] once it has been answered
/// in the app: the notification of its own, and the print-finished alert the
/// buttons were put on ([memory]). Best-effort: a platform without the plugin
/// (tests) or a notification long gone is nothing to report.
Future<void> cancelOutcomeAlert(
  int archiveId, {
  FinishAlertMemory? memory,
}) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(id: outcomeAlertId(archiveId));
    for (final alert in await memory?.entries() ?? const <PostedAlert>[]) {
      if (parseOutcomePayload(alert.payload)?.archiveId != archiveId) continue;
      await plugin.cancel(id: alert.id);
      await memory!.forget(alert.printerId);
    }
  } on Object {
    // Nothing on screen to take away.
  }
}
