import '../core/api/action_outcome.dart';
import '../core/api/api_exceptions.dart';
import 'app_localizations.dart';
import 'error_messages.dart';

/// One rule the server enforces and the app deliberately does not re-implement,
/// paired with what to say instead of the server's English.
///
/// [needles] must **all** appear in the refusal, case-folded, which is how a
/// family of related rules stays one table: "last admin" on its own and "last
/// admin" together with "delete" are two rows, the more specific one first.
/// Matching on fragments rather than whole strings is deliberate — a server
/// version that adds a name, a filename or punctuation still lands.
typedef RefusalRule = (List<String> needles, String Function(AppLocalizations));

/// What to tell the user when the server refused a write.
///
/// The status alone cannot explain a rule: a 400 localizes to "server returned
/// error 400", which is the whole of what one bug reporter's screen told them
/// about a queue item that had no way out. So the ladder is always the same —
/// a known refusal is localized, an unknown one is quoted exactly as the server
/// wrote it (a phrasing we do not know yet still beats a bare code), and a
/// refusal with nothing written falls back to the code's own wording.
///
/// Three features each built that ladder for themselves — accounts, the slicer,
/// the queue — differing only in [rules].
String serverRefusal(
  AppLocalizations l10n,
  AppApiException error,
  List<RefusalRule> rules,
) {
  final detail = error.detail;
  if (detail == null || detail.trim().isEmpty) return error.localized(l10n);
  return localizedRefusal(l10n, detail, rules) ?? detail;
}

/// [serverRefusal] for a caller that holds the server's words but not the
/// exception they arrived in — the watch's relay forwards the `detail` alone.
/// `null` when no rule matches, so the caller decides what to do with the
/// original.
String? localizedRefusal(
  AppLocalizations l10n,
  String detail,
  List<RefusalRule> rules,
) {
  final d = detail.toLowerCase();
  for (final (needles, say) in rules) {
    if (needles.every(d.contains)) return say(l10n);
  }
  return null;
}

/// [serverRefusal] for an outcome, which is how a notifier hands one back.
/// `null` when nothing failed, so a caller can `if (msg != null) snack(msg)`
/// without asking twice — the same shape as `ActionOutcomeL10n.messageFor`.
String? outcomeRefusal(
  AppLocalizations l10n,
  ActionOutcome outcome,
  List<RefusalRule> rules,
) =>
    switch (outcome) {
      ActionOk() => null,
      ActionFailed(:final error) => serverRefusal(l10n, error, rules),
    };
