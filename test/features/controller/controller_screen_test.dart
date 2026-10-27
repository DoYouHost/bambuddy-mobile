import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_picker.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// A landscape phone.
const _phone = Size(844, 390);

PrinterWithStatus _printer(
  int id,
  String name, {
  String? model,
  bool connected = true,
  String state = 'IDLE',
}) => PrinterWithStatus(
  printer: Printer(id: id, name: name, model: model),
  status: PrinterStatus(id: id, connected: connected, state: state),
);

void main() {
  /// Every `keepScreenOn` the screen asked for, in order.
  late List<bool> awake;
  late List<Object?> orientations;
  late List<Object?> uiModes;
  late List<Object?> overlays;
  late GoRouter router;

  Future<void> pumpController(
    WidgetTester tester, {
    List<PrinterWithStatus>? printers,
    Map<String, Object> prefs = const {},
  }) async {
    useLogicalWindow(tester, _phone);
    awake = [];
    orientations = [];
    uiModes = [];
    overlays = [];
    mockImmersiveChannels(
      tester,
      onWindow: (call) => awake.add((call.arguments as Map)['on'] as bool),
      onPlatform: (call) {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
        } else if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          uiModes.add(call.arguments);
        } else if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
          overlays.add(call.arguments);
        }
      },
    );

    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => openController(context, ref),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/controller/:id',
          builder: (_, state) => ControllerScreen(
            printerId: int.tryParse(state.pathParameters['id']!) ?? -1,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          fixedDashboardOverride(
            DashboardState(
              printers: printers ?? [_printer(1, 'X1C Warsztat', model: 'X1C')],
            ),
          ),
          inertStatusesOverride,
          inertSmartPlugsOverride,
        ],
        child: plRouterApp(router),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await settle(tester);
  }

  testWidgets('with one printer it opens at once, on that printer', (
    tester,
  ) async {
    await pumpController(tester);

    await open(tester);

    expect(find.byType(ControllerScreen), findsOneWidget);
    expect(find.text('X1C Warsztat'), findsOneWidget);
    expect(find.text('X1C'), findsOneWidget);
    expect(find.text(pl.controllerTabOverview), findsOneWidget);
  });

  testWidgets('a camera cutout at the side does not push the content in', (
    tester,
  ) async {
    await pumpController(tester);
    // A punch-hole on the left of a landscape phone, reported as an inset
    // down the whole edge.
    tester.view.padding = FakeViewPadding(
      left: 64 * tester.view.devicePixelRatio,
    );
    tester.view.viewPadding = FakeViewPadding(
      left: 64 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await open(tester);

    expect(tester.getRect(byLogId('controller.exit')).left, lessThan(64));
  });

  testWidgets('with one printer its name is not a switcher', (tester) async {
    await pumpController(tester);

    await open(tester);

    expect(byLogId('controller.switch_printer'), findsNothing);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    expect(find.text('X1C Warsztat'), findsOneWidget);
  });

  testWidgets('entering locks landscape, hides the bars, holds the screen on', (
    tester,
  ) async {
    await pumpController(tester);

    await open(tester);

    expect(orientations, [
      ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
    ]);
    expect(uiModes, ['SystemUiMode.immersiveSticky']);
    expect(awake, [true]);
  });

  testWidgets('with the setting off the screen is left to time out', (
    tester,
  ) async {
    await pumpController(
      tester,
      prefs: {'controller_prefs': '{"keep_awake":false}'},
    );

    await open(tester);

    expect(awake, [false]);
  });

  testWidgets(
    'every way out gives the rotation, the bars and the timeout back',
    (tester) async {
      await pumpController(tester);
      await open(tester);

      await tester.tap(byLogId('controller.exit'));
      await settle(tester);

      expect(find.text('OPEN'), findsOneWidget);
      expect(orientations.last, <Object?>[]);
      expect(overlays.last, [
        'SystemUiOverlay.top',
        'SystemUiOverlay.bottom',
      ], reason: 'both bars back, the flags the activity starts with');
      expect(awake.last, isFalse);
    },
  );

  testWidgets('shows the live state of its printer', (tester) async {
    await pumpController(
      tester,
      printers: [_printer(1, 'X1C Warsztat', state: 'RUNNING')],
    );

    await open(tester);

    expect(find.text('RUNNING'), findsOneWidget);
  });

  testWidgets('the top bar fits a long name, every tab and a long state', (
    tester,
  ) async {
    await pumpController(
      tester,
      printers: [
        _printer(
          1,
          'Pracownia X1C numer dwa',
          model: 'X1 Carbon',
          state: 'PREPARE',
        ),
      ],
    );
    tester.view.physicalSize = const Size(740, 320);

    await open(tester);

    expect(tester.takeException(), isNull);
    for (final tab in ControllerTab.values) {
      expect(byLogId(tab.logId), findsOneWidget);
    }
    // The tabs scroll inside what the name and the state leave them, so look at
    // where things sit: they keep clear of the name on one side, and the last
    // one, once scrolled to, clears the state on the other. Before the scroll
    // its rectangle lies past the edge of the viewport, under the state.
    final name = tester.getRect(find.text('Pracownia X1C numer dwa'));
    final first = tester.getRect(byLogId(ControllerTab.values.first.logId));
    final state = tester.getRect(find.text('PREPARE'));
    expect(name.right, lessThanOrEqualTo(first.left));
    // The bar's frame ends between the two, whole: only the tabs scroll.
    final frame = tester.getRect(
      find
          .ancestor(
            of: byLogId(ControllerTab.values.first.logId),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).border != null,
            ),
          )
          .first,
    );
    expect(frame.left, greaterThanOrEqualTo(name.right));
    expect(frame.right, lessThanOrEqualTo(state.left));
    await tester.ensureVisible(byLogId(ControllerTab.values.last.logId));
    await tester.pump();
    final last = tester.getRect(byLogId(ControllerTab.values.last.logId));
    expect(last.right, lessThanOrEqualTo(state.left));
  });

  testWidgets('a short name leaves the rest of the bar to the tabs', (
    tester,
  ) async {
    await pumpController(
      tester,
      printers: [_printer(1, 'X1C', model: 'X1C', state: 'RUNNING')],
    );
    tester.view.physicalSize = const Size(600, 320);

    await open(tester);

    // The tabs do not fit, so the bar takes all the name leaves it: its frame
    // starts where the name ends, not where the name's cap would.
    final name = tester.getRect(find.text('X1C').first);
    final frame = tester.getRect(
      find
          .ancestor(
            of: byLogId(ControllerTab.values.first.logId),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).border != null,
            ),
          )
          .first,
    );
    final state = tester.getRect(find.text('RUNNING'));
    final tabs = tester.state<ScrollableState>(
      find
          .ancestor(
            of: byLogId(ControllerTab.values.first.logId),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tabs.position.maxScrollExtent,
      greaterThan(0),
      reason: 'the case under test is tabs that overflow',
    );
    expect(frame.left - name.right, lessThan(DashSpace.lg));
    // The gap before the state pill, and the pill's padding before its text.
    expect(state.left - frame.right, lessThan(DashSpace.lg + DashSpace.sm));
  });

  testWidgets('a printer the server no longer has says so, and can be left', (
    tester,
  ) async {
    await pumpController(tester);
    router.push('/controller/99');
    await settle(tester);

    expect(find.text(pl.controllerPrinterGone), findsOneWidget);
    expect(find.text('X1C Warsztat'), findsNothing);

    await tester.tap(byLogId('controller.exit'));
    await settle(tester);

    expect(find.text('OPEN'), findsOneWidget);
  });

  testWidgets('an id that is not a number opens no printer at all', (
    tester,
  ) async {
    await pumpController(tester);
    router.push('/controller/first');
    await settle(tester);

    expect(find.text(pl.controllerPrinterGone), findsOneWidget);
  });

  group('with several printers', () {
    final farm = [
      _printer(1, 'X1C Warsztat', model: 'X1C'),
      _printer(2, 'P1S Biuro', model: 'P1S', state: 'RUNNING'),
      _printer(3, 'A1 mini', connected: false),
    ];

    testWidgets('asks which one first, and lists them all', (tester) async {
      await pumpController(tester, printers: farm);

      await tester.tap(find.text('OPEN'));
      await settle(tester);

      expect(find.byType(ControllerScreen), findsNothing);
      expect(byLogId('controller.pick_printer'), findsNWidgets(3));
    });

    testWidgets('opens the one that was picked', (tester) async {
      await pumpController(tester, printers: farm);
      await tester.tap(find.text('OPEN'));
      await settle(tester);

      await tester.tap(find.text('P1S Biuro'));
      await settle(tester);

      expect(find.byType(ControllerScreen), findsOneWidget);
      expect(find.text('P1S'), findsOneWidget, reason: 'its model');
      expect(find.text('X1C Warsztat'), findsNothing);
    });

    testWidgets('a printer that does not answer cannot be picked', (
      tester,
    ) async {
      await pumpController(tester, printers: farm);
      await tester.tap(find.text('OPEN'));
      await settle(tester);

      await tester.tap(find.text('A1 mini'));
      await settle(tester);

      expect(find.byType(ControllerScreen), findsNothing);
      expect(byLogId('controller.pick_printer'), findsNWidgets(3));
    });

    testWidgets('switching printers keeps the bars hidden and the screen on', (
      tester,
    ) async {
      await pumpController(tester, printers: farm);
      await tester.tap(find.text('OPEN'));
      await settle(tester);
      await tester.tap(find.text('X1C Warsztat'));
      await settle(tester);

      await tester.tap(byLogId('controller.switch_printer'));
      await settle(tester);
      await tester.tap(find.text('P1S Biuro'));
      await settle(tester);

      expect(uiModes.last, 'SystemUiMode.immersiveSticky');
      expect(overlays, isEmpty, reason: 'the bars were never given back');
      expect(orientations.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(awake.last, isTrue);

      await tester.tap(byLogId('controller.exit'));
      await settle(tester);

      expect(overlays, hasLength(1), reason: 'leaving gives them back');
      expect(orientations.last, <Object?>[]);
      expect(awake.last, isFalse);
    });

    testWidgets('switching printers swaps the screen instead of stacking', (
      tester,
    ) async {
      await pumpController(tester, printers: farm);
      await tester.tap(find.text('OPEN'));
      await settle(tester);
      await tester.tap(find.text('X1C Warsztat'));
      await settle(tester);

      await tester.tap(byLogId('controller.switch_printer'));
      await settle(tester);
      await tester.tap(find.text('P1S Biuro'));
      await settle(tester);

      expect(find.text('P1S'), findsOneWidget);

      await tester.tap(byLogId('controller.exit'));
      await settle(tester);

      expect(
        find.text('OPEN'),
        findsOneWidget,
        reason: 'one Back reaches home',
      );
    });
  });
}
