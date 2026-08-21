import 'package:bambuddy_mobile/features/common/dash_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScaffoldMessengerState messenger;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
  }

  testWidgets('says the sentence it was given', (tester) async {
    await pumpHost(tester);

    messenger.snack('saved');
    await tester.pump();

    expect(find.widgetWithText(SnackBar, 'saved'), findsOneWidget);
  });

  testWidgets('a second snack waits its turn by default', (tester) async {
    await pumpHost(tester);

    messenger.snack('first');
    messenger.snack('second');
    await tester.pump();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });

  testWidgets('clearQueue lets the newest answer win', (tester) async {
    await pumpHost(tester);

    messenger.snack('first');
    await tester.pump();
    messenger.snack('second', clearQueue: true);
    await tester.pumpAndSettle();

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('an action rides along without pinning the snack open', (
    tester,
  ) async {
    await pumpHost(tester);

    messenger.snack(
      'downloaded',
      action: SnackBarAction(label: 'open', onPressed: () {}),
      persist: false,
      duration: const Duration(seconds: 1),
    );
    await tester.pump();

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.action, isNotNull);
    // Material would otherwise keep a snack with an action until dismissed.
    expect(bar.persist, isFalse);
    expect(bar.duration, const Duration(seconds: 1));

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('without a duration it lasts as long as Material intends', (
    tester,
  ) async {
    await pumpHost(tester);

    messenger.snack('saved');
    await tester.pump();

    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 4),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
