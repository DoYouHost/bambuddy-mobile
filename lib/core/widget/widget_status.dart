import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';

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
  static const String failed = 'failed';
  static const String idle = 'idle';
  static const String offline = 'offline';
  static const String error = 'error';

  static String keyFor(PrinterStatus s) {
    if (!(s.connected ?? false)) return offline;
    if (s.isPaused) return paused;
    if (s.isPrinting) return printing;
    switch (s.state?.toUpperCase()) {
      case 'FINISH':
      case 'FINISHED':
        return finished;
      case 'FAILED':
        return failed;
    }
    return idle;
  }

  static String label(AppLocalizations l10n, String key) {
    switch (key) {
      case printing:
        return l10n.widgetStatusPrinting;
      case paused:
        return l10n.widgetStatusPaused;
      case finished:
        return l10n.widgetStatusFinished;
      case failed:
        return l10n.widgetStatusFailed;
      case offline:
        return l10n.widgetStatusOffline;
      default:
        return l10n.widgetStatusIdle;
    }
  }

  /// A printer the widget shows as running: the two states where progress and
  /// an ETA mean something.
  static bool isActive(String key) => key == printing || key == paused;

  static int progressPct(PrinterStatus s) {
    final p = s.progress ?? 0;
    final pct = p <= 1 ? (p * 100).round() : p.round();
    return pct.clamp(0, 100);
  }
}
