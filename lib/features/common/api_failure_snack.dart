import 'package:flutter/material.dart';

import '../../core/api/action_failure.dart';
import '../../core/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'dash_snack.dart';

/// For a screen that suppresses its own snack, so one import covers both doors.
export '../../core/api/action_failure.dart' show recordActionFailure;

/// Tells the user an action failed, and records that they were told. The screen
/// door of the funnel `docs/diagnostics-log.md` describes.
///
/// Pass `mounted ? messenger : null`: a null one says the screen went away
/// while the request was in flight, and the failure is recorded as reaching
/// nobody rather than dropped. Only the call site knows that.
///
/// [message] is for the one status a feature words better than
/// [AppApiExceptionL10n.localized] — "a tag with that name exists" beats
/// "server returned error 409". Everything else falls through to it.
///
/// Do **not** use it on an outcome a notifier handed back: that was recorded
/// when it was built, and `messageFor` is its wording.
void showApiFailure(
  ScaffoldMessengerState? messenger,
  AppApiException error,
  AppLocalizations l10n, {
  String? action,
  String? message,
}) {
  recordActionFailure(error, action: action, shown: messenger != null);
  if (messenger == null) return;
  messenger.snack(message ?? error.localized(l10n));
}
