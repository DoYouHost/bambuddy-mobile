import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/printers/hms_readback.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_faults.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// A runout with the buttons Bambu's catalog lists for it. The message makes it
/// displayable without the catalogue, which tests do not load.
const _runout = HmsError(
  message: 'Filament has run out.',
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
  jobId: '746795586',
  actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
);

PrinterStatus _status(int id, {List<HmsError> errors = const []}) =>
    PrinterStatus(id: id, connected: true, state: 'PAUSE', hmsErrors: errors);

/// Live statuses the test can change, as the socket would.
class _Statuses extends PrinterStatusesNotifier {
  _Statuses(this._initial);

  final Map<int, PrinterStatus> _initial;

  @override
  Map<int, PrinterStatus> build() => _initial;

  void put(PrinterStatus status) => state = {...state, status.id: status};
}

void main() {
  setUpAll(loadAppFonts);

  late RecordingCommands commands;
  late _Statuses statuses;
  late StatusReadBack readBack;

  /// Printer 1's controller, with printer 2 in the roster beside it.
  Future<void> pump(
    WidgetTester tester, {
    List<HmsError> mine = const [],
    List<HmsError> other = const [],
    List<PrinterStatus?>? readBackAs,
  }) async {
    readBack = StatusReadBack(readBackAs ?? [_status(1)]);
    useLogicalWindow(tester, const Size(844, 390));
    commands = RecordingCommands();
    statuses = _Statuses({
      1: _status(1, errors: mine),
      2: _status(2, errors: other),
    });
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(body: Center(child: ControllerFaultChip(printerId: 1))),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        printersRepositoryProvider.overrideWithValue(readBack),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: const Printer(id: 1, name: 'X1C'),
                status: _status(1, errors: mine),
              ),
              PrinterWithStatus(
                printer: const Printer(id: 2, name: 'P1S'),
                status: _status(2, errors: other),
              ),
            ],
          ),
        ),
        printerStatusesProvider.overrideWith(() => statuses),
      ],
    );
    await tester.pump();
  }

  group('the chip', () {
    testWidgets('is absent while the printer reports no fault', (tester) async {
      await pump(tester);

      expect(byLogId('controller.faults'), findsNothing);
    });

    testWidgets('counts this printer\'s faults', (tester) async {
      await pump(tester, mine: const [_runout]);

      expect(byLogId('controller.faults'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('ignores a fault of another printer', (tester) async {
      await pump(tester, other: const [_runout]);

      expect(byLogId('controller.faults'), findsNothing);
    });
  });

  group('the fault view', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(byLogId('controller.faults'));
      await settle(tester);
    }

    testWidgets('answers a fault with the action its firmware offers', (
      tester,
    ) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);

      await tester.tap(byLogId('controller.hms_resume_printing'));
      await settle(tester);

      expect(commands.calls, [
        'hmsAction:1:03008004:RESUME_PRINTING:746795586',
      ]);
    });

    testWidgets('stops the print only after a confirmation', (tester) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);

      await tester.tap(byLogId('controller.hms_stop_printing'));
      await settle(tester);
      expect(commands.calls, isEmpty, reason: 'asked first');

      await tester.tap(byLogId('controller.hms_stop_confirm.confirm'));
      await settle(tester);
      expect(commands.calls, ['hmsAction:1:03008004:STOP_PRINTING:746795586']);
    });

    group('dismissing every fault', () {
      /// The tap, then enough time for every read-back the notifier may make.
      Future<void> dismiss(WidgetTester tester) async {
        await tester.tap(byLogId('controller.faults_dismiss_all'));
        await tester.pump();
        await tester.pump(hmsRecheckEvery * hmsRecheckAttempts);
      }

      testWidgets('sends the clear', (tester) async {
        await pump(tester, mine: const [_runout]);
        await open(tester);

        await dismiss(tester);

        expect(commands.calls, ['hmsClear:1']);
      });

      testWidgets('says they are gone when the status comes back empty', (
        tester,
      ) async {
        await pump(tester, mine: const [_runout]);
        await open(tester);

        await dismiss(tester);

        expect(find.text(pl.hmsDismissed), findsOneWidget);
        expect(
          readBack.reads,
          hmsRecheckAttempts,
          reason: 'an empty read is not trusted until the window is over',
        );
      });

      testWidgets('says the printer still reports a fault that comes back', (
        tester,
      ) async {
        await pump(
          tester,
          mine: const [_runout],
          readBackAs: [
            _status(1, errors: const [_runout]),
          ],
        );
        await open(tester);

        await dismiss(tester);

        expect(find.text(pl.hmsStillReported(1)), findsOneWidget);
        expect(find.text(pl.hmsDismissed), findsNothing);
        expect(readBack.reads, 1, reason: 'the first fault ends the wait');
      });

      testWidgets('catches a fault the printer reports a beat late', (
        tester,
      ) async {
        await pump(
          tester,
          mine: const [_runout],
          readBackAs: [
            _status(1),
            _status(1, errors: const [_runout, _runout]),
          ],
        );
        await open(tester);

        await dismiss(tester);

        expect(find.text(pl.hmsStillReported(2)), findsOneWidget);
        expect(readBack.reads, 2);
      });

      testWidgets('falls back to the plain confirmation when the status '
          'cannot be read', (tester) async {
        await pump(tester, mine: const [_runout], readBackAs: [null]);
        await open(tester);

        await dismiss(tester);

        expect(find.text(pl.hmsDismissed), findsOneWidget);
        expect(readBack.reads, 1);
      });

      testWidgets('reads nothing back when the clear itself is refused', (
        tester,
      ) async {
        await pump(tester, mine: const [_runout]);
        commands.errors['hmsClear'] = const ApiException(
          AppErrorCode.badResponse,
        );
        await open(tester);

        await dismiss(tester);

        expect(find.text(pl.hmsDismissed), findsNothing);
        expect(readBack.reads, 0);
      });
    });

    testWidgets('closes itself once the last fault clears', (tester) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);
      expect(find.byType(ControllerFaults), findsOneWidget);

      statuses.put(_status(1));
      await settle(tester);

      expect(find.byType(ControllerFaults), findsNothing);
    });

    testWidgets('closes itself, not the Stop confirmation above it, when the '
        'fault clears', (tester) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);
      await tester.tap(byLogId('controller.hms_stop_printing'));
      await settle(tester);

      statuses.put(_status(1));
      await settle(tester);

      expect(find.byType(ControllerFaults), findsNothing);
      expect(commands.calls, isEmpty);
    });

    testWidgets('never opens twice for one printer', (tester) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);

      // What the alert does when the print pauses while the view is open.
      showControllerFaults(
        tester.element(find.byType(ControllerFaultChip)),
        1,
        title: 'paused',
      );
      await settle(tester);

      expect(find.byType(ControllerFaults), findsOneWidget);
    });

    testWidgets('stays open while the printer is off the network', (
      tester,
    ) async {
      await pump(tester, mine: const [_runout]);
      await open(tester);

      statuses.put(
        const PrinterStatus(
          id: 1,
          connected: false,
          state: 'PAUSE',
          hmsErrors: [_runout],
        ),
      );
      await settle(tester);

      expect(find.byType(ControllerFaults), findsOneWidget);
    });

    testWidgets('two calls in one frame open one view', (tester) async {
      await pump(tester, mine: const [_runout]);
      final context = tester.element(find.byType(ControllerFaultChip));

      showControllerFaults(context, 1);
      showControllerFaults(context, 1);
      await settle(tester);

      expect(find.byType(ControllerFaults), findsOneWidget);
    });

    testWidgets('stays open when another printer\'s fault clears', (
      tester,
    ) async {
      await pump(tester, mine: const [_runout], other: const [_runout]);
      await open(tester);

      statuses.put(_status(2));
      await settle(tester);

      expect(find.byType(ControllerFaults), findsOneWidget);
    });
  });
}
