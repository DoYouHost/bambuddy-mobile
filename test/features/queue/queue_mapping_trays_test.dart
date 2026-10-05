import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The fill the slot picker shows while mapping a print — the same reading as
/// the printer card, so the slot a user picks by "how much is left" is not
/// the one the AMS calls 100% for want of an RFID tag (issue #5).
class _Printers extends PrintersRepository {
  _Printers() : super(Dio());

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async =>
      const PrinterStatus(
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

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [Spool(id: 1, material: 'PLA', labelWeight: 1000, weightUsed: 898)],
    assignmentBySpool: {
      1: SpoolAssignment(spoolId: 1, printerId: 1, amsId: 0, trayId: 0),
    },
  );
}

void main() {
  test('a slot with a spool offers its fill, the rest the AMS one', () async {
    final container = ProviderContainer(
      overrides: [
        printersRepositoryProvider.overrideWithValue(_Printers()),
        inventoryBackendOverride(),
        inventoryProvider.overrideWith(_Shelf.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(inventoryProvider.future);

    final trays = await container.read(printerTraysProvider(1).future);

    expect([for (final t in trays) t.fill], [10, 66]);
  });
}
