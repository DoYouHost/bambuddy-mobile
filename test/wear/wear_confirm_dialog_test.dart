import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // Holder because the dialog result only lands after the dialog pops,
  // long after the pump helper has returned.
  bool? result;

  /// Opens the dialog on a real watch face — the small one by default, since a
  /// confirmation is the screen with the least room to spare.
  Future<void> pumpAndOpen(WidgetTester tester,
      {Size face = wearFaceSmall, String title = 'Stop print?'}) async {
    result = null;
    tester.view.physicalSize = face;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => WearConfirmDialog(
                icon: Icons.stop_rounded,
                title: title,
                subtitle: 'X1C',
                confirmColor: const Color(0xFFB3261E),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, subtitle and both round buttons', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Stop print?'), findsOneWidget);
    expect(find.text('X1C'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('confirm pops true', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel pops false', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('a long question does not push the answer off the face',
      (tester) async {
    // Both regressions the 192 dp emulator found: a fixed-width button row
    // overflowing the narrow content by 11 px, and the question growing until
    // the buttons needed a scroll. The row is pinned and sized from the width
    // it is given, so the taps below land without anyone scrolling first.
    await pumpAndOpen(tester,
        title: 'Change the server this watch talks to, dropping every secret?');

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  Size confirmButton(WidgetTester tester) => tester
      .getSize(find.widgetWithIcon(IconButton, Icons.check_rounded).first);

  testWidgets('a big face gets the full-size buttons', (tester) async {
    await pumpAndOpen(tester, face: wearFaceLarge);

    // 225 dp of face leaves this row 133 dp, which is more than the pair wants.
    expect(confirmButton(tester).width, 52.0);
  });

  testWidgets('a small face shrinks them instead of overflowing',
      (tester) async {
    await pumpAndOpen(tester);

    // 192 dp of face leaves 113 dp: the pair gives up 3 dp each rather than 11
    // px of stripes, and stays above the 48 dp tap target.
    final width = confirmButton(tester).width;
    expect(width, lessThan(52.0));
    expect(width, greaterThanOrEqualTo(48.0));
  });
}
