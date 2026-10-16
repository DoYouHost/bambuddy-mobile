import 'package:flutter/material.dart';

import '../../../core/models/printer_status.dart';
import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';

/// The pill that names a printer's state, worded as the printer card's own
/// (`_stateChipLabel`) so every screen that shows a printer says the same thing
/// about it. [offline] is the debounced answer, not a bare `connected:false`
/// frame (`OfflineDebounce`).
Widget printerStatePill(
  DashTokens t,
  AppLocalizations l10n,
  PrinterStatus? status, {
  required bool offline,
}) {
  if (offline) {
    return DashPill(
      label: l10n.statusOffline,
      accent: t.danger,
      accentInk: t.dangerInk,
      dense: true,
    );
  }
  final label =
      (status == null
              ? l10n.statusUnavailable
              : status.state ??
                    ((status.connected ?? false) ? l10n.online : l10n.offline))
          .toUpperCase();
  if (status?.isPaused ?? false) {
    return DashPill(
      label: label,
      accent: t.accentOrange,
      accentInk: t.accentOrangeInk,
      dense: true,
    );
  }
  if (status?.isPrinting ?? false) {
    return DashPill(
      label: label,
      accent: t.accentGreen,
      accentInk: t.accentGreenInk,
      dense: true,
    );
  }
  return DashPill(label: label, accent: t.textSecondary, dense: true);
}
