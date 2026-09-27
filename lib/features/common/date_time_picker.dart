import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

/// Asks for a calendar day, opening on [initial] — or, when that is outside
/// [firstDate]..[lastDate], on the nearest end of the range.
///
/// A stored date the range no longer covers is how the picker's assert gets
/// hit: an expired API key, a due date set years ago or years ahead.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDatePicker(
  context: context,
  initialDate: _openingDay(initial, firstDate, lastDate),
  firstDate: firstDate,
  lastDate: lastDate,
);

/// [seed] clamped into [first]..[last] by **day**, because that is what the
/// picker's assert compares: it runs `dateOnly` over all three before checking
/// (`date_picker.dart`, ~227). An instant comparison would clamp in cases the
/// assert never fires on.
DateTime _openingDay(DateTime seed, DateTime first, DateTime last) {
  final day = DateUtils.dateOnly(seed);
  if (day.isBefore(DateUtils.dateOnly(first))) return first;
  if (day.isAfter(DateUtils.dateOnly(last))) return last;
  return seed;
}

/// Asks for a date, then a time, and combines the two into a local instant.
///
/// Two dialogs because Material has no combined picker.
///
/// [initial] seeds both halves; with nothing to seed from it is an hour from
/// now. [firstDate] is the earliest day the calendar offers, today by default —
/// the queue passes yesterday, because editing a job whose time has already
/// passed must not silently move it.
///
/// Returns null when either step is dismissed, and when the screen goes away
/// between them — half an answer is not one.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
}) async {
  final now = clock.now();
  final seed = initial ?? now.add(const Duration(hours: 1));
  // A stored time that has since passed is the usual way past the range — the
  // queue's own row, or a drying time picked before the user went back to the
  // sliders.
  final date = await pickDate(
    context,
    initial: seed,
    firstDate: firstDate ?? now,
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;

  // From [seed], not from the clamped day: seeding the clock from the clamp
  // would throw away the hour the user chose — a job set for 06:00 last week
  // comes back to be re-dated, not re-timed.
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
