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

void main() {
  /// Every `keepScreenOn` the screen asked for, in order.
  late List<bool> awake;

  /// Every orientation list and system UI mode handed to `SystemChrome`.
  late List<Object?> orientations;
  late List<Object?> uiModes;

  Future<ProviderContainer> pumpDashboardWithWall(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    awake = [];
    orientations = [];
    uiModes = [];
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

  testWidgets('leaving restores free rotation, the bars and the timeout', (
    tester,
  ) async {
    await pumpDashboardWithWall(tester);

    await tester.tap(byLogId('wall.surface'));
    await tester.pump();
    await tester.tap(byLogId('wall.exit'));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(orientations.last, isEmpty);
    expect(uiModes.last, 'SystemUiMode.edgeToEdge');
    expect(awake.last, isFalse);
  });

  testWidgets('the switch releases the screen at once and is remembered', (
    tester,
  ) async {
    final container = await pumpDashboardWithWall(tester);

    await tester.tap(byLogId('wall.surface'));
    await tester.pump();
    await tester.tap(byLogId('wall.keep_awake'));
    await tester.pump();

    expect(awake, [true, false]);
    expect(
      container.read(settingsRepositoryProvider).loadWallKeepAwake(),
      isFalse,
    );
  });

  testWidgets('the controls hide again on their own', (tester) async {
    await pumpDashboardWithWall(tester);

    await tester.tap(byLogId('wall.surface'));
    await tester.pump();
    expect(byLogId('wall.exit'), findsOneWidget);

    await tester.pump(WallScreen.controlsTimeout);
    expect(byLogId('wall.exit'), findsNothing);
  });

  test('ScreenAwake on a host without the channel does nothing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await const ScreenAwake().set(true);
  });
}
