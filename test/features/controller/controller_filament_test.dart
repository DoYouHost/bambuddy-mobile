import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_filament.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

AmsTray _tray(int id, String type, String color, {int? remain = 80}) =>
    AmsTray(id: id, trayType: type, trayColor: color, remain: remain);

const _empty = AmsTray(id: 3);

const _serial = '01P00A123456789';

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
Finder slots() => find.byWidgetPredicate((w) {
  final id = w is Semantics ? w.properties.identifier ?? '' : '';
  return id.startsWith('controller.slot') && id != 'controller.slot_edit';
});

void main() {
  setUpAll(loadAppFonts);

  late RecordingCommands commands;
  late _Statuses statuses;

  Future<void> pump(
    WidgetTester tester,
    PrinterStatus status, {
    int? nozzleCount,
    Size size = _phone,
    String? serial,
    InventoryState? inventory,
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
          // Scaled as the screen scales its body.
          child: ScaleToFit(child: ControllerFilament(printerId: 1)),
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
                  serialNumber: serial,
                ),
                status: status,
              ),
            ],
          ),
        ),
        printerStatusesProvider.overrideWith(() => statuses),
        if (inventory != null) ...[
          inventoryProvider.overrideWith(() => FixedInventory(inventory)),
          inventoryBackendOverride(InventoryBackend.spoolman),
        ],
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

    group('choosing a slot', () {
      /// The tilt of slot [i]'s spool: the rotation the wiggle applies.
      double tilt(WidgetTester tester, int i) {
        final wiggle = find
            .byWidgetPredicate((w) => w.runtimeType.toString() == '_Wiggle')
            .at(i);
        final box = tester.widget<Transform>(
          find.descendant(of: wiggle, matching: find.byType(Transform)).first,
        );
        return box.transform.entry(0, 1);
      }

      testWidgets('the number sits over the spool, not under it', (
        tester,
      ) async {
        await pump(tester, _status());

        // A Stack paints its last child on top: the corner mark comes last.
        final stack = tester.widget<Stack>(
          find
              .descendant(
                of: slots().first,
                matching: find.byWidgetPredicate(
                  (w) => w is Stack && w.children.any((c) => c is Positioned),
                ),
              )
              .first,
        );
        expect(stack.children.last, isA<Positioned>());
      });

      testWidgets('rocks the spool it chose, then it rests', (tester) async {
        await pump(tester, _status());
        // With nothing feeding the print, the first slot stands in as chosen.
        expect(tilt(tester, 0), 0, reason: 'not on first build');

        await tester.tap(slots().at(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(tilt(tester, 1), isNot(0), reason: 'mid-wiggle');
        expect(tilt(tester, 0), 0, reason: 'only the chosen one');

        await tester.pump(const Duration(seconds: 1));
        expect(tilt(tester, 1), 0);
      });

      testWidgets('a tap on the chosen slot again does not rock it', (
        tester,
      ) async {
        await pump(tester, _status());
        await tester.tap(slots().at(1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(slots().at(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(tilt(tester, 1), 0);
      });

      testWidgets('stays still for whoever turned animations off', (
        tester,
      ) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pump(tester, _status());

        await tester.tap(slots().at(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(tilt(tester, 1), 0);
      });
    });

    testWidgets('marks the slot that feeds the print', (tester) async {
      // Unit 0, slot 1 is global tray 1.
      await pump(tester, _status(trayNow: 1));

      expect(find.byTooltip(pl.ctrlNozzleActive), findsOneWidget);
    });

    testWidgets('marks nothing when nothing is loaded', (tester) async {
      await pump(tester, _status());

      expect(find.byTooltip(pl.ctrlNozzleActive), findsNothing);
    });

    testWidgets('shows its readings in the header', (tester) async {
      await pump(tester, _status());

      // Once in the rail, once in the header beside its drop icon.
      expect(find.text('24%'), findsNWidgets(2));
      expect(find.byIcon(Icons.water_drop_outlined), findsNWidgets(2));
    });

    testWidgets('labels its temperature with a thermometer', (tester) async {
      await pump(
        tester,
        _status(
          ams: [
            AmsUnit(id: 0, humidity: 24, temp: 28.4, trays: _unit(0).trays),
          ],
        ),
      );

      expect(find.text('28°'), findsOneWidget);
      expect(find.byIcon(Icons.thermostat_outlined), findsOneWidget);
    });

    testWidgets('the pencil opens the card\'s own slot sheet for its slot', (
      tester,
    ) async {
      await pump(tester, _status());

      await tester.tap(byLogId('controller.slot_edit').at(1));
      await settle(tester);

      expect(find.text(amsSlotName(0, 1)), findsWidgets);
    });

    testWidgets('a tap on a slot chooses it and opens nothing', (tester) async {
      await pump(tester, _status());

      await tester.tap(slots().at(2));
      await settle(tester);

      expect(find.text(amsSlotName(0, 2)), findsNothing);
      await tester.tap(byLogId('controller.load'));
      await settle(tester);
      expect(commands.calls, ['amsLoad:1:2:-']);
    });
  });

  group('a spool without a tag', () {
    testWidgets('is found in Spoolman by the printer\'s serial and the slot', (
      tester,
    ) async {
      // The tag the server derives for slot 0 of unit 0 of this printer.
      final tag = fallbackSpoolTag(_serial, 0, 0)!;
      await pump(
        tester,
        _status(),
        serial: _serial,
        inventory: InventoryState(
          linkedTags: {
            tag: const LinkedSpool(id: 7, remaining: 250, filament: 1000),
          },
        ),
      );
      await tester.pump();

      // Spoolman's 25% wins over the tray's own 82%.
      expect(find.textContaining('25%'), findsOneWidget);
      expect(find.textContaining('82%'), findsNothing);
    });
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

    testWidgets('a unit shows its humidity at the size of a reading', (
      tester,
    ) async {
      await pump(tester, _status());

      final reading = tester.widget<Text>(
        find.descendant(
          of: byLogId('controller.filament_unit').first,
          matching: find.text('24%'),
        ),
      );
      // 11 dp in the tertiary ink was not legible from a stand.
      expect(reading.style!.fontSize, greaterThanOrEqualTo(13));
      expect(reading.style!.color!.a, 1, reason: 'the primary ink, not faded');

      // On the line of the name, not under it.
      final button = byLogId('controller.filament_unit').first;
      final name = tester.getRect(
        find.descendant(of: button, matching: find.text('AMS-A')),
      );
      final value = tester.getRect(
        find.descendant(of: button, matching: find.text('24%')),
      );
      expect(value.center.dy, closeTo(name.center.dy, 2));
      expect(value.left, greaterThan(name.right));
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
      expect(find.text('24%'), findsNWidgets(2), reason: 'rail and header');

      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      expect(find.text('30%'), findsNWidgets(2), reason: 'rail and header');
      expect(find.text('24%'), findsOneWidget, reason: 'the rail only');
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
      expect(find.text('24%'), findsNWidgets(2), reason: 'back on unit 0');
    });
  });

  group('load and unload', () {
    testWidgets('act on the slot feeding the print until another is chosen', (
      tester,
    ) async {
      await pump(tester, _status(ams: [_unit(0), _unit(1)], trayNow: 1));

      await tester.tap(byLogId('controller.unload'));
      await settle(tester);
      expect(commands.calls, ['amsUnload:1:1']);
    });

    testWidgets('address a slot of the second unit by its global number', (
      tester,
    ) async {
      await pump(tester, _status(ams: [_unit(0), _unit(1)]));
      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      await tester.tap(slots().at(3));
      await tester.pump();
      await tester.tap(byLogId('controller.load'));
      await settle(tester);

      expect(commands.calls, ['amsLoad:1:7:-']);
    });

    testWidgets('are off while printing and say why', (tester) async {
      await pump(tester, _status(state: 'RUNNING'));

      expect(find.text(pl.amsActionsWhilePrinting), findsOneWidget);
      await tester.tap(byLogId('controller.load'));
      await tester.tap(byLogId('controller.unload'));
      await settle(tester);

      expect(commands.calls, isEmpty);
    });

    testWidgets('are on again while paused, for a runout', (tester) async {
      await pump(tester, _status(state: 'PAUSE'));

      expect(find.text(pl.amsActionsWhilePrinting), findsNothing);
      await tester.tap(byLogId('controller.load'));
      await settle(tester);

      expect(commands.calls, ['amsLoad:1:0:-']);
    });

    testWidgets('are not offered on a slot with no global number (AMS-HT)', (
      tester,
    ) async {
      await pump(tester, _status(ams: [_unit(128)]));

      expect(byLogId('controller.load'), findsNothing);
      expect(byLogId('controller.unload'), findsNothing);
    });

    testWidgets('load the external spool by its holder number', (tester) async {
      await pump(tester, _status(external: [_tray(254, 'TPU', '2E6FD8FF')]));
      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      await tester.tap(byLogId('controller.load'));
      await settle(tester);

      expect(commands.calls, ['amsLoad:1:254:-']);
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

    testWidgets('is marked when it feeds the print', (tester) async {
      // Holder 254 is the external spool of the only nozzle.
      await pump(
        tester,
        _status(external: [_tray(254, 'TPU', '2E6FD8FF')], trayNow: 254),
      );
      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      expect(find.byTooltip(pl.ctrlNozzleActive), findsOneWidget);
    });

    testWidgets('is not marked while another slot feeds the print', (
      tester,
    ) async {
      await pump(
        tester,
        _status(external: [_tray(254, 'TPU', '2E6FD8FF')], trayNow: 1),
      );
      await tester.tap(byLogId('controller.filament_unit').at(1));
      await tester.pump();

      expect(find.byTooltip(pl.ctrlNozzleActive), findsNothing);
    });

    testWidgets('is absent when the printer has none', (tester) async {
      await pump(tester, _status());

      expect(find.text(pl.externalSpool), findsNothing);
    });
  });

  group('drying', () {
    testWidgets('belongs to the unit, in its header, not with the slots', (
      tester,
    ) async {
      await pump(
        tester,
        _status(ams: [_unit(0, moduleType: 'n3f')], drying: true),
      );

      final dry = tester.getRect(byLogId('controller.dry'));
      expect(dry.bottom, lessThan(tester.getRect(slots().first).top));
      expect(
        dry.right,
        closeTo(tester.getRect(slots().last).right, 0.5),
        reason: 'at the right edge, in line with the last slot',
      );
    });

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
        find.text(pl.extruderLeft),
        findsOneWidget,
        reason: 'unit 0 feeds the left head',
      );
      expect(find.text(pl.extruderRight), findsNothing);
    });

    testWidgets('say nothing of sides on one nozzle', (tester) async {
      await pump(tester, _status(sides: {0: 1}));

      expect(find.text(pl.extruderLeft), findsNothing);
      expect(find.text(pl.extruderRight), findsNothing);
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
      Size(740, 320),
      Size(1280, 800),
    ]) {
      testWidgets('the spools fill their cards at ${size.width.round()}x'
          '${size.height.round()}', (tester) async {
        await pump(tester, _status(trayNow: 1, state: 'RUNNING'), size: size);
        await tester.pump();

        final cards = slots();
        expect(cards, findsNWidgets(4));
        final spools = [
          for (var i = 0; i < 4; i++)
            tester.getRect(
              find.descendant(
                of: cards.at(i),
                matching: find.byType(SvgPicture),
              ),
            ),
        ];
        // One size on every card, empty one included, and never smaller than
        // 84 dp, which reads from a stand.
        for (final spool in spools) {
          expect(spool.width, closeTo(spools.first.width, 0.5));
          expect(spool.height, closeTo(spools.first.height, 0.5));
        }
        expect(spools.first.height, greaterThanOrEqualTo(84));
        // Nothing hangs in a corner of the card: the last line sits within a
        // small margin of its bottom.
        final card = tester.getRect(cards.at(1));
        final last = tester.getRect(
          find.descendant(of: cards.at(1), matching: find.textContaining('%')),
        );
        expect(card.bottom - last.bottom, lessThanOrEqualTo(DashSpace.lg));
      });
    }

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
            // Printing: the lock's line sits under Load and Unload and takes
            // its height from the cards.
            state: 'RUNNING',
          ),
          size: size,
          // Every slot linked to a spool, so each card carries its grams line
          // as well, the tallest card there is.
          serial: _serial,
          inventory: InventoryState(
            linkedTags: {
              for (var unit = 0; unit < 4; unit++)
                for (var slot = 0; slot < 4; slot++)
                  fallbackSpoolTag(_serial, unit, slot)!: const LinkedSpool(
                    id: 7,
                    remaining: 880,
                    filament: 1000,
                  ),
            },
          ),
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
