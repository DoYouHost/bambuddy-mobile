import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<SharedPreferences> pump(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    LabelPrinterInfo? info,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          labelPrinterInfoProvider.overrideWith((ref) async => info),
        ],
        child: MaterialApp(
          locale: const Locale('pl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LabelPrinterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('no server chosen says so', (tester) async {
    await pump(tester);
    expect(find.text(l10n.labelPrinterNotSet), findsOneWidget);
  });

  testWidgets('a chosen server shows what it answers', (tester) async {
    await pump(
      tester,
      stored: {'label_printer_url': 'http://10.0.0.5:8000'},
      info: const LabelPrinterInfo(
        model: 'QL-600',
        connected: true,
        labelId: '62x29',
        maxCopies: 50,
      ),
    );
    expect(find.text('http://10.0.0.5:8000'), findsWidgets);
    expect(
      find.text(l10n.labelPrinterReady('QL-600', '62x29')),
      findsOneWidget,
    );
  });

  testWidgets('warns when the loaded stock is not 62x29', (tester) async {
    await pump(
      tester,
      stored: {'label_printer_url': 'http://10.0.0.5:8000'},
      info: const LabelPrinterInfo(
        model: 'QL-600',
        connected: true,
        labelId: '54x29',
        maxCopies: 50,
      ),
    );
    expect(find.text(l10n.labelPrinterWrongStock('54x29')), findsOneWidget);
  });

  testWidgets('an address nothing answers on is not saved', (tester) async {
    final prefs = await pump(tester);
    await tester.enterText(find.byType(TextField), '10.255.255.1');
    await tester.tap(find.text(l10n.labelPrinterSave));
    await tester.pumpAndSettle();

    expect(find.text(l10n.labelPrinterNotAServer), findsOneWidget);
    expect(prefs.getString('label_printer_url'), isNull);
  });

  testWidgets('Remove forgets the server', (tester) async {
    final prefs = await pump(
      tester,
      stored: {'label_printer_url': 'http://10.0.0.5:8000'},
    );
    await tester.tap(find.text(l10n.labelPrinterRemove));
    await tester.pumpAndSettle();

    expect(prefs.getString('label_printer_url'), isNull);
    expect(find.text(l10n.labelPrinterNotSet), findsOneWidget);
  });
}
