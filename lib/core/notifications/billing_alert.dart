import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../api/ws_messages.dart';
import '../app_context.dart';
import '../diagnostics/notif_probe.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// What the foreground service posts when the server says billing went wrong on
/// a printer: the kill switch stopped a print nobody was authorised to start, or
/// a finished print could not be charged. The web shows both as a toast.

/// Bands 15 and 16 of the alert ids (bands 1–14 are `print_monitor.dart`,
/// `maintenance_monitor.dart` and `outcome_alert.dart`). A stopped print is one
/// alert per printer, a failed charge one per archive: two prints failing to
/// charge on one printer are two problems.
int billingAlertId(WsBillingAlert alert) => switch (alert.kind) {
  BillingAlertKind.killSwitch =>
    15 * alertBandWidth + alert.printerId % alertBandWidth,
  BillingAlertKind.chargeFailed =>
    16 * alertBandWidth + (alert.archiveId ?? alert.printerId) % alertBandWidth,
};

String? _serverName(String? name) {
  final trimmed = name?.trim();
  return trimmed == null ||
          trimmed.isEmpty ||
          trimmed.toLowerCase() == 'unknown'
      ? null
      : trimmed;
}

StreamSubscription<WsBillingAlert> listenForBillingAlerts(
  Stream<WsBillingAlert> alerts, {
  required NotificationService notifications,
  required NotificationPrefs prefs,
  AppLocalizations Function() l10n = systemAppLocalizations,
}) => alerts.listen((alert) {
  if (!prefs.isOn(NotifEvent.billingAlert)) {
    NotifProbe.suppressed(
      prefs.alertsEnabled ? NotifSkip.typeOff : NotifSkip.alertsOff,
      printerId: alert.printerId,
      event: NotifEvent.billingAlert,
    );
    return;
  }
  final l = l10n();
  final printer = (alert.printerName?.trim().isNotEmpty ?? false)
      ? alert.printerName!.trim()
      : l.printersTitle;
  // The server writes the English word itself when it has no name to give
  // (`main.py`: `... or "Unknown"`), so a missing name arrives as that.
  final file = _serverName(alert.filename) ?? l.notifBillingUnknownFile;
  final killed = alert.kind == BillingAlertKind.killSwitch;
  unawaited(
    notifications.showAlert(
      event: NotifEvent.billingAlert,
      printerId: alert.printerId,
      id: billingAlertId(alert),
      title: killed ? l.notifBillingKillTitle : l.notifBillingChargeTitle,
      body: killed
          ? l.notifBillingKillBody(printer, file)
          : l.notifBillingChargeBody(printer, file),
      payload: 'printer:${alert.printerId}',
    ),
  );
});
