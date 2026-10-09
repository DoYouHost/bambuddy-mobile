import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/demo/demo_label_printer.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _DemoProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() =>
      const ServerProfile(baseUrl: DemoConfig.baseUrl, authMode: AuthMode.none);
}

/// The whole label path in demo mode, through the real providers: the sheet's
/// options come from the demo's version, the file from the demo's route, and
/// the print goes to the demo's label printer.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    // Everything in the demo is timed (a network, a printer); a step at a time
    // lets each answer arrive before the next thing is asked.
    for (
      var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openOptions(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const InventoryScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverProfileProvider.overrideWith(_DemoProfile.new),
      ],
    );
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(find.byTooltip(l10n.inventoryLabelsPrintAll));
    await settle(tester);
    await tester.tap(find.textContaining('${l10n.inventoryLabelsPrint} ('));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text(l10n.inventoryLabelsBox62).hitTestable(),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(l10n.inventoryLabelsBox62));
    await pumpFor(tester, const Duration(seconds: 2));
  }

  testWidgets('the options a new server has are there', (tester) async {
    await openOptions(tester);

    // Offered only to a server that has them: the demo's version says it does.
    expect(find.text(l10n.labelFieldsTitle), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
  });

  testWidgets('a printer that is set up gets the labels, and says so', (
    tester,
  ) async {
    await openOptions(
      tester,
      stored: {'label_printer_url': demoLabelPrinterUrl},
    );

    // `/info` of the demo printer says 62 x 29, so it is the default here.
    await tester.tap(find.text(l10n.inventoryLabelsPrint));
    await pumpFor(tester, const Duration(seconds: 3));

    expect(find.text(l10n.labelPrinterSent), findsOneWidget);
  });
}
