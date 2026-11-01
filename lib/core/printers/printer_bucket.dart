import '../models/printer_status.dart';
import '../notifications/hms_catalog.dart';

/// Coarse status buckets a printer can fall into — mirrors the web app's
/// `classifyPrinterStatus` so every surface groups and words printers the same
/// way: the dashboard filter, the locations screen, the home-screen widgets and
/// the watch.
enum PrinterStatusBucket {
  all,
  printing,
  idle,
  paused,
  finished,
  error,
  offline,
}

/// Classify a printer's live [status] into one bucket — the web's
/// `classifyPrinterStatus` (`PrintersPage.tsx`), state for state: offline (no
/// connection, or none reported) wins, then error (a displayable HMS error —
/// nothing else is one), then the print state. A `FAILED` job without an HMS
/// code is the printer's terminal state after any unsuccessful end, a
/// cancellation included, so it counts as finished; a preparing printer and any
/// other state fall back to idle.
///
/// [describe] names an HMS code and is required, as for the other HMS filters:
/// no isolate is handed another's catalogue. The UI passes
/// `HmsCatalog.instance.describe`, a background isolate its own, and `null`
/// means "none loaded".
/// Never returns [PrinterStatusBucket.all] (that's the "no filter" sentinel).
PrinterStatusBucket classifyPrinter(
  PrinterStatus? status, {
  required String? Function(HmsError)? describe,
}) {
  if (!(status?.connected ?? false)) return PrinterStatusBucket.offline;
  // The same displayable HMS errors the card surfaces, through the shared
  // filter, so the two cannot drift.
  if (firstDisplayableHmsError(status, describe: describe) != null) {
    return PrinterStatusBucket.error;
  }
  switch (status!.state?.toUpperCase()) {
    case 'RUNNING':
      return PrinterStatusBucket.printing;
    case 'PAUSE':
    case 'PAUSED':
      return PrinterStatusBucket.paused;
    case 'FINISH':
    case 'FINISHED':
    case 'FAILED':
      return PrinterStatusBucket.finished;
    default:
      return PrinterStatusBucket.idle;
  }
}
