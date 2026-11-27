import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The shelf, recording what the assign sheet saves.
class _Shelf extends FixedInventory {
  _Shelf()
    : super(
        InventoryState(
          spools: [Spool(id: 7, material: 'PETG', brand: 'Loose')],
        ),
      );

  final drafts = <SpoolAssignmentDraft>[];

  @override
  Future<void> assignSpool(
    SpoolAssignmentDraft draft, {
    SpoolAssignment? from,
  }) async => drafts.add(draft);
}

class _Statuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => {
    // An H3C whose first frame lists no unit and names no model.
    4: const PrinterStatus(id: 4, connected: true),
    for (final (id, unit) in [(1, 32), (2, 0)])
      id: PrinterStatus(
        id: id,
        connected: true,
        // Input 251 feeds hotend 4: Ext-5, stored as tray 6.
        vtTray: [if (unit == 32) const AmsTray(id: 251, trayType: 'PETG')],
        ams: [
          AmsUnit(
            id: unit,
            trays: [
              for (var t = 0; t < (unit == 32 ? 9 : 4); t++) AmsTray(id: t),
            ],
          ),
        ],
      ),
  };
}

void main() {
  late _Shelf shelf;

  Future<void> openAssign(WidgetTester tester, {double scale = 1.0}) async {
    shelf = _Shelf();
    usePhoneWindow(tester, dp: 2400);
    await pumpPhone(
      tester,
      const InventoryScreen(),
      builder: textScaled(scale),
      overrides: [
        inventoryProvider.overrideWith(() => shelf),
        noServerProfileOverride,
        printerStatusesProvider.overrideWith(_Statuses.new),
        fixedDashboardOverride(
          const DashboardState(
            printers: [
              PrinterWithStatus(
                printer: Printer(id: 1, name: 'Rack', model: 'H3C'),
              ),
              PrinterWithStatus(
                printer: Printer(id: 2, name: 'Carbon', model: 'X1C'),
              ),
              // Not in the live statuses: an H3C known only by its model.
              PrinterWithStatus(
                printer: Printer(id: 3, name: 'Asleep', model: 'H3C'),
              ),
              PrinterWithStatus(
                printer: Printer(id: 4, name: 'Waking', model: 'H3C'),
              ),
            ],
          ),
        ),
      ],
    );
    await settle(tester);
    await tester.tap(find.text('Loose PETG').first);
    await settle(tester);
    await tester.tap(byLogId('spool_actions.assign'));
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, String menu, String option) async {
    await tester.tap(byLogId(menu));
    await settle(tester);
    await tester.ensureVisible(byLogId(option).last);
    await settle(tester);
    await tester.tap(byLogId(option).last);
    await settle(tester);
  }

  Future<void> choosePrinter(WidgetTester tester, String name) async {
    await tester.tap(byLogId('spool_assign.printer'));
    await settle(tester);
    await tester.tap(find.text(name).last);
    await settle(tester);
  }

  testWidgets('an AMS 3H offers all nine slots', (tester) async {
    await openAssign(tester);
    await tester.tap(byLogId('spool_assign.slot'));
    await settle(tester);
    expect(byLogId('spool_assign.slot.8'), findsWidgets);
    expect(byLogId('spool_assign.slot.9'), findsNothing);
    await tester.ensureVisible(byLogId('spool_assign.slot.8').last);
    await settle(tester);
    await tester.tap(byLogId('spool_assign.slot.8').last);
    await settle(tester);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (1, 32, 8));
  });

  testWidgets('a printer with a four-slot AMS takes slot 9 back to 1', (
    tester,
  ) async {
    await openAssign(tester);
    await pick(tester, 'spool_assign.slot', 'spool_assign.slot.8');
    await choosePrinter(tester, 'Carbon');
    expect(byLogId('spool_assign.slot.8'), findsNothing);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.amsId, draft.trayId), (0, 0));
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets("the H3C's input menu fits at text scale $scale", (
      tester,
    ) async {
      await openAssign(tester, scale: scale);
      await tester.tap(find.text(pl.externalSpool));
      await settle(tester);
      await tester.tap(byLogId('spool_assign.input'));
      await settle(tester);
      // An overflow is a FlutterError, which fails the test on its own.
      expect(find.text('Ext-5 · PETG'), findsWidgets);
    });
  }

  testWidgets("an H3C's external spool goes to the input picked, Ext-n", (
    tester,
  ) async {
    await openAssign(tester);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    expect(find.text(pl.inventoryAssignExternalHint), findsNothing);
    await tester.tap(byLogId('spool_assign.input'));
    await settle(tester);
    expect(find.text('Ext-5 · PETG'), findsWidgets);
    expect(find.text('Ext-1 · ${pl.traySlotEmpty}'), findsWidgets);
    await tester.ensureVisible(byLogId('spool_assign.input.6').last);
    await settle(tester);
    await tester.tap(byLogId('spool_assign.input.6').last);
    await settle(tester);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (1, 255, 6));
  });

  testWidgets('a printer with one holder takes a rack input back to it', (
    tester,
  ) async {
    await openAssign(tester);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    await pick(tester, 'spool_assign.input', 'spool_assign.input.6');
    await choosePrinter(tester, 'Carbon');
    expect(byLogId('spool_assign.input'), findsNothing);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (2, 255, 0));
  });

  testWidgets('an H3C input defaults to Ext-1', (tester) async {
    await openAssign(tester);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    expect(find.text('Ext-1 · ${pl.traySlotEmpty}'), findsWidgets);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (1, 255, 1));
  });

  testWidgets('Ext-1 does not follow the spool to a one-holder printer', (
    tester,
  ) async {
    // Ext-1 is tray 1, which a printer with one holder does not have.
    await openAssign(tester);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    await choosePrinter(tester, 'Carbon');

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (2, 255, 0));
  });

  testWidgets('an H3C with no status yet offers its AMS 3H and nine slots', (
    tester,
  ) async {
    await openAssign(tester);
    await choosePrinter(tester, 'Asleep');

    expect(find.text('AMS 3H'), findsWidgets);
    await pick(tester, 'spool_assign.slot', 'spool_assign.slot.8');
    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (3, 32, 8));
  });

  testWidgets('back on the H3C after another printer the input is Ext-1', (
    tester,
  ) async {
    await openAssign(tester);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    await pick(tester, 'spool_assign.input', 'spool_assign.input.6');
    await choosePrinter(tester, 'Carbon');
    await choosePrinter(tester, 'Rack');

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (1, 255, 1));
  });

  testWidgets("an H3C's model counts when its status says nothing yet", (
    tester,
  ) async {
    await openAssign(tester);
    await choosePrinter(tester, 'Waking');
    expect(find.text('AMS 3H'), findsWidgets);
    await tester.tap(find.text(pl.externalSpool));
    await settle(tester);
    expect(byLogId('spool_assign.input'), findsOneWidget);
  });
}
