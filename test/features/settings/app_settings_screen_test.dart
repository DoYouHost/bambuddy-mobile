import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/appearance_providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/dashboard/card_collapse_providers.dart';
import 'package:bambuddy_mobile/features/settings/demo_printers_provider.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:bambuddy_mobile/features/wall/wall_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    List<Override> extra = const [],
    Map<String, Object> stored = const {},
  }) async {
    // Tall enough for the whole list: a ListView builds only what is on
    // screen, and the appearance card pushed the last rows below a phone's
    // fold.
    useLogicalWindow(tester, const Size(411, 2000));
    SharedPreferences.setMockInitialValues(stored);
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
            return plRouterApp(router);
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
    Switch collapseSwitch() => tester.widget<Switch>(
      find.descendant(
        of: byLogId('app_settings.collapse_printer_cards'),
        matching: find.byType(Switch),
      ),
    );

    expect(collapseSwitch().value, isFalse);

    await tester.tap(find.text(pl.collapsePrinterCardsTitle));
    await tester.pumpAndSettle();

    expect(collapseSwitch().value, isTrue);
    expect(container.read(printerCardsCollapsedByDefaultProvider), isTrue);
    expect(
      container.read(settingsRepositoryProvider).loadPrinterCardsCollapsed(),
      isTrue,
    );
  });

  testWidgets(
    'the wall keep-awake switch starts on and saves what it is set to',
    (tester) async {
      final container = await pumpScreen(tester);
      Switch wallSwitch() => tester.widget<Switch>(
        find.descendant(
          of: byLogId('app_settings.wall_keep_awake'),
          matching: find.byType(Switch),
        ),
      );

      expect(wallSwitch().value, isTrue);

      await tester.tap(find.text(pl.wallKeepAwakeTitle));
      await tester.pumpAndSettle();

      expect(wallSwitch().value, isFalse);
      expect(container.read(wallKeepAwakeProvider), isFalse);
      expect(
        container.read(settingsRepositoryProvider).loadWallKeepAwake(),
        isFalse,
      );
    },
  );

  testWidgets('notification settings are one entry away', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(pl.notifEventsMenu));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS'), findsOneWidget);
  });

  testWidgets('every control is named for the log', (tester) async {
    await pumpScreen(tester);

    expect(
      identifiersIn(tester),
      containsAll(<String>[
        'app_settings.accent',
        'app_settings.theme_mode',
        'app_settings.collapse_printer_cards',
        'app_settings.wall_keep_awake',
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
        DemoBackend.defaultPrintingPrinters,
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

  group('appearance', () {
    SystemSchemes schemesOf(Color seed) => (
      light: ColorScheme.fromSeed(seedColor: seed),
      dark: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
    );

    Future<void> pick(WidgetTester tester, String field, String row) async {
      await tester.tap(byLogId(field));
      await tester.pumpAndSettle();
      await tester.tap(byLogId(row).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a picked accent is stored and paints the brand', (
      tester,
    ) async {
      final container = await pumpScreen(tester);
      expect(container.read(appBrandProvider), bambuddyBrand);

      await pick(tester, 'app_settings.accent', 'app_settings.accent.blue');

      expect(container.read(appearanceProvider).accent, AccentSource.blue);
      expect(container.read(appBrandProvider), isNot(bambuddyBrand));
      expect(
        container.read(settingsRepositoryProvider).loadAppearancePrefs().accent,
        AccentSource.blue,
      );
    });

    testWidgets('a picked theme mode is stored', (tester) async {
      final container = await pumpScreen(tester);

      await pick(
        tester,
        'app_settings.theme_mode',
        'app_settings.theme_mode.dark',
      );

      expect(container.read(appearanceProvider).mode, ThemeMode.dark);
      expect(
        container.read(settingsRepositoryProvider).loadAppearancePrefs().mode,
        ThemeMode.dark,
      );
    });

    testWidgets('a stored choice is what the fields open with', (tester) async {
      await pumpScreen(
        tester,
        stored: {'appearance_prefs': '{"accent":"pink","mode":"light"}'},
      );

      expect(find.text(pl.appearanceAccentPink), findsOneWidget);
      expect(find.text(pl.appearanceModeLight), findsOneWidget);
    });

    testWidgets('System is offered only where there is a palette', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byLogId('app_settings.accent'));
      await tester.pumpAndSettle();
      expect(byLogId('app_settings.accent.system'), findsNothing);
      expect(byLogId('app_settings.accent.graphite'), findsWidgets);
    });

    testWidgets('with a palette, System is offered', (tester) async {
      await pumpScreen(
        tester,
        extra: [
          initialSystemSchemesProvider.overrideWithValue(
            schemesOf(const Color(0xFF2E7DD7)),
          ),
        ],
      );
      await tester.tap(byLogId('app_settings.accent'));
      await tester.pumpAndSettle();
      expect(byLogId('app_settings.accent.system'), findsWidgets);
    });

    // A backup restored onto an older phone: the stored choice must still
    // show, not leave the field blank.
    testWidgets('a stored System stays listed without a palette', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        stored: {'appearance_prefs': '{"accent":"system","mode":"system"}'},
      );
      expect(find.text(pl.appearanceAccentSystem), findsOneWidget);
    });

    testWidgets('picking what is already picked writes nothing', (
      tester,
    ) async {
      final container = await pumpScreen(tester);
      final prefs = container.read(sharedPreferencesProvider);

      await pick(tester, 'app_settings.accent', 'app_settings.accent.bambuddy');
      expect(prefs.getString('appearance_prefs'), isNull);

      await pick(tester, 'app_settings.accent', 'app_settings.accent.orange');
      await pick(tester, 'app_settings.accent', 'app_settings.accent.orange');
      expect(
        container.read(settingsRepositoryProvider).loadAppearancePrefs().accent,
        AccentSource.orange,
      );
    });
  });
}
