import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/dashboard/card_collapse_providers.dart';
import 'package:bambuddy_mobile/features/settings/demo_printers_provider.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...extra,
        ],
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
      identifiersIn(tester),
      containsAll(<String>[
        'app_settings.collapse_printer_cards',
        'app_settings.notifications',
      ]),
    );
  });

  group('the demo printer count', () {
    // The demo prints on one machine, and every screen that behaves differently
    // with several had no way to be looked at. The row is demo-only: on a real
    // server the number of printing machines is the server's business.
    Override demoProfile() => serverProfileOverride(
      const ServerProfile(baseUrl: DemoConfig.baseUrl, authMode: AuthMode.none),
    );

    tearDown(() => DemoBackend.printingPrinters = 1);

    testWidgets('is not offered against a real server', (tester) async {
      await pumpScreen(tester, extra: [fakeServerProfileOverride()]);

      expect(
        identifiersIn(tester),
        isNot(contains('app_settings.demo_printing_count')),
      );
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('sets the demo, the preference and the service isolate', (
      tester,
    ) async {
      final container = await pumpScreen(tester, extra: [demoProfile()]);

      expect(
        identifiersIn(tester),
        contains('app_settings.demo_printing_count'),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));

      // Dragging is a preview: the demo follows along so the dashboard behind
      // the screen moves, but a value per frame must not be a flash write and
      // an IPC message each.
      slider.onChanged!(3);
      await tester.pumpAndSettle();

      expect(container.read(demoPrintingCountProvider), 3);
      expect(DemoBackend.printingPrinters, 3);
      expect(
        container.read(settingsRepositoryProvider).loadDemoPrintingCount(),
        1,
        reason: 'nothing is kept until the drag ends',
      );

      // Letting go is the decision: kept, and told to the service isolate.
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(3);
      await tester.pumpAndSettle();

      expect(
        container.read(settingsRepositoryProvider).loadDemoPrintingCount(),
        3,
      );
    });
  });
}
