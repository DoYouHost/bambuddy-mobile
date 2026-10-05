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

    test(
      'a slot assignment outranks the tag, which answers elsewhere',
      () async {
        final assigned = await resolve(InventoryBackend.spoolman);
        const tray = AmsTray(id: 0, tagUid: 'A1B2C3D4E5F60708');

        expect(assigned.inAmsSlot(0, tray), pinned);
        expect(assigned.inAmsSlot(1, tray), tagged);
        expect(assigned.inAmsSlot(1, const AmsTray(id: 0)), isNull);
      },
    );
  });

  test('the built-in inventory binds nothing by tag', () async {
    final assigned = await resolve(InventoryBackend.native);
    const tray = AmsTray(tagUid: 'A1B2C3D4E5F60708');

    expect(assigned.tagBinds(tray), isFalse);
    expect(assigned.boundByTag(tray), isNull);
  });

  group('trayFillPercent', () {
    Spool weighed(double used, {int label = 1000}) =>
        Spool(id: 1, material: 'PLA', labelWeight: label, weightUsed: used);

    test('a spool outranks the AMS, which reads 100% without RFID', () {
      expect(trayFillPercent(remain: 100, spool: weighed(898)), 10);
    });

    test('without a spool the AMS answers, unless it has no reading', () {
      expect(trayFillPercent(remain: 66), 66);
      expect(trayFillPercent(remain: -1), isNull);
      expect(trayFillPercent(), isNull);
    });

    test('a spool of unknown size leaves it to the AMS', () {
      expect(trayFillPercent(remain: 40, spool: weighed(0, label: 0)), 40);
    });

    test('an empty spool yields to an AMS that still sees filament', () {
      // A stale weight_used, server #676.
      expect(trayFillPercent(remain: 40, spool: weighed(1000)), 40);
      expect(trayFillPercent(remain: 0, spool: weighed(1000)), 0);
      expect(trayFillPercent(spool: weighed(1200)), 0);
    });

    test('rounds as the web does', () {
      expect(trayFillPercent(spool: weighed(995)), 1);
      expect(trayFillPercent(spool: weighed(996)), 0);
    });
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

class _Shelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [tagged, byUuid, pinned],
    assignmentBySpool: {
      7: SpoolAssignment(spoolId: 7, printerId: 1, amsId: 0, trayId: 0),
    },
  );
}
