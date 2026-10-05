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

/// What the slot picker says about a slot while mapping a print — the web's
/// mapping: grams left on the built-in inventory's spool, and no percent at
/// all (`FilamentMapping.tsx`, trayRemainingWeightMap).
class _Printers extends PrintersRepository {
  _Printers() : super(Dio());

  int fetches = 0;

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async {
    fetches++;
    return const PrinterStatus(
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
    );
  }
}

/// A printer answering with [status] and nothing else.
class _Reporting extends PrintersRepository {
  _Reporting(this._status) : super(Dio());

  final PrinterStatus? _status;

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async => _status;
}

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async {
    // Arrives after the trays, as a shelf nobody had open does.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return InventoryState(
      spools: [
        Spool(id: 1, material: 'PLA', labelWeight: 1000, weightUsed: 898),
      ],
      assignments: [
        SpoolAssignment(spoolId: 1, printerId: 1, amsId: 0, trayId: 0),
      ],
    );
  }
}

void main() {
  testWidgets('a slot with a spool shows its grams, the rest only the type', (
    tester,
  ) async {
    final printers = _Printers();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeServerProfileOverride(),
          printersRepositoryProvider.overrideWithValue(printers),
          inventoryBackendOverride(),
          inventoryProvider.overrideWith(_Shelf.new),
          filamentRequirementsProvider.overrideWith(
            (ref, key) async => const [
              FilamentRequirement(slotId: 1, type: 'PLA'),
            ],
          ),
        ],
        child: plApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showQueueMappingSheet(
                context,
                item: const QueueItem(
                  id: 1,
                  position: 1,
                  status: 'pending',
                  archiveId: 5,
                ),
                printerId: 1,
                confirmLabel: 'OK',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament 1'));
    await tester.pumpAndSettle();

    expect(find.text('PLA · zostało 102 g'), findsOneWidget);
    expect(find.text('PETG'), findsOneWidget);
    // The shelf arriving late re-reads nothing: the status was fetched once.
    expect(printers.fetches, 1);
  });

  group('the slots offered', () {
    Future<List<int>> globalsFor(PrinterStatus? status) async {
      final container = ProviderContainer(
        overrides: [
          printersRepositoryProvider.overrideWithValue(_Reporting(status)),
          inventoryBackendOverride(),
          inventoryProvider.overrideWith(_Shelf.new),
        ],
      );
      addTearDown(container.dispose);
      final trays = await container.read(printerTraysProvider(1).future);
      return [for (final t in trays) t.global];
    }

    test('come from the live status alone, never the assignments', () async {
      // The web has no other source (`useFilamentMapping.ts`); a slot the
      // inventory remembers but the printer does not report is how a job
      // gets rejected. The shelf assigns a spool to the first slot here.
      const unloaded = PrinterStatus(
        id: 1,
        ams: [
          AmsUnit(id: 0, trays: [AmsTray(id: 0)]),
        ],
      );
      expect(await globalsFor(unloaded), isEmpty);
      expect(await globalsFor(null), isEmpty);
    });

    test(
      'include a transparent filament, as the web tests the type only',
      () async {
        const clear = PrinterStatus(
          id: 1,
          ams: [
            AmsUnit(
              id: 0,
              trays: [AmsTray(id: 2, trayType: 'PETG', trayColor: 'FFFFFF00')],
            ),
          ],
        );
        expect(await globalsFor(clear), [2]);
      },
    );
  });

  testWidgets('two external holders are Ext-L and Ext-R, as the web', (
    tester,
  ) async {
    // `useFilamentMapping.ts`: the letters on the machine, untranslated.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeServerProfileOverride(),
          printersRepositoryProvider.overrideWithValue(
            _Reporting(
              const PrinterStatus(
                id: 1,
                vtTray: [
                  AmsTray(id: 254, trayType: 'TPU'),
                  AmsTray(id: 255, trayType: 'PLA'),
                ],
              ),
            ),
          ),
          inventoryBackendOverride(),
          inventoryProvider.overrideWith(_Shelf.new),
          filamentRequirementsProvider.overrideWith(
            (ref, key) async => const [
              FilamentRequirement(slotId: 1, type: 'PLA'),
            ],
          ),
        ],
        child: plApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showQueueMappingSheet(
                context,
                item: const QueueItem(
                  id: 1,
                  position: 1,
                  status: 'pending',
                  archiveId: 5,
                ),
                printerId: 1,
                confirmLabel: 'OK',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament 1'));
    await tester.pumpAndSettle();

    expect(find.text('Ext-L'), findsOneWidget);
    expect(find.text('Ext-R'), findsOneWidget);
  });
}
