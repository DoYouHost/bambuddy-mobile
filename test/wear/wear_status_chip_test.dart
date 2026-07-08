import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/wear/wear_status.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the localized state label in the state color',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: WearStatusChip(state: WearState.printing)),
    ));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('Printing'));
    expect(text.style?.color, WearState.printing.color);
  });
}
