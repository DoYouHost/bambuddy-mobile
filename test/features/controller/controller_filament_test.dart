import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_filament.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

AmsTray _tray(int id, String type, String color, {int? remain = 80}) =>
    AmsTray(id: id, trayType: type, trayColor: color, remain: remain);

const _empty = AmsTray(id: 3);

AmsUnit _unit(int id, {String? moduleType, int humidity = 24}) => AmsUnit(
  id: id,
  humidity: humidity,
  moduleType: moduleType,
  trays: [
    _tray(0, 'PLA', '1D1D1FFF', remain: 82),
    _tray(1, 'PLA', 'FF7A1AFF', remain: 64),
    _tray(2, 'PETG', 'F2F2F0FF', remain: 15),
    _empty,
  ],
);

PrinterStatus _status({
  List<AmsUnit>? ams,
  List<AmsTray>? external,
  int? trayNow,
  bool drying = false,
  Map<int, int>? sides,
  int? extruder,
  String state = 'IDLE',
}) => PrinterStatus(
  id: 1,
  connected: true,
  state: state,
  ams: ams ?? [_unit(0)],
  vtTray: external,
  trayNow: trayNow,
  supportsDrying: drying,
  amsExtruderMap: sides,
  activeExtruder: extruder,
);

/// Live statuses the test can change, as the socket would.
class _Statuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};

  void put(PrinterStatus status) => state = {...state, status.id: status};
}

/// The slot cards. Their identifier carries the material (`logTagMaterial`), so
/// they are found by prefix.
Finder slots() => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.identifier ?? '').startsWith('controller.slot'),
);

