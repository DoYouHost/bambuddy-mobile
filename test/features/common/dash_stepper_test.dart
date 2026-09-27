import 'package:bambuddy_mobile/features/common/dash_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    required int value,
    bool enabled = true,
  }) async {
    final changes = <int>[];
    await pumpPhone(
      tester,
      Scaffold(
        body: DashStepper(
          value: value,
          min: 1,
          max: 3,
          onChanged: enabled ? changes.add : null,
          lessTooltip: 'less',
          moreTooltip: 'more',
          lessId: 't.less',
          moreId: 't.more',
        ),
      ),
    );
    return changes;
  }

  IconButton button(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip),
      );

  testWidgets('steps by one and names each button', (tester) async {
    final changes = await pump(tester, value: 2);

    await tester.tap(byLogId('t.less'));
    await tester.tap(byLogId('t.more'));

    expect(changes, [1, 3]);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('each end of the range disables its own button', (tester) async {
    await pump(tester, value: 1);
    expect(button(tester, 'less').onPressed, isNull);
    expect(button(tester, 'more').onPressed, isNotNull);

    await pump(tester, value: 3);
    expect(button(tester, 'less').onPressed, isNotNull);
    expect(button(tester, 'more').onPressed, isNull);
  });

  testWidgets('no callback disables both', (tester) async {
    await pump(tester, value: 2, enabled: false);

    expect(button(tester, 'less').onPressed, isNull);
    expect(button(tester, 'more').onPressed, isNull);
  });
}
