import 'package:material_ui/material_ui.dart';

/// How far back a range may start.
const _yearsBack = 5;

/// The last [_yearsBack] years up to today, opened on typed entry: the calendar's day
/// cell is a fixed 42 dp that no parameter changes, so it is one tap away behind
/// the dialog's own calendar icon instead of the first thing the user meets.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  DateTimeRange? initial,
}) {
  final now = DateTime.now();
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - _yearsBack),
    lastDate: now,
    initialDateRange: initial,
    initialEntryMode: DatePickerEntryMode.input,
  );
}
