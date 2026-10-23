import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import '../notifications/hms_catalog.dart';

/// How often, and how many times, "dismiss all" reads the status back. The
/// printer repeats a standing fault in its next report, a second or two after
/// the server emptied its list; the first read that finds one ends the wait.
const hmsRecheckEvery = Duration(milliseconds: 1500);
const hmsRecheckAttempts = 3;

/// Faults the printer still reports after a clear, as the cards list them, or
/// `null` when [read] could not say.
///
/// The server's 200 only says the command was published. An `hms[]` fault is
/// the printer's own state, rebuilt from every report it sends, so one whose
/// cause is still there comes straight back (docs/server-contract-traps.md,
/// "Clearing HMS errors"). The server pushes no frame for an HMS-only change, so
/// [read] has to be a REST read, not the socket.
Future<int?> hmsStillReported(Future<PrinterStatus?> Function() read) async {
  for (var i = 0; i < hmsRecheckAttempts; i++) {
    await Future<void>.delayed(hmsRecheckEvery);
    final status = await read();
    if (status == null) return null;
    final left = displayableHmsErrors(
      status,
      describe: HmsCatalog.instance.describe,
    ).length;
    if (left > 0) return left;
  }
  return 0;
}

/// What "dismiss all" tells the user once the status was read back: how many
/// faults the printer still reports, else that they are gone. An unreadable
/// status ([remaining] null) gets the plain confirmation, as the server's own
/// 200 deserves.
String hmsDismissedMessage(AppLocalizations l10n, int? remaining) {
  final left = remaining ?? 0;
  return left > 0 ? l10n.hmsStillReported(left) : l10n.hmsDismissed;
}
