import 'dart:async';

import 'package:bambuddy_mobile/core/models/panda_breath.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

const _heater = PandaBreathState(
  deviceId: 'pb-1',
  online: true,
  chamberTemp: 41,
  targetTemp: 45,
  workOn: true,
  mode: 'auto mode',
);

PrinterStatus _status({
  bool connected = true,
  PandaBreathState? panda = _heater,
}) => PrinterStatus(
  id: 2,
  name: 'P1S',
  model: 'P1S',
  connected: connected,
  state: connected ? 'IDLE' : null,
  temperatures: connected
      ? const {'nozzle': 28, 'bed': 26, 'chamber': 39}
      : null,
  pandaBreath: panda,
);

/// The live map the sheet reads the heater from, holding one fixed status.
class _Statuses extends PrinterStatusesNotifier {
  _Statuses(this.status, [this.handle]);
  final PrinterStatus status;
  final _StatusesHandle? handle;
  @override
  Map<int, PrinterStatus> build() {
    handle?._notifier = this;
    return {status.id: status};
  }
}

/// Lets a test replace the live status while a sheet reads it.
class _StatusesHandle {
  _Statuses? _notifier;
  void set(PrinterStatus status) => _notifier!.state = {status.id: status};
}

void main() {
  late RecordingCommands commands;
  setUp(() => commands = RecordingCommands());

  Future<void> pumpCard(
    WidgetTester tester,
    PrinterStatus status, {
    double scale = 1.0,
    bool refused = false,
    PrinterCommandsRepository? repo,
    _StatusesHandle? statuses,
  }) async {
    // The narrow phone the layout has to fit (docs/dev-environment.md).
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: layerOverrides(
          [
            fakeServerProfileOverride(),
            mediaAuthOverride(),
            inertFirmwareOverride,
            inertTotalPrintHoursOverride,
            inertChamberMaxOverride,
            ...inertHistorySupportOverrides,
            ...inertDashboardPollOverrides,
          ],
          [
            printerCommandsRepositoryProvider.overrideWithValue(
              repo ?? commands,
            ),
            printerStatusesProvider.overrideWith(
              () => _Statuses(status, statuses),
            ),
            if (refused)
              controlRefusedProvider(
                ControlPermission.control,
              ).overrideWithValue(true),
          ],
        ),
        child: plApp(
          Scaffold(
            body: SingleChildScrollView(
              child: PrinterCard(
                item: PrinterWithStatus(
                  printer: const Printer(id: 2, name: 'P1S'),
                  status: status,
                ),
              ),
            ),
          ),
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: app!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(byLogId('printer.panda_breath'));
    await tester.pumpAndSettle();
  }

  group('on a connected printer', () {
    testWidgets('is one more tile of the temperature grid', (tester) async {
      await pumpCard(tester, _status());

      expect(find.text(pl.pandaBreath.toUpperCase()), findsOneWidget);
      expect(find.text('41°'), findsOneWidget);
      expect(find.text('45°'), findsOneWidget);
      // The offline card's row is not shown beside it: one place per card.
      expect(byLogId('panda_breath.power'), findsNothing);
    });

    testWidgets('an older server, or no heater bound: no tile', (tester) async {
      await pumpCard(tester, _status(panda: null));

      expect(find.text(pl.pandaBreath.toUpperCase()), findsNothing);
      expect(byLogId('printer.panda_breath'), findsNothing);
    });

    testWidgets('a heater the server cannot reach is shown, not driven', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _status(
          panda: const PandaBreathState(
            deviceId: 'pb-1',
            online: false,
            chamberTemp: 41,
          ),
        ),
      );

      expect(find.text(pl.pandaBreath.toUpperCase()), findsOneWidget);
      // The last reading of an unreachable heater is not today's.
      expect(find.text('41°'), findsNothing);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.cloud_off)).semanticLabel,
        pl.pandaBreathOffline,
      );
      expect(byLogId('printer.panda_breath'), findsNothing);
    });

    testWidgets('a key that may not control gets the reading only', (
      tester,
    ) async {
      await pumpCard(tester, _status(), refused: true);

      expect(find.text('41°'), findsOneWidget);
      expect(byLogId('printer.panda_breath'), findsNothing);
    });
  });

  group('on an offline printer', () {
    testWidgets('stays on the collapsed card as a row with a switch', (
      tester,
    ) async {
      await pumpCard(tester, _status(connected: false));

      expect(find.text(pl.statusOffline), findsOneWidget);
      expect(find.text(pl.pandaBreath), findsOneWidget);
      expect(find.text('41° → 45° · ${pl.commonAuto}'), findsOneWidget);

      await tester.tap(byLogId('panda_breath.power'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['pandaOn:2:false']);
      expect(find.text(pl.pandaBreathSent), findsOneWidget);
      // The switch is its own target: the sheet did not open under it.
      expect(byLogId('panda_breath.set'), findsNothing);
    });

    testWidgets('the row opens the sheet', (tester) async {
      await pumpCard(tester, _status(connected: false));
      await openSheet(tester);

      expect(byLogId('panda_breath.set'), findsOneWidget);
    });

    testWidgets('a drying cycle shows the time left', (tester) async {
      await pumpCard(
        tester,
        _status(
          connected: false,
          panda: const PandaBreathState(
            deviceId: 'pb-1',
            chamberTemp: 50,
            targetTemp: 55,
            workOn: true,
            mode: 'filament drying',
            dryingRunning: true,
            dryingRemainingMin: 94.6,
          ),
        ),
      );

      expect(
        find.text(
          '50° → 55° · ${pl.pandaBreathModeDrying} · '
          '${pl.pandaBreathDryingLeft(95)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a heater that is off shows no target', (tester) async {
      await pumpCard(
        tester,
        _status(
          connected: false,
          panda: const PandaBreathState(
            deviceId: 'pb-1',
            chamberTemp: 27,
            targetTemp: 45,
            workOn: false,
          ),
        ),
      );

      expect(find.text('27°'), findsOneWidget);
      await tester.tap(byLogId('panda_breath.power'));
      await tester.pumpAndSettle();
      expect(commands.calls, ['pandaOn:2:true']);
    });

    testWidgets('an unreachable heater: no switch, no sheet', (tester) async {
      await pumpCard(
        tester,
        _status(
          connected: false,
          panda: const PandaBreathState(deviceId: 'pb-1', online: false),
        ),
      );

      expect(find.text(pl.pandaBreathOffline), findsOneWidget);
      expect(byLogId('panda_breath.power'), findsNothing);
      expect(byLogId('printer.panda_breath'), findsNothing);
    });
  });

  testWidgets('an unreachable heater shows no stale target either', (
    tester,
  ) async {
    // The server keeps the last target of a heater it lost (`to_dict`).
    await pumpCard(
      tester,
      _status(
        panda: const PandaBreathState(
          deviceId: 'pb-1',
          online: false,
          chamberTemp: 41,
          targetTemp: 45,
          workOn: true,
        ),
      ),
    );

    expect(find.text('45°'), findsNothing);
  });

  testWidgets('a second tap on the switch mid-request opens no sheet', (
    tester,
  ) async {
    final held = Completer<void>();
    commands.holds['pandaOn'] = held;
    await pumpCard(tester, _status(connected: false));

    await tester.tap(byLogId('panda_breath.power'));
    await tester.pump();
    await tester.tap(byLogId('panda_breath.power'));
    // The spinner runs for as long as the request: fixed pumps.
    await tester.pump(const Duration(milliseconds: 500));

    expect(byLogId('panda_breath.set'), findsNothing);
    expect(commands.calls, ['pandaOn:2:false']);
    // Nothing for a reader to activate while the request runs.
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(byLogId('panda_breath.power')),
      isSemantics(hasTapAction: false),
    );
    semantics.dispose();
    held.complete();
    await tester.pumpAndSettle();
  });

  group('the sheet', () {
    testWidgets('follows the heater\'s target until the user edits it', (
      tester,
    ) async {
      final status = _StatusesHandle();
      await pumpCard(tester, _status(), statuses: status);
      await openSheet(tester);

      // Changed elsewhere (the web) while the sheet is open.
      status.set(
        _status(
          panda: const PandaBreathState(
            deviceId: 'pb-1',
            online: true,
            targetTemp: 50,
            workOn: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('50°'), findsOneWidget);

      await tester.tap(byLogId('panda_breath.step_up'));
      await tester.pump();
      status.set(
        _status(
          panda: const PandaBreathState(
            deviceId: 'pb-1',
            online: true,
            targetTemp: 52,
            workOn: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The user's pick is not overwritten under their thumb.
      expect(find.text('51°'), findsOneWidget);
    });

    testWidgets('a held editor takes no keyboard focus either', (tester) async {
      final status = _StatusesHandle();
      await pumpCard(tester, _status(), statuses: status);
      await openSheet(tester);
      status.set(_status(panda: null));
      await tester.pumpAndSettle();

      final step = find.descendant(
        of: byLogId('panda_breath.step_up'),
        matching: find.byType(Icon),
      );
      expect(Focus.of(tester.element(step)).canRequestFocus, isFalse);
    });

    testWidgets('a heater that goes away freezes the target too', (
      tester,
    ) async {
      final status = _StatusesHandle();
      await pumpCard(tester, _status(), statuses: status);
      await openSheet(tester);

      status.set(_status(panda: null));
      await tester.pumpAndSettle();
      expect(byLogId('panda_breath.set'), findsOneWidget);
      await tester.tap(byLogId('panda_breath.step_up'), warnIfMissed: false);
      await tester.pump();

      // Gone, the heater has no target to start from: the editor holds still.
      expect(find.text('1°'), findsNothing);
      expect(find.text('46°'), findsNothing);
    });

    testWidgets('sends the mode, closes and says it was sent', (tester) async {
      await pumpCard(tester, _status());
      await openSheet(tester);

      await tester.tap(find.text(pl.pandaBreathModeDrying));
      await tester.pumpAndSettle();

      expect(commands.calls, ['pandaMode:2:filament drying']);
      expect(byLogId('panda_breath.set'), findsNothing);
      expect(find.text(pl.pandaBreathSent), findsOneWidget);
    });

    testWidgets('starts at the heater\'s target and sends the one picked', (
      tester,
    ) async {
      await pumpCard(tester, _status());
      await openSheet(tester);

      await tester.tap(byLogId('panda_breath.step_up'));
      await tester.pump();
      await tester.tap(byLogId('panda_breath.set'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['pandaTarget:2:46']);
    });

    testWidgets('the target stops at the server\'s 60', (tester) async {
      await pumpCard(tester, _status());
      await openSheet(tester);

      await tester.tap(find.text('$pandaBreathMaxTargetC°'));
      await tester.pump();
      await tester.tap(byLogId('panda_breath.step_up'));
      await tester.pump();
      await tester.tap(byLogId('panda_breath.set'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['pandaTarget:2:$pandaBreathMaxTargetC']);
    });

    testWidgets('turns the heater off', (tester) async {
      await pumpCard(tester, _status());
      await openSheet(tester);

      await tester.tap(find.text(pl.pandaBreathTurnOff));
      await tester.pumpAndSettle();

      expect(commands.calls, ['pandaOn:2:false']);
    });

    testWidgets('a refusal keeps the sheet open under its message', (
      tester,
    ) async {
      // The server's 503: its MQTT broker is down.
      commands.errors['pandaOn'] = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 503,
      );
      await pumpCard(tester, _status());
      await openSheet(tester);

      await tester.tap(find.text(pl.pandaBreathTurnOff));
      await tester.pumpAndSettle();

      expect(byLogId('panda_breath.set'), findsOneWidget);
      expect(find.text(pl.pandaBreathSent), findsNothing);
    });

    testWidgets('an unexpected error unlocks the sheet and reaches the log', (
      tester,
    ) async {
      commands.errors['pandaMode'] = StateError('unreadable');
      await pumpCard(tester, _status());
      await openSheet(tester);

      final errors = await tapCapturingErrors(
        tester,
        find.text(pl.pandaBreathModeOn),
        animated: true,
      );

      expect(errors.single, isA<StateError>());
      expect(commands.calls, ['pandaMode:2:power on']);
      // Unlocked: the next tap goes out instead of hitting a dead chip.
      await tapCapturingErrors(
        tester,
        find.text(pl.pandaBreathModeOn),
        animated: true,
      );
      expect(commands.calls, hasLength(2));
    });
  });

  testWidgets('the writes the sheet sends, recorded for the live server', (
    tester,
  ) async {
    final dio = testDio();
    mockServer(dio).onPost(
      '/api/v1/printers/2/panda-breath',
      (server) => server.reply(200, {'success': true}),
      data: Matchers.any,
    );
    final log = captureRequests(dio);
    await pumpCard(tester, _status(), repo: PrinterCommandsRepository(dio));

    // Each change closes the sheet, as on the web.
    await openSheet(tester);
    await tester.tap(find.text(pl.pandaBreathTurnOff));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await tester.tap(find.text(pl.pandaBreathModeDrying));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await tester.tap(byLogId('panda_breath.step_up'));
    await tester.pump();
    await tester.tap(byLogId('panda_breath.set'));
    await tester.pumpAndSettle();

    // Replayed by `panda_breath_contract_test.dart`.
    expectSentAsRecorded('panda_breath', writesOf(log.requests));
  });

  group('at large text', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the tile, the row and the sheet fit at text $scale', (
        tester,
      ) async {
        await pumpCard(tester, _status(), scale: scale);
        expect(tester.takeException(), isNull);
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        // Every mode stays reachable when the chips wrap.
        final modes = byLogId('panda_breath.mode');
        expect(modes, findsNWidgets(PandaBreathMode.values.length));
        for (var i = 0; i < PandaBreathMode.values.length; i++) {
          expect(tester.getRect(modes.at(i)).right, lessThanOrEqualTo(360));
        }

        await pumpCard(tester, _status(connected: false), scale: scale);
        expect(tester.takeException(), isNull);
        final row = tester.getRect(byLogId('panda_breath.power'));
        expect(row.right, lessThanOrEqualTo(360));
        expect(row.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      });
    }
  });
}
