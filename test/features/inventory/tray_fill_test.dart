import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The fill a slot shows, branch for branch against the web's chain
/// (`PrintersPage.tsx`, ~5532): the Spoolman spool linked by the tray's tag,
/// the Spoolman spool assigned to the slot, the built-in inventory's spool,
/// the AMS's own `remain`.
void main() {
  const serial = '01P00A123456789';

  Future<AssignedSpools> resolve(
    InventoryBackend backend,
    InventoryState shelf,
  ) async {
    final container = ProviderContainer(
      overrides: [
        inventoryBackendOverride(backend),
        inventoryProvider.overrideWith(() => _Fixed(shelf)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(inventoryProvider.future);
    await container.read(inventoryBackendProvider.future);
    return container.read(assignedSpoolsProvider(1));
  }

  Spool weighed(int id, double used, {int label = 1000, String? tagUid}) =>
      Spool(
        id: id,
        material: 'PLA',
        labelWeight: label,
        weightUsed: used,
        tagUid: tagUid,
      );

  SpoolAssignment at(int spoolId, int amsId, int trayId, {Spool? spool}) =>
      SpoolAssignment(
        spoolId: spoolId,
        printerId: 1,
        amsId: amsId,
        trayId: trayId,
        spool: spool,
      );

  const pla = AmsTray(id: 0, trayType: 'PLA', remain: 100);

  group('built-in inventory', () {
    test('the spool in the slot outranks the AMS', () async {
      final spool = weighed(1, 898);
      final assigned = await resolve(
        InventoryBackend.native,
        InventoryState(spools: [spool], assignmentBySpool: {1: at(1, 0, 0)}),
      );

      final fill = assigned.fillOf(pla, amsId: 0, trayId: 0);
      expect(fill.percent, 10);
      expect(fill.spool, spool);
    });

    test('without a spool the AMS answers, if it has a reading', () async {
      final assigned = await resolve(
        InventoryBackend.native,
        const InventoryState(),
      );

      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).percent, 100);
      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).spool, isNull);
      const unread = AmsTray(id: 0, trayType: 'PLA', remain: -1);
      expect(assigned.fillOf(unread, amsId: 0, trayId: 0).percent, isNull);
      // An empty slot: no type, so no reading either (`hasFillLevel`).
      const empty = AmsTray(id: 0, remain: 0);
      expect(assigned.fillOf(empty, amsId: 0, trayId: 0).percent, isNull);
    });

    test('a spool at 0% yields to an AMS that still sees filament', () async {
      // #676: a stale weight_used.
      final assigned = await resolve(
        InventoryBackend.native,
        InventoryState(
          spools: [weighed(1, 1000), weighed(2, 1000)],
          assignmentBySpool: {1: at(1, 0, 0), 2: at(2, 0, 1)},
        ),
      );

      final stale = assigned.fillOf(
        const AmsTray(id: 0, trayType: 'PLA', remain: 66),
        amsId: 0,
        trayId: 0,
      );
      expect((stale.percent, stale.spool), (66, null));
      final empty = assigned.fillOf(
        const AmsTray(id: 1, trayType: 'PLA', remain: 0),
        amsId: 0,
        trayId: 1,
      );
      expect(empty.percent, 0);
      expect(empty.spool?.id, 2);
    });

    test('a spool of unknown size leaves it to the AMS', () async {
      final assigned = await resolve(
        InventoryBackend.native,
        InventoryState(
          spools: [weighed(1, 0, label: 0)],
          assignmentBySpool: {1: at(1, 0, 0)},
        ),
      );

      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).percent, 100);
    });

    test(
      'the external holder is unit 255 by side, AMS fill included',
      () async {
        final spool = weighed(1, 250, label: 500);
        final assigned = await resolve(
          InventoryBackend.native,
          InventoryState(
            spools: [spool],
            assignmentBySpool: {1: at(1, 255, 1)},
          ),
        );

        const right = AmsTray(id: 255, trayType: 'PLA', remain: 0);
        expect(assigned.fillOf(right, amsId: 255, trayId: 1).percent, 50);
        const left = AmsTray(id: 254, trayType: 'TPU', remain: 0);
        expect(assigned.fillOf(left, amsId: 255, trayId: 0).percent, 0);
      },
    );

    test('rounds as the web does', () async {
      final assigned = await resolve(
        InventoryBackend.native,
        InventoryState(
          spools: [weighed(1, 995), weighed(2, 996)],
          assignmentBySpool: {1: at(1, 0, 0), 2: at(2, 0, 1)},
        ),
      );

      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).percent, 1);
      const second = AmsTray(id: 1, trayType: 'PLA', remain: 0);
      expect(assigned.fillOf(second, amsId: 0, trayId: 1).percent, 0);
    });
  });

  group('Spoolman', () {
    test('the spool linked by the tag outranks the one in the slot', () async {
      final linked = weighed(1, 300, tagUid: 'A1B2C3D4E5F60708');
      final inSlot = weighed(2, 898);
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(
          spools: [linked, inSlot],
          assignmentBySpool: {2: at(2, 0, 0)},
        ),
      );

      const tagged = AmsTray(
        id: 0,
        trayType: 'PLA',
        remain: 100,
        tagUid: 'A1B2C3D4E5F60708',
      );
      final fill = assigned.fillOf(tagged, amsId: 0, trayId: 0);
      expect((fill.percent, fill.spool), (70, linked));
      // No tag on the tray: the slot's spool.
      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).spool, inSlot);
    });

    test('a tray without a tag is looked up by its fallback tag', () async {
      final linked = weighed(1, 600, tagUid: fallbackSpoolTag(serial, 0, 0));
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(spools: [linked]),
      );

      final fill = assigned.fillOf(pla, amsId: 0, trayId: 0, serial: serial);
      expect((fill.percent, fill.spool), (40, linked));
      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).spool, isNull);
    });

    test('only the first tag present is looked up', () async {
      // The web keys its linked map by `tray_uuid || tag_uid || fallback`.
      final byUid = weighed(1, 300, tagUid: 'A1B2C3D4E5F60708');
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(spools: [byUid]),
      );

      const both = AmsTray(
        id: 0,
        trayType: 'PLA',
        remain: 100,
        tagUid: 'A1B2C3D4E5F60708',
        trayUuid: '0123456789ABCDEF0123456789ABCDEF',
      );
      expect(assigned.fillOf(both, amsId: 0, trayId: 0).spool, isNull);
    });

    test('a linked spool with nothing left gives way to the slot', () async {
      // `getSpoolmanFillLevel` reads remaining_weight 0 as no answer.
      final spent = weighed(1, 1000, tagUid: 'A1B2C3D4E5F60708');
      final inSlot = weighed(2, 500);
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(
          spools: [spent, inSlot],
          assignmentBySpool: {2: at(2, 0, 0)},
        ),
      );

      const tagged = AmsTray(
        id: 0,
        trayType: 'PLA',
        remain: 100,
        tagUid: 'A1B2C3D4E5F60708',
      );
      expect(assigned.fillOf(tagged, amsId: 0, trayId: 0).spool, inSlot);
    });

    test('the built-in inventory answers after Spoolman', () async {
      final builtIn = weighed(9, 750);
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(builtInSlots: [at(9, 0, 0, spool: builtIn)]),
      );

      final fill = assigned.fillOf(pla, amsId: 0, trayId: 0);
      expect((fill.percent, fill.spool), (25, builtIn));
    });

    test('a Spoolman slot spool at 0% stays at 0%', () async {
      // #676 is the built-in inventory's rule only.
      final assigned = await resolve(
        InventoryBackend.spoolman,
        InventoryState(
          spools: [weighed(2, 1000)],
          assignmentBySpool: {2: at(2, 0, 0)},
        ),
      );

      expect(assigned.fillOf(pla, amsId: 0, trayId: 0).percent, 0);
    });
  });
}

class _Fixed extends InventoryNotifier {
  _Fixed(this._state);

  final InventoryState _state;

  @override
  Future<InventoryState> build() async => _state;
}
