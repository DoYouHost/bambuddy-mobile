import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

/// Asks for a date, then a time, and combines the two into a local instant.
///
/// Two dialogs because Material has no combined picker — which is why both
/// places that schedule something (a queued print, a drying run) had written
/// out the same pair, down to the `mounted` check between the steps and the
/// hour-ahead default.
///
/// [initial] seeds both halves. With nothing to seed from it is an hour from
/// now: near enough to be a small edit, far enough to be a schedule the server
/// will accept.
///
/// [firstDate] is the earliest day the calendar offers, today by default. The
/// queue passes yesterday, because editing a job whose time has already passed
/// must not silently move it.
///
/// Returns null when either step is dismissed, and when the screen goes away
/// between them — half an answer is not one.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
}) async {
  final now = clock.now();
  final earliest = firstDate ?? now;
  final seed = initial ?? now.add(const Duration(hours: 1));
  // `showDatePicker` asserts on an initial day before the first one, and a
  // stored time that has since passed is exactly how that happens — the queue's
  // own row, or a drying time picked before the user went back to the sliders.
  //
  // Compared by **day**, the way the picker itself compares them: an instant
  // comparison would also move a seed that merely sits earlier in the first
  // allowed day, which is the queue's ordinary case (yesterday at 18:00 against
  // a `firstDate` of yesterday evening) and would silently reset the time.
  final base = DateUtils.dateOnly(seed).isBefore(DateUtils.dateOnly(earliest))
      ? earliest
      : seed;

  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: earliest,
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
