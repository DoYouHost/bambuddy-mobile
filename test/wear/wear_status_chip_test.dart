import 'package:bambuddy_mobile/wear/wear_status.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('renders the localized state label in the state color', (
    tester,
  ) async {
    await tester.pumpWidget(
      plApp(const Scaffold(body: WearStatusChip(state: WearState.printing))),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text(pl.widgetStatusPrinting));
    expect(text.style?.color, WearState.printing.color);
  });
}
