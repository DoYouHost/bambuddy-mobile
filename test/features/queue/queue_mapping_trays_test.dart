import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The mapping sheet as the web's print dialog maps
/// (`useFilamentMapping.ts`, ported in `filament_mapping.dart` and checked
/// case by case in `filament_mapping_test.dart`): what it starts from, what it
/// sends, and what it shows about each slot.
class _Printers extends PrintersRepository {
  _Printers(this._status) : super(Dio());

  final PrinterStatus? _status;
  int fetches = 0;

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async {
    fetches++;
    return _status;
  }

  @override
  Future<SlotInventory> fetchInventoryRemain(int printerId) async =>
      (grams: const <int, double>{}, spools: const <int, SlotSpool>{});
}

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async {
    // Arrives after the slots, as a shelf nobody had open does.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return InventoryState(
      spools: [
        const Spool(id: 1, material: 'PLA', labelWeight: 1000, weightUsed: 898),
      ],
      assignments: [
        const SpoolAssignment(spoolId: 1, printerId: 1, amsId: 0, trayId: 0),
      ],
    );
  }
}

const _twoReds = PrinterStatus(
  id: 1,
  ams: [
    AmsUnit(
      id: 0,
      trays: [
        AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF0000FF', remain: 100),
        AmsTray(id: 1, trayType: 'PLA', trayColor: 'FF0000FF', remain: 66),
      ],
    ),
  ],
);

const _redPla = FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000');

void main() {
  late _Printers printers;
  List<int>? answer;

  Future<void> open(
    WidgetTester tester, {
    PrinterStatus? status = _twoReds,
    List<FilamentRequirement> requirements = const [_redPla],
    List<int>? stored,
    List<int>? startFrom,
  }) async {
    printers = _Printers(status);
    answer = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeServerProfileOverride(),
          printersRepositoryProvider.overrideWithValue(printers),
          inventoryBackendOverride(),
          inventoryProvider.overrideWith(_Shelf.new),
          serverSettingsOverride(const {}),
          printRequirementsProvider.overrideWith(
            (ref, key) async => requirements,
          ),
        ],
        child: plApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showQueueMappingSheet(
                context,
                item: QueueItem(
                  id: 1,
                  position: 1,
                  status: 'pending',
                  archiveId: 5,
                  amsMapping: stored,
                ),
                printerId: 1,
                confirmLabel: 'OK',
                startFrom: startFrom,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('it sends the whole mapping it shows, as the web', (
    tester,
  ) async {
    // Two red PLA spools: the first exact match wins.
    await open(tester);
    await confirm(tester);
    expect(answer, [0]);
  });

  testWidgets('a stored mapping is where it starts', (tester) async {
    // The web seeds its manual picks from the queue item's mapping.
    await open(tester, stored: [1]);
    await confirm(tester);
    expect(answer, [1]);
  });

  testWidgets('the caller\'s newer mapping outranks the stored one', (
    tester,
  ) async {
    // The edit form after a pick, and after a printer switch emptied it.
    await open(tester, startFrom: [1]);
    await confirm(tester);
    expect(answer, [1]);

    await open(tester, stored: [1], startFrom: const []);
    await confirm(tester);
    expect(answer, [0]);
  });

  testWidgets('dropping a pick lets the match decide again', (tester) async {
    await open(tester, stored: [1]);
    await tester.tap(find.text('PLA').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz slot AMS').last);
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(answer, [0]);
  });

  testWidgets('the mapping keeps the file\'s slot numbers', (tester) async {
    // A plate printing only slot 3 sends [-1, -1, tray] (`buildAmsMapping`).
    await open(
      tester,
      requirements: const [
        FilamentRequirement(slotId: 3, type: 'PLA', color: '#FF0000'),
      ],
    );
    await confirm(tester);
    expect(answer, [-1, -1, 0]);
  });

  testWidgets('a printer reporting no loaded slot sends no mapping', (
    tester,
  ) async {
    // Nothing from the inventory either, though the shelf assigns a spool
    // to the first slot: the web reads the live status alone.
    const unloaded = PrinterStatus(
      id: 1,
      ams: [
        AmsUnit(id: 0, trays: [AmsTray(id: 0)]),
      ],
    );
    await open(tester, status: unloaded, stored: [1]);
    expect(find.textContaining('Brak filamentów'), findsOneWidget);
    await confirm(tester);
    expect(answer, isEmpty);
  });

  testWidgets('a slot with a spool shows its grams, the rest only the type', (
    tester,
  ) async {
    // The web's picker: grams left on the built-in inventory's spool and no
    // percent (`FilamentMapping.tsx`, trayRemainingWeightMap).
    await open(
      tester,
      status: const PrinterStatus(
        id: 1,
        ams: [
          AmsUnit(
            id: 0,
            trays: [
              AmsTray(id: 0, trayType: 'PLA', remain: 100),
              AmsTray(id: 1, trayType: 'PETG', remain: 66),
            ],
          ),
        ],
      ),
    );
    await tester.tap(find.text('PLA').first);
    await tester.pumpAndSettle();

    // Slot 1 has a spool on the shelf, slot 2 none.
    expect(find.text('zostało 102 g'), findsOneWidget);
    expect(find.textContaining('A2: PETG'), findsOneWidget);
    // The shelf arriving late re-reads nothing: the status was fetched once.
    expect(printers.fetches, 1);
  });

  testWidgets('two external holders are Ext-L and Ext-R, as the web', (
    tester,
  ) async {
    // `useFilamentMapping.ts`: the letters on the machine, untranslated.
    await open(
      tester,
      status: const PrinterStatus(
        id: 1,
        vtTray: [
          AmsTray(id: 254, trayType: 'TPU'),
          AmsTray(id: 255, trayType: 'PLA'),
        ],
      ),
    );
    await tester.tap(find.text('PLA').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Ext-L: TPU'), findsOneWidget);
    expect(find.textContaining('Ext-R: PLA'), findsWidgets);
  });
}
