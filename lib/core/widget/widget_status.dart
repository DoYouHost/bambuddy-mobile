import 'package:home_widget/home_widget.dart';

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import '../printers/printer_bucket.dart';

/// Asks the launcher to redraw [androidProvider] with the data just saved. The
/// qualified name must carry the applicationId, or the update goes nowhere.
Future<void> refreshWidgetProvider(String androidProvider) async {
  await HomeWidget.updateWidget(
    androidName: androidProvider,
    qualifiedAndroidName:
        'page.codeberg.morganmlgman.bambuddy_mobile.$androidProvider',
  );
}

/// The file being printed, or the prep stage while the server has no file name
/// yet; empty when neither is known. A blank `currentPrint` does not fall back to
/// `gcodeFile`: it goes straight to the stage.
String activePrintLabel(PrinterStatus s) {
  final name = (s.currentPrint ?? s.gcodeFile)?.trim();
  if (name != null && name.isNotEmpty) return name;
  return s.stgCurName?.trim() ?? '';
}

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
    required String? Function(HmsError)? describe,
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
