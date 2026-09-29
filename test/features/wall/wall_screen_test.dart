import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/wall/wall_tile.dart';
import 'package:bambuddy_mobile/features/wall/wall_camera.dart';
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

/// The dashboard state the wall reads, fixed: no poll, no server.
class _FixedDashboard extends DashboardNotifier {
  _FixedDashboard(this._fixed);

  final DashboardState _fixed;

  @override
  DashboardState build() => _fixed;

  @override
  Future<void> refresh() async {}
}

/// Live statuses, fixed: what the socket would have delivered.
class _FixedStatuses extends PrinterStatusesNotifier {
  _FixedStatuses(this._fixed);

  final Map<int, PrinterStatus> _fixed;

  @override
  Map<int, PrinterStatus> build() => _fixed;
}

/// A fixed queue that counts how often the wall asked for it again.
class _CountingQueue extends QueueNotifier {
  _CountingQueue(this._items);

  final List<QueueItem> _items;

  /// Every request for the queue: the first load and each refresh.
  static int refreshes = 0;

  @override
  Future<List<QueueItem>> build() async {
    refreshes++;
    return _items;
  }

  @override
  Future<void> refresh() async => refreshes++;
}

/// The demo's five printers, idle and connected.
final _farm = [
  for (final (i, name) in ['X1C-01', 'X1C-02', 'P1S', 'A1 mini', 'H2D'].indexed)
    PrinterWithStatus(
      printer: Printer(id: i + 1, name: name),
      status: PrinterStatus(id: i + 1, connected: true, state: 'IDLE'),
    ),
];

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

  /// The harness's router, for the tests that navigate from outside the wall.
  late GoRouter router;

  Future<ProviderContainer> pumpDashboardWithWall(
    WidgetTester tester, {
    Size size = _phone,
    Map<String, Object> prefs = const {},
    List<PrinterWithStatus>? printers,
    Map<int, PrinterStatus>? live,
    List<QueueItem> queue = const [],
    Override? profile,
  }) async {
    _CountingQueue.refreshes = 0;
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
    router = GoRouter(
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
        GoRoute(
          path: '/setup',
          builder: (_, _) => const Scaffold(body: Text('SETUP')),
        ),
      ],
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          dashboardProvider.overrideWith(
            () => _FixedDashboard(DashboardState(printers: printers ?? _farm)),
          ),
          queueProvider.overrideWith(() => _CountingQueue(queue)),
          ?profile,
          cameraTokenProvider.overrideWith((ref) async => 'tok'),
          if (live == null)
            inertStatusesOverride
          else
            printerStatusesProvider.overrideWith(() => _FixedStatuses(live)),
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

  group('the grid', () {
    testWidgets('lays the demo farm out in three columns on a phone', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester);

      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('X1C-01'), top('P1S'), reason: 'first row: three tiles');
      expect(top('A1 mini'), greaterThan(top('X1C-01')));
    });

    testWidgets('draws the live status, not the roster\'s minute-old one', (
      tester,
    ) async {
      await pumpDashboardWithWall(
        tester,
        live: {
          1: const PrinterStatus(
            id: 1,
            connected: true,
            state: 'RUNNING',
            progress: 64,
            remainingTime: 72,
          ),
        },
      );

      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('64%'), findsOneWidget);
    });

    testWidgets('puts each printer\'s camera behind its status', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, profile: fakeServerProfileOverride());

      expect(byLogId('wall.tile'), findsNWidgets(5));
      expect(find.byType(WallCamera), findsNWidgets(5));
    });

    testWidgets('keeps the demo status-only: it serves no camera', (
      tester,
    ) async {
      await pumpDashboardWithWall(
        tester,
        profile: serverProfileOverride(
          const ServerProfile(
            baseUrl: DemoConfig.baseUrl,
            authMode: AuthMode.none,
          ),
        ),
      );

      expect(byLogId('wall.tile'), findsNothing);
      expect(find.text('X1C-01'), findsOneWidget);
    });

    testWidgets('says so when the server has no printers', (tester) async {
      await pumpDashboardWithWall(tester, printers: const []);

      expect(find.textContaining('Brak drukarek'), findsOneWidget);
    });

    testWidgets('scrolls a farm too big to fit rather than squeezing it', (
      tester,
    ) async {
      final big = [
        for (var i = 1; i <= 24; i++)
          PrinterWithStatus(
            printer: Printer(id: i, name: 'P$i'),
            status: PrinterStatus(id: i, connected: true, state: 'IDLE'),
          ),
      ];
      await pumpDashboardWithWall(tester, printers: big);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(WallTile).first).height,
        greaterThanOrEqualTo(120),
      );
      expect(find.text('P24'), findsNothing, reason: 'below the fold');

      await tester.scrollUntilVisible(
        find.text('P24'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('P24'), findsOneWidget);
    });
  });

  group('the farm view', () {
    PrinterWithStatus faulty(int id, String name, String code, String text) =>
        PrinterWithStatus(
          printer: Printer(id: id, name: name),
          status: PrinterStatus(
            id: id,
            connected: true,
            state: 'IDLE',
            hmsErrors: [HmsError(code: code, message: text)],
          ),
        );

    testWidgets('lists faults most severe first, each naming its printer', (
      tester,
    ) async {
      await pumpDashboardWithWall(
        tester,
        size: _tablet,
        printers: [
          // The fatal fault is on the printer whose name sorts last, so only
          // the level can put it first.
          faulty(1, 'A1 mini', '0x30001', 'Nozzle clog suspected'),
          faulty(2, 'X1C-01', '0x10001', 'Heatbed heating failed'),
        ],
      );

      final panel = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_WallFarm',
      );
      double top(String text) => tester
          .getTopLeft(find.descendant(of: panel, matching: find.text(text)))
          .dy;
      expect(
        top('Heatbed heating failed'),
        lessThan(top('Nozzle clog suspected')),
      );
      for (final name in ['A1 mini', 'X1C-01']) {
        expect(
          find.descendant(of: panel, matching: find.text(name)),
          findsOneWidget,
          reason: name,
        );
      }
    });

    testWidgets('lists the queue with its target and waiting reason', (
      tester,
    ) async {
      await pumpDashboardWithWall(
        tester,
        size: _tablet,
        queue: const [
          QueueItem(
            id: 7,
            position: 1,
            status: 'pending',
            archiveName: 'Camera_mount_v3.3mf',
            printerName: 'X1C-01',
            waitingReason: 'Waiting on Enclosure Door',
          ),
          QueueItem(
            id: 8,
            position: 2,
            status: 'pending',
            libraryFileName: 'Cable_clip.3mf',
            targetModel: 'X1C',
          ),
        ],
      );

      expect(find.text('Camera_mount_v3.3mf'), findsOneWidget);
      expect(find.text('Waiting on Enclosure Door'), findsOneWidget);
      expect(find.text('Cable_clip.3mf'), findsOneWidget);
      expect(find.text('Dowolna X1C'), findsOneWidget);
    });

    testWidgets('says quietly that there are no faults and no queue', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, size: _tablet);

      expect(find.text('Brak aktywnych błędów'), findsOneWidget);
      expect(find.text('Kolejka jest pusta'), findsOneWidget);
    });

    testWidgets('the rail counts faults and queued jobs', (tester) async {
      await pumpDashboardWithWall(
        tester,
        printers: [faulty(1, 'X1C-01', '0x10001', 'Heatbed heating failed')],
        queue: const [
          QueueItem(id: 1, position: 1, status: 'pending'),
          QueueItem(id: 2, position: 2, status: 'pending'),
        ],
      );

      expect(find.bySemanticsLabel('1 błąd, 2 w kolejce'), findsOneWidget);
    });

    testWidgets('asks for the queue on entry, every 30 s, and not after', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, size: _tablet);
      expect(_CountingQueue.refreshes, 1);

      await tester.pump(WallScreen.queuePoll);
      await tester.pump(WallScreen.queuePoll);
      expect(_CountingQueue.refreshes, 3);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('wall.exit'));
      await tester.pumpAndSettle();
      await tester.pump(WallScreen.queuePoll);
      expect(_CountingQueue.refreshes, 3);
    });

    testWidgets('stops asking while the app is in the background', (
      tester,
    ) async {
      await pumpDashboardWithWall(tester, size: _tablet);
      expect(_CountingQueue.refreshes, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(WallScreen.queuePoll * 3);
      expect(_CountingQueue.refreshes, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_CountingQueue.refreshes, 2, reason: 'back: refresh at once');
      await tester.pump(WallScreen.queuePoll);
      expect(_CountingQueue.refreshes, 3);
    });
  });

  group('printers kept off the wall', () {
    testWidgets('are not tiled, and the settings can show them again', (
      tester,
    ) async {
      final container = await pumpDashboardWithWall(
        tester,
        size: _tablet,
        prefs: {
          'wall_hidden_printer_ids': ['2'],
        },
      );
      Finder tile(String name) =>
          find.descendant(of: find.byType(WallTile), matching: find.text(name));
      expect(tile('X1C-02'), findsNothing);
      expect(tile('X1C-01'), findsOneWidget);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'X1C-02'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'P1S'));
      await tester.pumpAndSettle();

      expect(tile('X1C-02'), findsOneWidget);
      expect(tile('P1S'), findsNothing, reason: 'the second tick kept');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'P1S'));
      await tester.pumpAndSettle();
      expect(
        container.read(settingsRepositoryProvider).loadWallHiddenPrinters(),
        isEmpty,
      );
    });

    testWidgets('bring no faults into the panel', (tester) async {
      await pumpDashboardWithWall(
        tester,
        size: _tablet,
        printers: [
          PrinterWithStatus(
            printer: const Printer(id: 1, name: 'X1C-01'),
            status: const PrinterStatus(
              id: 1,
              connected: true,
              state: 'IDLE',
              hmsErrors: [
                HmsError(code: '0x10001', message: 'Heatbed heating failed'),
              ],
            ),
          ),
        ],
        prefs: {
          'wall_hidden_printer_ids': ['1'],
        },
      );

      expect(find.text('Heatbed heating failed'), findsNothing);
      expect(find.text('Brak aktywnych błędów'), findsOneWidget);
    });

    testWidgets('all hidden says so rather than "no printers"', (tester) async {
      await pumpDashboardWithWall(
        tester,
        prefs: {
          'wall_hidden_printer_ids': ['1', '2', '3', '4', '5'],
        },
      );

      expect(find.textContaining('ukryte'), findsOneWidget);
      expect(find.textContaining('Brak drukarek'), findsNothing);
    });
  });

  testWidgets('with the live camera off, tiles show status only', (
    tester,
  ) async {
    await pumpDashboardWithWall(
      tester,
      profile: fakeServerProfileOverride(),
      prefs: {'wall_live_camera': false},
    );

    expect(find.byType(WallCamera), findsNothing);
    expect(byLogId('wall.tile'), findsNothing);
    expect(find.text('X1C-01'), findsOneWidget);
    expect(find.text('IDLE'), findsNWidgets(5));
  });

  testWidgets('holds the burn-in clock while the app is in the background', (
    tester,
  ) async {
    await pumpDashboardWithWall(tester);
    final at = tester.getTopLeft(grid());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(WallScreen.burnInStep * 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(tester.getTopLeft(grid()), at);
  });

  testWidgets('steps the wall a few pixels on the burn-in clock, same size', (
    tester,
  ) async {
    await pumpDashboardWithWall(tester);
    final at = tester.getTopLeft(grid());
    final size = tester.getSize(grid());

    await tester.pump(WallScreen.burnInStep);

    expect(tester.getTopLeft(grid()), at + WallScreen.burnInOffsets[1]);
    expect(tester.getSize(grid()), size);
  });

  // The dashboard's side (authExpired → go('/setup')) is its own test; this
  // is the wall's: a route change that replaces it still restores everything.
  testWidgets('a go to /setup from under the wall restores what it took', (
    tester,
  ) async {
    await pumpDashboardWithWall(tester);

    // What the dashboard under the wall does when the session expires.
    router.go('/setup');
    await tester.pumpAndSettle();

    expect(find.text('SETUP'), findsOneWidget);
    expect(orientations.last, isEmpty);
    expect(overlays.last, ['SystemUiOverlay.top', 'SystemUiOverlay.bottom']);
    expect(awake.last, isFalse);
  });

  testWidgets('a tap on the wall itself opens nothing', (tester) async {
    await pumpDashboardWithWall(tester);

    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsNothing, reason: 'still on the wall');
    expect(byLogId('wall.panel_expand'), findsOneWidget);
    expect(byLogId('wall.panel_collapse'), findsNothing);
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

    testWidgets('a remembered expand wins on a phone', (tester) async {
      await pumpDashboardWithWall(tester, prefs: {'wall_panel_expanded': true});

      expect(byLogId('wall.panel_collapse'), findsOneWidget);
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
      void atLeast48(String id) {
        final size = tester.getSize(byLogId(id));
        expect(size.width, greaterThanOrEqualTo(48), reason: id);
        expect(size.height, greaterThanOrEqualTo(48), reason: id);
      }

      atLeast48('wall.settings');
      atLeast48('wall.panel_expand');
      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      atLeast48('wall.settings');
      atLeast48('wall.panel_collapse');
      atLeast48('wall.exit');
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

    testWidgets('closed again, they give the rail back without saving it', (
      tester,
    ) async {
      final container = await pumpDashboardWithWall(tester);

      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('wall.settings'));
      await tester.pumpAndSettle();

      expect(byLogId('wall.panel_expand'), findsOneWidget);
      expect(
        container.read(settingsRepositoryProvider).loadWallPanelExpanded(),
        isNull,
      );
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
