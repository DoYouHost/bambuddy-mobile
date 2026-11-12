import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
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
    await pick(tester, 'spool_assign.printer', 'spool_assign.printer_option');
    // The menu lists both printers under one id; the second is the X1C.
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
    await pick(tester, 'spool_assign.printer', 'spool_assign.printer_option');
    expect(byLogId('spool_assign.input'), findsNothing);

    await tester.tap(byLogId('spool_assign.save'));
    await settle(tester);
    final draft = shelf.drafts.single;
    expect((draft.printerId, draft.amsId, draft.trayId), (2, 255, 0));
  });
}
