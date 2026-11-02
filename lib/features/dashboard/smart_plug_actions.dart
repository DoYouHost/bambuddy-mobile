import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/smart_plug.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/smart_plugs_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'smart_plugs_providers.dart';

/// Switch a smart plug on or off after the user confirms — shared by the printer
/// card and the single-printer controller, so one tap means the same on both.
/// [confirmId] names the dialog's buttons in the diagnostic log.
Future<void> confirmAndSwitchPlug(
  BuildContext context,
  WidgetRef ref,
  SmartPlug plug,
  bool want, {
  required String confirmId,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmDialog(
    context,
    title: want ? l10n.smartPlugOnConfirmTitle : l10n.smartPlugOffConfirmTitle,
    message: want ? l10n.smartPlugOnConfirmBody : l10n.smartPlugOffConfirmBody,
    confirmLabel: want ? l10n.smartPlugTurnOn : l10n.smartPlugTurnOff,
    // Cutting the power to a machine is the answer worth a red button;
    // turning it on is not.
    destructive: !want,
    id: confirmId,
  );
  if (!confirmed || !context.mounted) return;

  final result = await ref
      .read(smartPlugsProvider.notifier)
      .control(plug.id, want ? SmartPlugAction.on : SmartPlugAction.off);
  if (!context.mounted) return;
  final msg = result.messageFor(l10n);
  if (msg != null) {
    ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
  }
}
