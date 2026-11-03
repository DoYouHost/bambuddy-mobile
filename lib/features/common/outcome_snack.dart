import 'package:dash_kit/dash_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/action_outcome.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';

/// Tells the user how an action a notifier handed back went: the failure's
/// wording, or [fallback] when it succeeded (no [fallback] is a silent success).
///
/// The counterpart of `showApiFailure` for an outcome: that one was already
/// recorded when the notifier built it, so never pass it to `showApiFailure`.
/// The caller keeps its own `mounted` check and takes the messenger before the
/// await, as everywhere else.
void snackOutcome(
  ScaffoldMessengerState messenger,
  ActionOutcome outcome,
  AppLocalizations l10n, {
  String? fallback,
}) {
  final message = outcome.messageFor(l10n) ?? fallback;
  if (message != null) messenger.snack(message, clearQueue: true);
}
