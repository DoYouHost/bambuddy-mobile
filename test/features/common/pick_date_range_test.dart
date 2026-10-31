import 'package:bambuddy_mobile/features/common/pick_date_range.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  Future<void> open(WidgetTester tester, {DateTimeRange? initial}) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => pickDateRange(context, initial: initial),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on typed entry, two fields and no calendar grid', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    // The calendar is one tap away behind the dialog's own icon.
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
  });

  testWidgets('the calendar icon opens the range calendar', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('15'), findsWidgets);
  });

  testWidgets('a range already chosen is typed into the fields', (
    tester,
  ) async {
    // The first of a month, on a clock of its own: the picker refuses a range
    // that starts after today, so a test that built one from the real date
    // failed on exactly this day.
    await withClock(Clock.fixed(DateTime(2026, 11, 1)), () async {
      await open(
        tester,
        initial: DateTimeRange(
          start: DateTime(2026, 10, 25),
          end: DateTime(2026, 10, 31),
        ),
      );

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.every((f) => (f.controller?.text ?? '').isNotEmpty),
        isTrue,
      );
    });
  });

  testWidgets('the picker stops at the clock\'s today, not the real one', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2024, 3, 10)), () async {
      await open(tester);

      final dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.lastDate, DateTime(2024, 3, 10));
      expect(dialog.firstDate, DateTime(2019));
    });
  });
}
