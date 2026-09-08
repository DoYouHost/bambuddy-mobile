import '../../l10n/app_localizations.dart';

/// How long something took or has left — `1h 23min`, `45min`, `30s`.
///
/// Units sit against their number: `1 h 23 min` reads as two separate
/// measurements rather than one span. Minutes are `min`, never `m`, which is
/// metres. Exact spellings live in the `.arb` files and are pinned by tests.
String formatMinutes(AppLocalizations l10n, int minutes) {
  if (minutes < 60) return l10n.durationMinutes(minutes);
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? l10n.durationHours(hours)
      : l10n.durationHoursMinutes(hours, rest);
}

/// [formatMinutes] for a span the server reports in seconds. Below a minute it
/// stays in seconds, so a print that failed on the first layer does not read as
/// having taken no time at all.
String formatSeconds(AppLocalizations l10n, int seconds) => seconds < 60
    ? l10n.durationSeconds(seconds)
    : formatMinutes(l10n, seconds ~/ 60);

/// [formatSeconds] without the truncation, for a span the user is **setting**
/// rather than reading back.
///
/// `formatSeconds` drops the leftover seconds, which is right for "how long did
/// this print take" and wrong for a slider: at a 30-second step every other
/// stop rendered the same text, so the control looked stuck while the value
/// under it kept moving — and the number that reached the server was not the
/// one on screen.
String formatSecondsExact(AppLocalizations l10n, int seconds) {
  final rest = seconds % 60;
  if (seconds < 60) return l10n.durationSeconds(seconds);
  if (rest == 0) return formatMinutes(l10n, seconds ~/ 60);
  return '${formatMinutes(l10n, seconds ~/ 60)} ${l10n.durationSeconds(rest)}';
}
