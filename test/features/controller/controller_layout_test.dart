import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_controls.dart';
import 'package:bambuddy_mobile/features/controller/controller_overview.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The design's landscape phone, an emulator-sized window, a short phone held
/// sideways, and a tablet.
const _sizes = [
  Size(844, 390),
  Size(1229, 540),
  Size(740, 320),
  Size(1280, 800),
];

class _Plugs extends SmartPlugsNotifier {
  @override
  SmartPlugsState build() => const SmartPlugsState(
    plugs: [
      SmartPlug(
        id: 10,
        name: 'Szafa',
        printerId: 1,
        enabled: true,
        showOnPrinterCard: true,
      ),
    ],
  );
}

const _printing = PrinterStatus(
  id: 1,
  connected: true,
  state: 'RUNNING',
  progress: 43,
  remainingTime: 52,
  layerNum: 114,
  totalLayers: 264,
  currentPrint: 'Bag dispenser.3mf',
  speedLevel: 2,
  temperatures: {
    'nozzle': 219,
    'nozzle_target': 220,
    'bed': 66,
    'bed_target': 65,
    'chamber': 33,
  },
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    PrinterStatus status = _printing,
  }) async {
    useLogicalWindow(tester, size);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          // Scaled as the screen scales its body.
          child: ScaleToFit(child: ControllerOverview(printerId: 1)),
        ),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        smartPlugsProvider.overrideWith(_Plugs.new),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: const Printer(id: 1, name: 'X1C'),
                status: status,
              ),
            ],
          ),
        ),
        inertStatusesOverride,
      ],
    );
    await tester.pump();
  }

  /// What scrolls the tab. A text field scrolls its own text, and the speed
  /// select is one.
  Finder scrollables() => find.descendant(
    of: find.byType(ControllerOverview),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.restorationId != 'editable',
    ),
  );

  for (final size in _sizes) {
    group('at ${size.width.round()}x${size.height.round()}', () {
      testWidgets('nothing scrolls and nothing overflows', (tester) async {
        await pump(tester, size);

        expect(scrollables(), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the right column runs to the bottom of the screen', (
        tester,
      ) async {
        await pump(tester, size);

        final overview = tester.getRect(find.byType(ControllerOverview));
        final switches = tester.getRect(find.byType(ControllerSwitches));
        expect(switches.bottom, closeTo(overview.bottom, 0.5));
      });

      testWidgets('the job stays inside its card, at any font size', (
        tester,
      ) async {
        for (final scale in [1.0, 1.5]) {
          await pump(tester, size, textScale: scale);

          // A FittedBox never reports an overflow, so look at where things sit.
          // The job's bar is the first: the reading tiles below carry their own.
          final jobBar = find.byType(DashProgressBar).first;
          final card = tester.getRect(
            find.ancestor(of: jobBar, matching: find.byType(Container)).first,
          );
          final bar = tester.getRect(jobBar);
          final percent = tester.getRect(find.text('43%'));
          expect(bar.bottom, lessThanOrEqualTo(card.bottom + 0.5));
          expect(percent.top, greaterThanOrEqualTo(card.top - 0.5));
          expect(percent.right, lessThanOrEqualTo(card.right + 0.5));
        }
      });

      testWidgets('the camera runs to the controls under it', (tester) async {
        await pump(tester, size);

        final overview = tester.getRect(find.byType(ControllerOverview));
        final skip = tester.getRect(byLogId('controller.skip_objects'));
        expect(skip.bottom, closeTo(overview.bottom, 0.5));
      });

      testWidgets('survives a larger system font without overflowing', (
        tester,
      ) async {
        await pump(tester, size, textScale: 1.5);

        expect(scrollables(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('a taller screen gives the rows more height', (tester) async {
    await pump(tester, _sizes.first);
    final design = tester.getSize(find.byType(ControllerSwitches)).height;

    await pump(tester, _sizes.last);
    final tablet = tester.getSize(find.byType(ControllerSwitches)).height;

    expect(tablet, greaterThan(design));
  });

  testWidgets('a printer that is not printing keeps its rows slim', (
    tester,
  ) async {
    await pump(
      tester,
      _sizes.last,
      status: const PrinterStatus(
        id: 1,
        connected: true,
        state: 'IDLE',
        temperatures: {'nozzle': 25, 'bed': 24},
      ),
    );

    expect(
      tester.getSize(find.byType(ControllerSwitches)).height,
      lessThanOrEqualTo(88),
    );
    expect(scrollables(), findsNothing);
  });
}
