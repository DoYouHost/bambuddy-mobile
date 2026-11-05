import 'package:material_ui/material_ui.dart';

import '../core/format/duration_format.dart';
import '../core/models/printer_status.dart';
import '../core/notifications/hms_catalog.dart';
import '../core/printers/printer_bucket.dart';
import '../l10n/app_localizations.dart';

/// Normalized printer state for the watch UI. Kept intentionally coarse — the
/// watch only needs a glanceable label/color; which buttons to show follows the
/// job ([PrinterStatus.isJobActive]), not this.
enum WearState { offline, printing, paused, finished, error, idle }

/// The watch's name for the printer's bucket — the one classification
/// ([classifyPrinter], the web's) every surface reads, so the watch never says
/// something else than the phone's filter or the widget.
WearState wearStateOf(PrinterStatus? s) =>
    switch (classifyPrinter(s, describe: HmsCatalog.instance.describe)) {
      PrinterStatusBucket.offline => WearState.offline,
      PrinterStatusBucket.printing => WearState.printing,
      PrinterStatusBucket.paused => WearState.paused,
      PrinterStatusBucket.finished => WearState.finished,
      PrinterStatusBucket.error => WearState.error,
      PrinterStatusBucket.idle || PrinterStatusBucket.all => WearState.idle,
    };

extension WearStateView on WearState {
  /// Same wording as the home-screen widget statuses.
  String label(AppLocalizations l10n) => switch (this) {
    WearState.offline => l10n.widgetStatusOffline,
    WearState.printing => l10n.widgetStatusPrinting,
    WearState.paused => l10n.widgetStatusPaused,
    WearState.finished => l10n.widgetStatusFinished,
    WearState.error => l10n.widgetStatusError,
    WearState.idle => l10n.widgetStatusIdle,
  };

  /// Printing wears the accent, as the phone's status chip does; the rest are
  /// states to tell apart, not branding, and keep their own colours.
  Color colorIn(ColorScheme scheme) => switch (this) {
    WearState.offline => const Color(0xFF9E9E9E),
    WearState.printing => scheme.primary,
    WearState.paused => const Color(0xFFFFB300),
    WearState.finished => const Color(0xFF42A5F5),
    WearState.error => const Color(0xFFEF5350),
    WearState.idle => const Color(0xFF90A4AE),
  };
}

/// Remaining minutes as `1h 23min`; empty when unknown, which is what the
/// caller filters on.
String formatEta(AppLocalizations l10n, int? minutes) =>
    minutes == null || minutes <= 0 ? '' : formatMinutes(l10n, minutes);
