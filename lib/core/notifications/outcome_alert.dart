import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_locale.dart';
import '../api/ws_messages.dart';
import '../diagnostics/notif_probe.dart';
import '../models/archive.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// The outcome question as a notification (#1898): what the foreground
/// service posts when the server's `print_confirm_request` arrives while the
/// app is in the background. The app on screen asks with a sheet instead
/// (`outcome_prompt.dart`), so the two never ask at once.

/// Band 14 of the alert ids (see `alertBandWidth` in `print_monitor.dart`).
/// Per archive, not per printer: a reprint of one file on two printers is two
/// questions, and the id is also how an answer given in the app takes the
/// notification away.
int outcomeAlertId(int archiveId) => 14 * 1000000 + archiveId % 1000000;

/// Action ids are `outcome:<verdict wire>`; the archive travels in the payload.
const String outcomeActionIdPrefix = 'outcome:';

String outcomePayload(int archiveId) => 'outcome:$archiveId';

/// The archive an outcome notification is about, or null for any other
/// payload — including one written by a version that formatted it differently.
int? parseOutcomePayload(String? payload) {
  if (payload == null || !payload.startsWith('outcome:')) return null;
  final id = int.tryParse(payload.substring('outcome:'.length));
  return id != null && id > 0 ? id : null;
}

/// The verdict an action id names, or null for any other action.
PrintVerdict? outcomeActionVerdict(String? actionId) =>
    actionId == null || !actionId.startsWith(outcomeActionIdPrefix)
    ? null
    : PrintVerdict.fromWire(actionId.substring(outcomeActionIdPrefix.length));

/// Posts one notification per request the server sends. Good and Reject
/// answer from the notification itself; a tap on its body opens the sheet,
/// where a reject can be given a cause and a reprint.
StreamSubscription<WsPrintConfirmRequest> listenForOutcomeRequests(
  Stream<WsPrintConfirmRequest> requests, {
  required NotificationService notifications,
  required NotificationPrefs prefs,
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
  final l = l10n();
  final name = request.printName;
  unawaited(
    notifications.showAlert(
      event: NotifEvent.outcomeRequest,
      printerId: request.printerId,
      id: outcomeAlertId(request.archiveId),
      title: name == null || name.isEmpty
          ? l.outcomeTitle
          : l.outcomeNotifTitle(name),
      body: l.outcomeNotifBody,
      payload: outcomePayload(request.archiveId),
      actions: [
        for (final verdict in PrintVerdict.values)
          NotificationAction(
            id: '$outcomeActionIdPrefix${verdict.wire}',
            title: switch (verdict) {
              PrintVerdict.good => l.outcomeGood,
              PrintVerdict.reject => l.outcomeReject,
            },
          ),
      ],
    ),
  );
});

/// Takes the outcome notification for [archiveId] away once it has been
/// answered somewhere else. Best-effort: a platform without the plugin (tests)
/// or a notification long gone is nothing to report.
Future<void> cancelOutcomeAlert(int archiveId) async {
  try {
    await FlutterLocalNotificationsPlugin().cancel(
      id: outcomeAlertId(archiveId),
    );
  } on Object {
    // Nothing on screen to take away.
  }
}
