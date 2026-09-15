import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

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
  final earliest = firstDate ?? now;
  final seed = initial ?? now.add(const Duration(hours: 1));
  // `showDatePicker` asserts on an initial day before the first one, and a
  // stored time that has since passed is exactly how that happens — the queue's
  // own row, or a drying time picked before the user went back to the sliders.
  //
  // Compared by **day**, because that is what the assert compares: the picker
  // runs `dateOnly` over both before checking (`date_picker.dart`, ~227). An
  // instant comparison clamps in cases it never fires on, which is a claim
  // about the SDK that would quietly stop being true.
  final openOn = DateUtils.dateOnly(seed).isBefore(DateUtils.dateOnly(earliest))
      ? earliest
      : seed;

  final date = await showDatePicker(
    context: context,
    initialDate: openOn,
    firstDate: earliest,
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