void main() {
  late RecordingCommands commands;
  late _Statuses statuses;

  Future<void> pump(
    WidgetTester tester,
    PrinterStatus status, {
    int? nozzleCount,
    Size size = _phone,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    commands = RecordingCommands();
    statuses = _Statuses();
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: ControllerFilament(printerId: 1),
        ),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        inertHistorySupportOverrides.first,
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: Printer(
                  id: 1,
                  name: 'P',
                  model: 'X1C',
                  nozzleCount: nozzleCount,
                ),
                status: status,
              ),
            ],
          ),
        ),
        printerStatusesProvider.overrideWith(() => statuses),
      ],
    );
    await tester.pump();
  }

  group('a unit', () {
    testWidgets('shows each slot with its material and what is left', (
      tester,
    ) async {
      await pump(tester, _status());

      expect(find.text('PLA'), findsNWidgets(2));
      expect(find.text('PETG'), findsOneWidget);
      expect(find.text(pl.traySlotEmpty), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('15%'), findsOneWidget);
      expect(slots(), findsNWidgets(4));
    });

    testWidgets('marks the slot that feeds the print', (tester) async {
      // Unit 0, slot 1 is global tray 1.
      await pump(tester, _status(trayNow: 1));

      expect(find.text(pl.ctrlNozzleActive), findsOneWidget);
    });

    testWidgets('marks nothing when nothing is loaded', (tester) async {
      await pump(tester, _status());

      expect(find.text(pl.ctrlNozzleActive), findsNothing);
    });

    testWidgets('shows its readings in the header', (tester) async {
      await pump(tester, _status());

      expect(find.textContaining('${amsUnitName(0)} · 24%'), findsOneWidget);
    });

    testWidgets(
      'opens the card\'s own slot sheet for the slot that was tapped',
      (tester) async {
        await pump(tester, _status());

        await tester.tap(slots().at(1));
        await settle(tester);

        expect(find.text(amsSlotName(0, 1)), findsWidgets);
      },
    );
  });

  group('the rail', () {
    testWidgets('a unit button is a real touch target, not a strip', (
      tester,
    ) async {
      await pump(tester, _status());

      expect(
        tester.getRect(byLogId('controller.filament_unit').first).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('and a slot card is big enough to read', (tester) async {
      await pump(tester, _status());
      final small = tester.getRect(slots().first).size;

      await pump(tester, _status(), size: const Size(1280, 800));
      final large = tester.getRect(slots().first).size;

      expect(small.height, greaterThanOrEqualTo(120));
      expect(large.height, greaterThan(small.height));
    });
  });

  group('several units', () {
    final two = [_unit(0), _unit(1, humidity: 30)];

    testWidgets('are listed in a rail, one on screen at a time', (
      tester,
    ) async {
      await pump(tester, _status(ams: two));

      expect(byLogId('controller.filament_unit'), findsNWidgets(2));
      expect(slots(), findsNWidgets(4));
    });

    testWidgets('a tap on the rail switches to that unit', (tester) async {
      await pump(tester, _status(ams: two));
      expect(find.textContaining('${amsUnitName(0)} · 24%'), findsOneWidget);

      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      expect(find.textContaining('${amsUnitName(1)} · 30%'), findsOneWidget);
      expect(find.textContaining('${amsUnitName(0)} · 24%'), findsNothing);
    });

    testWidgets('survive the unit they were looking at going away', (
      tester,
    ) async {
      await pump(tester, _status(ams: two));
      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      statuses.put(_status(ams: [_unit(0)]));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('${amsUnitName(0)} · 24%'), findsOneWidget);
    });
  });

  group('the external spool', () {
    testWidgets('is a unit of its own in the rail', (tester) async {
      await pump(tester, _status(external: [_tray(254, 'TPU', '2E6FD8FF')]));

      expect(byLogId('controller.filament_unit'), findsNWidgets(2));

      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      expect(find.text('TPU'), findsOneWidget);
      expect(find.text(pl.externalSpool), findsWidgets);
    });

    testWidgets('is absent when the printer has none', (tester) async {
      await pump(tester, _status());

      expect(find.text(pl.externalSpool), findsNothing);
    });
  });

  group('drying', () {
    testWidgets('is offered on a module that can dry, on a printer that can', (
      tester,
    ) async {
      await pump(
        tester,
        _status(ams: [_unit(0, moduleType: 'n3f')], drying: true),
      );

      expect(byLogId('controller.dry'), findsOneWidget);
    });

    testWidgets('is not offered on a module that cannot', (tester) async {
      await pump(tester, _status(drying: true));

      expect(byLogId('controller.dry'), findsNothing);
    });

    testWidgets('is not offered by a printer that cannot', (tester) async {
      await pump(tester, _status(ams: [_unit(0, moduleType: 'n3f')]));

      expect(byLogId('controller.dry'), findsNothing);
    });

    testWidgets('opens the drying sheet', (tester) async {
      await pump(
        tester,
        _status(ams: [_unit(0, moduleType: 'n3f')], drying: true),
      );

      await tester.tap(byLogId('controller.dry'));
      await settle(tester);

      expect(find.text(pl.ctrlDryStart), findsOneWidget);
    });
  });

  group('two nozzles', () {
    testWidgets('say which side a unit feeds', (tester) async {
      await pump(
        tester,
        _status(ams: [_unit(0), _unit(1)], sides: {0: 1, 1: 0}, extruder: 0),
        nozzleCount: 2,
      );

      expect(
        find.text('${amsUnitName(0)} · ${pl.extruderLeftShort} · 24%'),
        findsOneWidget,
        reason: 'unit 0 feeds the left head',
      );
    });

    testWidgets('say nothing of sides on one nozzle', (tester) async {
      await pump(tester, _status(sides: {0: 1}));

      expect(find.text('${amsUnitName(0)} · 24%'), findsOneWidget);
    });
  });

  group('a printer with nothing loaded at all', () {
    testWidgets('shows a dash, not an error', (tester) async {
      await pump(tester, _status(ams: const []));

      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the layout', () {
    for (final size in const [
      Size(844, 390),
      Size(1229, 540),
      Size(740, 320),
      Size(1280, 800),
    ]) {
      testWidgets('fits ${size.width.round()}x${size.height.round()} without '
          'scrolling', (tester) async {
        await pump(
          tester,
          _status(
            ams: [for (var i = 0; i < 4; i++) _unit(i)],
            external: [_tray(254, 'TPU', '2E6FD8FF')],
            trayNow: 1,
          ),
          size: size,
        );

        expect(
          find.descendant(
            of: find.byType(ControllerFilament),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
