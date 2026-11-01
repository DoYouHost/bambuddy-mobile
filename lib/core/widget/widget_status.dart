import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import '../printers/printer_bucket.dart';

/// The status vocabulary both home-screen widgets publish, and the reads that
/// derive it from a [PrinterStatus].
///
/// The keys are wire values: the Kotlin providers switch on them to pick a
/// background and a chip colour, so renaming one here breaks an installed
/// widget until the layout is updated with it.
abstract final class WidgetStatus {
  static const String printing = 'printing';
  static const String paused = 'paused';
  static const String finished = 'finished';
  static const String idle = 'idle';
  static const String offline = 'offline';
  static const String error = 'error';

  /// The bucket name of `classifyPrinter` — the web's one classification — as a
  /// wire key. `failed` is not a key any more: the web files a failed job under
  /// finished, and a fault under error.
  static String keyFor(
    PrinterStatus s, {
    String? Function(HmsError)? describe = catalogHmsDescription,
  }) => classifyPrinter(s, describe: describe).name;

  static String label(AppLocalizations l10n, String key) {
    switch (key) {
      case printing:
        return l10n.widgetStatusPrinting;
      case paused:
        return l10n.widgetStatusPaused;
      case finished:
        return l10n.widgetStatusFinished;
      case offline:
        return l10n.widgetStatusOffline;
      case error:
        return l10n.widgetStatusError;
      default:
        return l10n.widgetStatusIdle;
    }
  }

  /// A printer the widget shows as running: the cases where progress and an ETA
  /// mean something. Read from the job, not the key, so a fault or a preparing
  /// stage does not hide the print.
  static bool isActive(PrinterStatus s) => s.isJobActive;
}
