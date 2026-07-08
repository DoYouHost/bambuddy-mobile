import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Holder because the dialog result only lands after the dialog pops,
  // long after the pump helper has returned.
  bool? result;

  Future<void> pumpAndOpen(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => const WearConfirmDialog(
                icon: Icons.stop_rounded,
                title: 'Stop print?',
                subtitle: 'X1C',
                confirmColor: Color(0xFFB3261E),
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
}
