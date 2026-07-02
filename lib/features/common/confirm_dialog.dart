import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shared yes/no confirmation dialog. Replaces the near-identical per-screen
/// `_confirm` / `_confirmDelete` helpers.
///
/// Returns `true` only when the user confirms; cancel/dismiss → `false`.
/// [destructive] styles the confirm button with the error color.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel ?? l10n.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
