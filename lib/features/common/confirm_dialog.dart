import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../l10n/app_localizations.dart';

/// Shared yes/no confirmation dialog. Replaces the near-identical per-screen
/// `_confirm` / `_confirmDelete` helpers.
///
/// Returns `true` only when the user confirms; cancel/dismiss → `false`.
/// [destructive] styles the confirm button with the error color.
///
/// [id] names the two buttons in the diagnostic log (`<id>.confirm` /
/// `<id>.cancel`). The title is user-facing text and is never recorded, so
/// without an id the log cannot say *what* was confirmed — pass one wherever the
/// answer matters.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  IconData? icon,
  String id = 'confirm',
}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon == null ? null : Icon(icon),
      title: Text(title),
      content: Text(message),
      actions: [
        logTag(
          '$id.cancel',
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel ?? l10n.cancel),
          ),
        ),
        logTag(
          '$id.confirm',
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
