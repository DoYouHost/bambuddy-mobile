import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('inventory contract', skip: contractSkipReason, () {
    late Dio dio;
    late InventoryRepository repo;
    final createdSpoolIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      final source = NativeInventorySource(dio);
      repo = InventoryRepository(source);
    });

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

    test('GET /inventory/catalog decodes into CoreWeightEntry catalog', () async {
      final catalog = await repo.fetchCoreWeights();
      expect(catalog, isA<List<CoreWeightEntry>>());
      for (final entry in catalog) {
        expect(entry.id, greaterThan(0));
        expect(entry.name, isNotEmpty);
      }
    });

    test('GET /inventory/colors decodes into ColorEntry database', () async {
      final colors = await repo.fetchColors();
      expect(colors, isA<List<ColorEntry>>());
      for (final c in colors) {
        expect(c.hexColor, isNotEmpty);
      }
    });

    test('GET /inventory/locations decodes into StorageLocation catalog', () async {
      final locations = await repo.fetchLocations();
      expect(locations, isA<List<StorageLocation>>());
      for (final loc in locations) {
        expect(loc.id, greaterThan(0));
        expect(loc.name, isNotEmpty);
      }
    });

    test('GET /filament-catalog/ decodes into FilamentPreset list', () async {
      final presets = await repo.fetchFilamentPresets();
      expect(presets, isA<List<FilamentPreset>>());
      for (final p in presets) {
        expect(p.name, isNotEmpty);
      }
    });

    test('GET /inventory/assignments decodes into SpoolAssignment list', () async {
      final assignments = await repo.fetchAssignments();
      expect(assignments, isA<List<SpoolAssignment>>());
      for (final a in assignments) {
        expect(a.printerId, greaterThan(0));
      }
    });

    test('spool lifecycle: create, update, archive, restore and delete', () async {
      final uniqueMaterial = 'PLA-Contract-${DateTime.now().millisecondsSinceEpoch}';
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
      expect(archivedList.any((s) => s.id == created.id && s.isArchived), isTrue);

      // Restore
      await repo.restoreSpool(created.id);
      final activeList = await repo.fetchSpools(includeArchived: false);
      expect(activeList.any((s) => s.id == created.id && !s.isArchived), isTrue);

      // Delete
      await repo.deleteSpool(created.id);
      createdSpoolIds.remove(created.id);
      final finalList = await repo.fetchSpools(includeArchived: true);
      expect(finalList.any((s) => s.id == created.id), isFalse);
    });
  });
}
