import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_faults.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Displayable without the catalogue, which tests do not load.
const _runout = HmsError(
  message: 'Filament has run out.',
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
  actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
);

PrinterStatus _status(
  int id, {
  String state = 'RUNNING',
  List<HmsError> errors = const [],
}) => PrinterStatus(id: id, connected: true, state: state, hmsErrors: errors);

class _Statuses extends PrinterStatusesNotifier {
  _Statuses(this._initial);

  final Map<int, PrinterStatus> _initial;

  @override
  Map<int, PrinterStatus> build() => _initial;

  void put(PrinterStatus status) => state = {...state, status.id: status};
}

void main() {
  setUpAll(loadAppFonts);

  late _Statuses statuses;

  /// Printer 1's controller with a one-minute saver, printer 2 beside it.
  Future<void> pump(
    WidgetTester tester, {
    bool wakeOnWarnings = true,
    List<HmsError> atOpen = const [],
    String stateAtOpen = 'RUNNING',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    statuses = _Statuses({
      1: _status(1, state: stateAtOpen, errors: atOpen),
      2: _status(2),
    });
    SharedPreferences.setMockInitialValues({
      'controller_prefs':
          '{"saver_after_minutes":1,"wake_on_warnings":$wakeOnWarnings}',
    });
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const ControllerSaverHost(
        printerId: 1,
        child: Scaffold(body: Text('controller')),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(
          RecordingCommands(),
        ),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: const Printer(id: 1, name: 'X1C'),
                status: _status(1),
              ),
              PrinterWithStatus(
                printer: const Printer(id: 2, name: 'P1S'),
                status: _status(2),
              ),
            ],
          ),
        ),
        printerStatusesProvider.overrideWith(() => statuses),
      ],
    );
    await tester.pump();
  }

  /// The listener runs during the frame after the change, and what it does
  /// shows in the frame after that; the dialog's entrance takes the rest.
  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> idle(WidgetTester tester) =>
      tester.pump(const Duration(minutes: 1, seconds: 1));

  Finder saver() => find.byType(ControllerSaver);
  Finder alert() => find.byType(ControllerFaults);

  testWidgets('a fault that pauses the print wakes the screen and opens the '
      'fault view', (tester) async {
    await pump(tester);
    await idle(tester);
    expect(saver(), findsOneWidget);

    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(saver(), findsNothing);
    expect(alert(), findsOneWidget);
    expect(find.text(pl.controllerPrintPaused), findsOneWidget);
  });

  testWidgets('a fault while printing only wakes the screen', (tester) async {
    await pump(tester);
    await idle(tester);

    statuses.put(_status(1, errors: const [_runout]));
    await frames(tester);

    expect(saver(), findsNothing);
    expect(alert(), findsNothing);
  });

  testWidgets('with Wake on warnings off, a fault while printing lets the '
      'saver be', (tester) async {
    await pump(tester, wakeOnWarnings: false);
    await idle(tester);

    statuses.put(_status(1, errors: const [_runout]));
    await frames(tester);

    expect(saver(), findsOneWidget);
  });

  testWidgets('a warning that then pauses the print opens the fault view', (
    tester,
  ) async {
    await pump(tester);
    statuses.put(_status(1, errors: const [_runout]));
    await frames(tester);
    expect(alert(), findsNothing);

    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(alert(), findsOneWidget);
  });

  testWidgets('another printer\'s fault neither wakes nor opens anything', (
    tester,
  ) async {
    await pump(tester);
    await idle(tester);

    statuses.put(_status(2, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(saver(), findsOneWidget);
    expect(alert(), findsNothing);
  });

  testWidgets('a fault already there when the controller opens raises '
      'nothing', (tester) async {
    await pump(tester, atOpen: const [_runout], stateAtOpen: 'PAUSE');
    await frames(tester);
    // The next status frame repeats the same fault; it is not a new one.
    statuses.put(
      PrinterStatus(
        id: 1,
        connected: true,
        state: 'PAUSE',
        progress: 41,
        hmsErrors: const [_runout],
      ),
    );
    await frames(tester);

    expect(alert(), findsNothing);
  });

  testWidgets('a warning already there at open still raises the alert when '
      'it pauses the print', (tester) async {
    await pump(tester, atOpen: const [_runout]);
    await idle(tester);

    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(saver(), findsNothing);
    expect(alert(), findsOneWidget);
  });

  testWidgets('a dropped connection does not bring back an answered alert', (
    tester,
  ) async {
    await pump(tester);
    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);
    await tester.tap(byLogId('controller.faults_close'));
    await frames(tester);
    expect(alert(), findsNothing);

    statuses.put(
      const PrinterStatus(
        id: 1,
        connected: false,
        state: 'PAUSE',
        hmsErrors: [_runout],
      ),
    );
    await frames(tester);
    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(alert(), findsNothing);
  });

  testWidgets('a fault cleared while the printer was away alerts again when '
      'it comes back', (tester) async {
    await pump(tester);
    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);
    await tester.tap(byLogId('controller.faults_close'));
    await frames(tester);

    // Off the network, cleared at the printer, back with nothing to report.
    statuses.put(
      const PrinterStatus(
        id: 1,
        connected: false,
        state: 'PAUSE',
        hmsErrors: [_runout],
      ),
    );
    await frames(tester);
    statuses.put(_status(1, state: 'PAUSE'));
    await frames(tester);
    expect(alert(), findsNothing);

    // The same fault, a second time.
    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);

    expect(alert(), findsOneWidget);
  });

  testWidgets('the saver comes back over the alert if nobody answers', (
    tester,
  ) async {
    await pump(tester);
    statuses.put(_status(1, state: 'PAUSE', errors: const [_runout]));
    await frames(tester);
    expect(alert(), findsOneWidget);

    await idle(tester);

    expect(saver(), findsOneWidget);
    expect(alert(), findsOneWidget, reason: 'still open under the saver');
  });
}
