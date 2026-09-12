import 'package:bambuddy_mobile/features/dashboard/card_collapse_providers.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AppSettingsScreen()),
        GoRoute(
          path: '/settings/notifications',
          builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS')),
        ),
      ],
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return MaterialApp.router(
              locale: const Locale('pl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('the collapse switch starts off and saves what it is set to', (
    tester,
  ) async {
    final container = await pumpScreen(tester);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.text(l10n.collapsePrinterCardsTitle));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(container.read(printerCardsCollapsedByDefaultProvider), isTrue);
    expect(
      container.read(settingsRepositoryProvider).loadPrinterCardsCollapsed(),
      isTrue,
    );
  });

  testWidgets('notification settings are one entry away', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(l10n.notifEventsMenu));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS'), findsOneWidget);
  });

  testWidgets('every control is named for the log', (tester) async {
    await pumpScreen(tester);

    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.identifier),
      containsAll(<String>[
        'app_settings.collapse_printer_cards',
        'app_settings.notifications',
      ]),
    );
  });
}
