import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Which spool a slot shows. In Spoolman mode the server binds a tagged spool
/// by its tag (`spoolman.py::sync_ams_tray`) and charges usage to it before any
/// slot assignment, so that is the order the card reads them in.
void main() {
  Future<AssignedSpools> resolve(InventoryBackend backend) async {
    final container = ProviderContainer(
      overrides: [
        inventoryBackendOverride(backend),
        inventoryProvider.overrideWith(_Shelf.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(inventoryProvider.future);
    await container.read(inventoryBackendProvider.future);
    return container.read(assignedSpoolsProvider(1));
  }

  group('Spoolman mode', () {
    test('a tray reading a tag shows the spool bound to it', () async {
      final assigned = await resolve(InventoryBackend.spoolman);

      expect(
        assigned.boundByTag(const AmsTray(tagUid: 'A1B2C3D4E5F60708')),
        tagged,
      );
      expect(
        assigned.boundByTag(
          const AmsTray(trayUuid: '0123456789abcdef0123456789abcdef'),
        ),
        byUuid,
      );
    });

    test('a spool the linked map leaves out is not bound', () async {
      // An archived spool still carries its tag on the shelf, but
      // `/spoolman/spools/linked` lists no archived spool.
      final assigned = await resolve(InventoryBackend.spoolman);
      const tray = AmsTray(tagUid: 'B1B2C3D4E5F60708');

      expect(assigned.tagBinds(tray), isTrue);
      expect(assigned.boundByTag(tray), isNull);
    });

    test('a tag binds even when no spool carries it yet', () async {
      // auto_add_unknown_rfid off: the web still offers no assign there.
      final assigned = await resolve(InventoryBackend.spoolman);
      const unknown = AmsTray(tagUid: 'FFFFFFFFFFFFFFFF');

      expect(assigned.tagBinds(unknown), isTrue);
      expect(assigned.boundByTag(unknown), isNull);
    });

    test('an unread tag of zeros binds nothing', () async {
      final assigned = await resolve(InventoryBackend.spoolman);
      const unread = AmsTray(
        tagUid: '0000000000000000',
        trayUuid: '00000000000000000000000000000000',
      );

      expect(assigned.tagBinds(unread), isFalse);
      expect(assigned.tagBinds(const AmsTray()), isFalse);
    });

    test('the slot assignment still answers an untagged tray', () async {
      final assigned = await resolve(InventoryBackend.spoolman);

      expect(assigned.boundByTag(const AmsTray()), isNull);
      expect(assigned.forAmsSlot(0, 0), pinned);
    });
  });

  test('the built-in inventory binds nothing by tag', () async {
    final assigned = await resolve(InventoryBackend.native);
    const tray = AmsTray(tagUid: 'A1B2C3D4E5F60708');

    expect(assigned.tagBinds(tray), isFalse);
    expect(assigned.boundByTag(tray), isNull);
  });
}

const tagged = Spool(
  id: 21,
  material: 'PLA',
  tagUid: 'a1b2c3d4e5f60708',
  labelWeight: 1000,
);
const byUuid = Spool(
  id: 22,
  material: 'PETG',
  trayUuid: '0123456789ABCDEF0123456789ABCDEF',
);
const pinned = Spool(id: 7, material: 'ABS');
// On the shelf with its tag, as an archived spool is, but not linked.
const unlinked = Spool(id: 23, material: 'PLA', tagUid: 'b1b2c3d4e5f60708');

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => InventoryState(
    spools: [tagged, byUuid, pinned, unlinked],
    assignments: [
      SpoolAssignment(spoolId: 7, printerId: 1, amsId: 0, trayId: 0),
    ],
    // `/spoolman/spools/linked`, keyed by the tag in upper case.
    linkedTags: const {
      'A1B2C3D4E5F60708': LinkedSpool(id: 21),
      '0123456789ABCDEF0123456789ABCDEF': LinkedSpool(id: 22),
    },
  );
}
