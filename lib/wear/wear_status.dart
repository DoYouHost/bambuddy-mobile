import 'package:flutter/material.dart';

import '../core/format/duration_format.dart';
import '../core/models/printer_status.dart';
import '../l10n/app_localizations.dart';

/// Normalized printer state for the watch UI. Kept intentionally coarse — the
/// watch only needs a glanceable label/color and which control buttons to show.
enum WearState { offline, printing, paused, finished, failed, idle }

/// Derives a [WearState] from a (possibly null) [PrinterStatus]. Mirrors the
/// derivation used by the home widget / dashboard so the watch reads the same.
WearState wearStateOf(PrinterStatus? s) {
  if (s == null || s.connected == false) return WearState.offline;
  if (s.isPaused) return WearState.paused;
  if (s.isPrinting) return WearState.printing;
  switch (s.state?.toUpperCase()) {
    case 'FINISH':
    case 'FINISHED':
      return WearState.finished;
    case 'FAILED':
      return WearState.failed;
  }
  return WearState.idle;
}

extension WearStateView on WearState {
  /// Same wording as the home-screen widget statuses.
  String label(AppLocalizations l10n) => switch (this) {
        WearState.offline => l10n.widgetStatusOffline,
        WearState.printing => l10n.widgetStatusPrinting,
        WearState.paused => l10n.widgetStatusPaused,
        WearState.finished => l10n.widgetStatusFinished,
        WearState.failed => l10n.widgetStatusFailed,
        WearState.idle => l10n.widgetStatusIdle,
      };

  Color get color => switch (this) {
        WearState.offline => const Color(0xFF9E9E9E),
        WearState.printing => const Color(0xFF4CAF50),
        WearState.paused => const Color(0xFFFFB300),
        WearState.finished => const Color(0xFF42A5F5),
        WearState.failed => const Color(0xFFEF5350),
        WearState.idle => const Color(0xFF90A4AE),
      };
}

/// Remaining minutes as `1h 23min`; empty when unknown, which is what the
/// caller filters on.
String formatEta(AppLocalizations l10n, int? minutes) =>
    minutes == null || minutes <= 0 ? '' : formatMinutes(l10n, minutes);
