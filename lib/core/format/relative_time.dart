import '../../l10n/app_localizations.dart';
import 'datetime_format.dart';

/// How long ago [at] was, or how soon it is — `5 min ago`, `in 3 h` — and the
/// plain date and time once it is a week or more away (`formatRelativeTime`,
/// web `utils/date.ts`). `-` when there is no time to tell.
String relativeTime(
  AppLocalizations l10n,
  DateTimeFormats formats,
  DateTime? at, {
  required DateTime now,
}) {
  if (at == null) return '-';
  final diff = at.difference(now);
  final past = diff.isNegative;
  final span = diff.abs();
  final (minutes, hours, days) = (span.inMinutes, span.inHours, span.inDays);
  if (minutes < 1) return past ? l10n.timeJustNow : l10n.timeNow;
  if (hours < 1) {
    return past ? l10n.timeMinutesAgo(minutes) : l10n.timeInMinutes(minutes);
  }
  if (days < 1) {
    return past ? l10n.timeHoursAgo(hours) : l10n.timeInHours(hours);
  }
  if (days < 7) return past ? l10n.timeDaysAgo(days) : l10n.timeInDays(days);
  return formats.dateTime(at);
}
