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

/// The fill the slot picker shows while mapping a print — the same reading as
/// the printer card, so the slot a user picks by "how much is left" is not
/// the one the AMS calls 100% for want of an RFID tag (issue #5).
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

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async {
    // Arrives after the trays, as a shelf nobody had open does.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const InventoryState(
      spools: [
        Spool(id: 1, material: 'PLA', labelWeight: 1000, weightUsed: 898),
      ],
      assignmentBySpool: {
        1: SpoolAssignment(spoolId: 1, printerId: 1, amsId: 0, trayId: 0),
      },
    );
  }
}

void main() {
  testWidgets('a slot with a spool offers its fill, the rest the AMS one', (
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

    expect(find.text('PLA · 10%'), findsOneWidget);
    expect(find.text('PETG · 66%'), findsOneWidget);
    // The shelf arriving late re-reads nothing: the status was fetched once.
    expect(printers.fetches, 1);
  });
}
