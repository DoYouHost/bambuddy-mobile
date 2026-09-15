import '../core/api/action_outcome.dart';
import '../core/api/api_exceptions.dart';
import 'app_localizations.dart';
import 'error_messages.dart';

/// One rule the server enforces and the app does not re-implement, paired with
/// what to say instead of the server's English.
///
/// [needles] must **all** appear, case-folded, which keeps a family of rules in
/// one table. Fragments rather than whole strings, so a server version that adds
/// a name or punctuation still lands.
typedef RefusalRule = (List<String> needles, String Function(AppLocalizations));

/// What to tell the user when the server refused a write.
///
/// A known refusal is localized, an unknown one quoted, and one the server did
/// not explain falls back to the code. Order in [rules] is the specificity.
///
/// Only a rule violation is ever quoted, and [AppErrorCode.badResponse] is what
/// tells one apart: every other failure carrying a `detail` already has a better
/// sentence built for it. Dio puts its own "Connecting timed out [10000ms]"
/// there, and quoting that is how a network drop mid-print would reach the user
/// in untranslated English.
String serverRefusal(
  AppLocalizations l10n,
  AppApiException error,
  List<RefusalRule> rules,
) {
  final detail = error.detail?.toLowerCase();
  if (detail == null || detail.trim().isEmpty) return error.localized(l10n);
  for (final (needles, say) in rules) {
    if (needles.every(detail.contains)) return say(l10n);
  }
  if (error.code != AppErrorCode.badResponse) return error.localized(l10n);
  return error.detail!;
}

/// [serverRefusal] for an outcome, which is how a notifier hands one back.
/// `null` when nothing failed, so a caller can `if (msg != null) snack(msg)`
/// without asking twice — the shape of `ActionOutcomeL10n.messageFor`.
String? outcomeRefusal(
  AppLocalizations l10n,
  ActionOutcome outcome,
  List<RefusalRule> rules,
) => switch (outcome) {
  ActionOk() => null,
  ActionFailed(:final error) => serverRefusal(l10n, error, rules),
};
