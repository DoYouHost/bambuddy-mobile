import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'controls_providers.dart';

/// Pause, resume or stop a print and tell the user when the server refused —
/// shared by the printer card and the single-printer controller, so one tap
/// means the same thing on both.
Future<void> runPrintAction(
  BuildContext context,
  WidgetRef ref,
  int printerId,
  ControlAction action,
) async {
  final notifier = ref.read(controlsProvider.notifier);
  final result = switch (action) {
    ControlAction.pause => await notifier.pause(printerId),
    ControlAction.resume => await notifier.resume(printerId),
    ControlAction.stop => await notifier.stop(printerId),
    _ => ActionOutcome.ok,
  };
  if (!context.mounted) return;
  final msg = result.messageFor(AppLocalizations.of(context));
  if (msg == null) return;
  ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
}

/// Stop is always behind a confirmation — one tap must not be enough to kill a
/// print that has run for hours. [confirmId] names the dialog's two buttons in
/// the diagnostic log, so each screen reports under its own.
Future<void> stopPrintConfirmed(
  BuildContext context,
  WidgetRef ref,
  int printerId, {
  required String confirmId,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmDialog(
    context,
    title: l10n.ctrlStopConfirmTitle,
    message: l10n.ctrlStopConfirmBody,
    confirmLabel: l10n.ctrlStop,
    destructive: true,
    id: confirmId,
  );
  if (confirmed && context.mounted) {
    await runPrintAction(context, ref, printerId, ControlAction.stop);
  }
}
