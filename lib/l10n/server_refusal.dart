import '../core/api/action_outcome.dart';
import '../core/api/api_exceptions.dart';
import 'app_localizations.dart';
import 'error_messages.dart';

/// One rule the server enforces and the app does not re-implement, paired with
/// what to say instead of the server's English.
///
/// [needles] must **all** appear, case-folded, which is what keeps a family of
/// rules in one table: "last admin" alone and "last admin" with "delete" are
/// two rows. Fragments rather than whole strings, so a version that adds a
/// name or punctuation still lands.
typedef RefusalRule = (List<String> needles, String Function(AppLocalizations));

/// What to tell the user when the server refused a write.
///
/// A known refusal is localized, an unknown one quoted, and one the server did
/// not explain falls back to the code — a 400 on its own only ever reads as
/// "server returned error 400". Order in [rules] is the specificity: first
/// match wins.
///
/// Only a rule violation is ever quoted, and [AppErrorCode.badResponse] is what
/// tells one apart: [mapDioExceptionKeepingDetail] keeps a `detail` for the 400
/// and 422 alone, and every other failure that carries one already has a better
/// sentence built for it. A lost connection puts Dio's own
/// "Connecting timed out [10000ms]" in `detail`, and a 403 needs the
/// "Not allowed:" frame plus the deactivated-owner case that
/// `AppApiExceptionL10n` handles — quoting either raw is how a network drop
/// while starting a print would reach the user in untranslated English.
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
