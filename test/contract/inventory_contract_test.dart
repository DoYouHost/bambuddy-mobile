import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/core/models/location_sensor.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/location_sensors_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('inventory contract', skip: contractSkipReason, () {
    late Dio dio;
    late InventoryRepository repo;
    late int printerId;
    final createdSpoolIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      final source = NativeInventorySource(dio);
      repo = InventoryRepository(source);
      final printers = (await dio.get<List<dynamic>>(
        '/api/v1/printers/',
      )).data!;
      printerId = (printers.first as Map<String, dynamic>)['id'] as int;
    });

    /// A spool with 102 of 1000 g left, assigned to AMS 0 slot [trayId] of
    /// the seeded printer for the rest of the test.
    Future<Spool> assignWeighed(int trayId) async {
      final spool = await repo.createSpool(
        SpoolDraft(
          material: 'PLA',
          brand: 'Contract ${DateTime.now().millisecondsSinceEpoch}',
          labelWeight: 1000,
          weightUsed: 898,
        ),
      );
      createdSpoolIds.add(spool.id);
      await repo.assignSpool(
        SpoolAssignmentDraft(
          spoolId: spool.id,
          printerId: printerId,
          amsId: 0,
          trayId: trayId,
        ),
      );
      addTearDown(() => repo.unassignSpool(printerId, 0, trayId));
      return spool;
    }

    tearDownAll(() async {
      for (final id in createdSpoolIds) {
        try {
          await repo.deleteSpool(id);
        } catch (_) {}
      }
    });

    test('GET /inventory/spools decodes into List<Spool>', () async {
      final spools = await repo.fetchSpools();
      expect(spools, isA<List<Spool>>());
      for (final s in spools) {
        expect(s.id, greaterThan(0));
        expect(s.material, isNotEmpty);
      }
    });

    test(
      'GET /inventory/catalog decodes into CoreWeightEntry catalog',
      () async {
        final catalog = await repo.fetchCoreWeights();
        expect(catalog, isA<List<CoreWeightEntry>>());
        for (final entry in catalog) {
          expect(entry.id, greaterThan(0));
          expect(entry.name, isNotEmpty);
        }
      },
    );

    test('GET /inventory/colors decodes into ColorEntry database', () async {
      final colors = await repo.fetchColors();
      expect(colors, isA<List<ColorEntry>>());
      for (final c in colors) {
        expect(c.hexColor, isNotEmpty);
      }
    });

    test(
      'GET /inventory/locations decodes into StorageLocation catalog',
      () async {
        final locations = await repo.fetchLocations();
        expect(locations, isA<List<StorageLocation>>());
        for (final loc in locations) {
          expect(loc.id, greaterThan(0));
          expect(loc.name, isNotEmpty);
        }
      },
    );

    test('GET /filament-catalog/ decodes into FilamentPreset list', () async {
      final presets = await repo.fetchFilamentPresets();
      expect(presets, isA<List<FilamentPreset>>());
      for (final p in presets) {
        expect(p.name, isNotEmpty);
      }
    });

    test(
      'GET /inventory/assignments decodes into SpoolAssignment list',
      () async {
        final assignments = await repo.fetchAssignments();
        expect(assignments, isA<List<SpoolAssignment>>());
        for (final a in assignments) {
          expect(a.printerId, greaterThan(0));
        }
      },
    );

    test(
      'spool lifecycle: create, update, archive, restore and delete',
      () async {
        final uniqueMaterial =
            'PLA-Contract-${DateTime.now().millisecondsSinceEpoch}';
        final draft = SpoolDraft(
          material: uniqueMaterial,
          colorName: 'Crimson',
          rgba: 'FF0000FF',
          brand: 'Bambu Lab',
          labelWeight: 1000,
          coreWeight: 200,
        );

        final created = await repo.createSpool(draft);
        createdSpoolIds.add(created.id);
        expect(created.id, greaterThan(0));
        expect(created.material, uniqueMaterial);

        final updatedDraft = SpoolDraft(
          material: uniqueMaterial,
          colorName: 'Ruby',
          rgba: 'EE1122FF',
          brand: 'Bambu Lab',
          labelWeight: 1000,
          coreWeight: 200,
        );
        final updated = await repo.updateSpool(created.id, updatedDraft);
        expect(updated.id, created.id);
        expect(updated.colorName, 'Ruby');

        // Archive
        await repo.archiveSpool(created.id);
        final archivedList = await repo.fetchSpools(includeArchived: true);
        expect(
          archivedList.any((s) => s.id == created.id && s.isArchived),
          isTrue,
        );

        // Restore
        await repo.restoreSpool(created.id);
        final activeList = await repo.fetchSpools(includeArchived: false);
        expect(
          activeList.any((s) => s.id == created.id && !s.isArchived),
          isTrue,
        );

        // Delete
        await repo.deleteSpool(created.id);
        createdSpoolIds.remove(created.id);
        final finalList = await repo.fetchSpools(includeArchived: true);
        expect(finalList.any((s) => s.id == created.id), isFalse);
      },
    );

    test("the printer card reads a slot's fill from its spool", () async {
      // An AMS without RFID data says 100% for any spool (issue #5); the card
      // shows the spool's own weight, as the web does.
      final spool = await assignWeighed(2);

      final container = contractContainer(dio);
      container.listen(assignedSpoolsProvider(printerId), (_, _) {});
      await container.read(inventoryBackendProvider.future);
      await container.read(inventoryProvider.future);
      final inSlot = container
          .read(assignedSpoolsProvider(printerId))
          .inAmsSlot(0, const AmsTray(id: 2, remain: 100));

      expect(inSlot?.id, spool.id);
      expect(trayFillPercent(remain: 100, spool: inSlot), 10);
    });

    test("a user's AMS label names the unit, not the slot", () async {
      // Without one the slot reads AMS-A · 2; with one the slot number has to
      // survive, which it did not while the label was taken as the whole slot.
      final spool = await assignWeighed(1);
      final before = await repo.fetchAssignments(printerId: printerId);
      expect(
        before.singleWhere((a) => a.spoolId == spool.id).slotLabel,
        'AMS-A · 2',
      );

      await dio.put<dynamic>(
        '/api/v1/printers/$printerId/ams-labels/0',
        data: {'label': 'Contract dryer'},
      );
      addTearDown(
        () => dio.delete<dynamic>('/api/v1/printers/$printerId/ams-labels/0'),
      );
      final after = await repo.fetchAssignments(printerId: printerId);
      final labelled = after.singleWhere((a) => a.spoolId == spool.id);
      expect(labelled.amsLabel, 'Contract dryer');
      expect(labelled.slotLabel, 'Contract dryer · 2');
    });

    test(
      'GET /location-ha-sensors/ decodes into LocationSensorBinding list',
      () async {
        final sensorsRepo = LocationSensorsRepository(dio);
        final bindings = await sensorsRepo.listBindings();
        expect(bindings, isA<List<LocationSensorBinding>>());
      },
    );
  });
}
