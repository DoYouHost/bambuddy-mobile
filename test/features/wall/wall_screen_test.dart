import 'package:bambuddy_mobile/features/wall/wall_providers.dart';
import 'package:bambuddy_mobile/features/wall/wall_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _window = MethodChannel('page.codeberg.morganmlgman.bambuddy/window');

/// A landscape phone and a landscape tablet, either side of the D16 threshold.
const _phone = Size(844, 390);
const _tablet = Size(1280, 800);

void main() {
  /// Every `keepScreenOn` the screen asked for, in order.
  late List<bool> awake;

  /// Every orientation list and system UI mode handed to `SystemChrome`.
  late List<Object?> orientations;
  late List<Object?> uiModes;
  late List<Object?> overlays;

  Future<ProviderContainer> pumpDashboardWithWall(
    WidgetTester tester, {
    Size size = _phone,
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    awake = [];
    orientations = [];
    uiModes = [];
    overlays = [];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_window, (call) async {
      awake.add((call.arguments as Map)['on'] as bool);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      } else if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        uiModes.add(call.arguments);
      } else if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
        overlays.add(call.arguments);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_window, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/wall'),
              child: const Text('DASHBOARD'),
            ),
          ),
        ),
        GoRoute(path: '/wall', builder: (_, _) => const WallScreen()),
      ],
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
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
    await tester.tap(find.text('DASHBOARD'));
    await tester.pumpAndSettle();
    return container;
  }

  const landscape = [
    'DeviceOrientation.landscapeLeft',
    'DeviceOrientation.landscapeRight',
  ];

  Finder grid() =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_WallGrid');

  testWidgets('entering locks landscape, hides the bars, holds the screen on', (
    tester,
  ) async {
    await pumpDashboardWithWall(tester);

    expect(orientations, [landscape]);
    expect(uiModes, ['SystemUiMode.immersiveSticky']);
    expect(awake, [true]);
  });

  testWidgets('with the setting off the screen is left to time out', (
    tester,
  ) async {
    await pumpDashboardWithWall(
      tester,
      prefs: {'wall_keep_screen_awake': false},
    );

    expect(awake, [false]);
  });

  testWidgets('a tap on the wall itself opens nothing', (tester) async {
    await pumpDashboardWithWall(tester);

    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    expect(byLogId('wall.keep_awake'), findsNothing);
    expect(byLogId('wall.exit'), findsNothing);
  });

  group('the panel', () {
    testWidgets('starts as a rail on a phone', (tester) async {
      await pumpDashboardWithWall(tester);

      expect(byLogId('wall.panel_expand'), findsOneWidget);
      expect(byLogId('wall.panel_collapse'), findsNothing);
    });

    testWidgets('starts expanded on a tablet, and can collapse there too', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, size: _tablet);

      expect(byLogId('wall.panel_collapse'), findsOneWidget);
      await tester.tap(byLogId('wall.panel_collapse'));
      await tester.pumpAndSettle();
      expect(byLogId('wall.panel_expand'), findsOneWidget);
    });

    testWidgets('remembers the last choice over the screen width', (
      tester,
    ) async {
      final container = await pumpDashboardWithWall(tester);

      await tester.tap(byLogId('wall.panel_expand'));
      await tester.pumpAndSettle();

      expect(byLogId('wall.panel_collapse'), findsOneWidget);
      expect(
        container.read(settingsRepositoryProvider).loadWallPanelExpanded(),
        isTrue,
      );
    });

    testWidgets('a remembered collapse wins on a tablet', (tester) async {
      await pumpDashboardWithWall(
        tester,
        size: _tablet,
        prefs: {'wall_panel_expanded': false},
      );

      expect(byLogId('wall.panel_expand'), findsOneWidget);
    });

    testWidgets('ends with settings, then the expand/collapse button', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester);
      double top(String id) => tester.getTopLeft(byLogId(id)).dy;
      expect(top('wall.settings'), lessThan(top('wall.panel_expand')));

      await tester.tap(byLogId('wall.panel_expand'));
      await tester.pumpAndSettle();
      double left(String id) => tester.getTopLeft(byLogId(id)).dx;
      expect(left('wall.settings'), lessThan(left('wall.panel_collapse')));
    });

    testWidgets('keeps every button at least 48 px', (tester) async {
      await pumpDashboardWithWall(tester);
      for (final id in ['wall.settings', 'wall.panel_expand']) {
        final size = tester.getSize(byLogId(id));
        expect(size.width, greaterThanOrEqualTo(48), reason: id);
        expect(size.height, greaterThanOrEqualTo(48), reason: id);
      }
    });
  });

  group('the settings', () {
    testWidgets('open from the rail straight into the panel', (tester) async {
      await pumpDashboardWithWall(tester);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();

      expect(byLogId('wall.panel_collapse'), findsOneWidget);
      expect(byLogId('wall.keep_awake'), findsOneWidget);
    });

    testWidgets('toggle back to the farm view without resizing the grid', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, size: _tablet);
      final before = tester.getSize(grid());

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      expect(byLogId('wall.keep_awake'), findsOneWidget);
      expect(tester.getSize(grid()), before);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      expect(byLogId('wall.keep_awake'), findsNothing);
      expect(tester.getSize(grid()), before);
    });

    testWidgets('the switch releases the screen at once and is remembered', (
      tester,
    ) async {
      final container = await pumpDashboardWithWall(tester, size: _tablet);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('wall.keep_awake'));
      await tester.pump();

      expect(awake, [true, false]);
      expect(
        container.read(settingsRepositoryProvider).loadWallKeepAwake(),
        isFalse,
      );
    });

    testWidgets(
      'the exit button restores free rotation, the bars and the timeout',
      (tester) async {
        await pumpDashboardWithWall(tester, size: _tablet);

        await tester.tap(byLogId('wall.settings'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('wall.exit'));
        await tester.pumpAndSettle();

        expect(find.text('DASHBOARD'), findsOneWidget);
        expect(orientations.last, isEmpty);
        expect(
          overlays.last,
          ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
          reason: 'both bars back, the flags the activity starts with',
        );
        expect(awake.last, isFalse);
      },
    );
  });

  test('ScreenAwake on a host without the channel does nothing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await const ScreenAwake().set(true);
  });
}
