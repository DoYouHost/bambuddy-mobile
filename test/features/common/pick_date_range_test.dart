import 'package:bambuddy_mobile/features/common/pick_date_range.dart';
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
    final now = DateTime.now();
    await open(
      tester,
      initial: DateTimeRange(
        start: DateTime(now.year, now.month, 2),
        end: DateTime(now.year, now.month, 9),
      ),
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.every((f) => (f.controller?.text ?? '').isNotEmpty), isTrue);
  });
}
