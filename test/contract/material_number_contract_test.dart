import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The spool material number (server #2870): written trimmed, cleared by a
/// blank, inherited by a new spool of the same product, grouped by the stats
/// route — and, on a server without it, that the app learns so from the rows.
void main() {
  group('material number contract', skip: contractSkipReason, () {
    late Dio dio;
    late InventoryRepository inventory;
    late NativeInventorySource source;
    late bool hasNumber;
    final spoolIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final material = 'PLA-MatNo-$stamp';

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      inventory = InventoryRepository(source, ServerVersionService(dio));
      final probe = await source.createSpool(
        SpoolDraft(material: material, labelWeight: 1000),
      );
      spoolIds.add(probe.id);
      hasNumber = probe.materialNumberReported;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
    });

    Future<Spool> create(String? number) async {
      final spool = await source.createSpool(
        SpoolDraft(
          material: material,
          brand: 'Contract',
          colorName: 'Teal',
          labelWeight: 1000,
          materialNumber: number,
        ),
      );
      spoolIds.add(spool.id);
      return spool;
    }

    test('an older server is recognised from its own rows', () async {
      if (hasNumber) {
        markTestSkipped('server has the material number');
        return;
      }
      final spools = await source.fetchSpools();
      expect(spools.every((s) => !s.materialNumberReported), isTrue);

      inventory.observeSpools(spools);
      expect(inventory.materialNumberCapability.observedAnswer, isFalse);
      expect(await inventory.fetchMaterialNumberStats(), isEmpty);
    });

    test('a write the server cannot store is dropped, not refused', () async {
      if (hasNumber) {
        markTestSkipped('server has the material number');
        return;
      }
      final spool = await create('15');
      expect(spool.materialNumber, isNull);
    });

    test('the key rides on every row, null or not', () async {
      if (!hasNumber) {
        markTestSkipped('server predates the material number');
        return;
      }
      final spools = await source.fetchSpools();
      expect(spools, isNotEmpty);
      expect(spools.every((s) => s.materialNumberReported), isTrue);

      inventory.observeSpools(spools);
      expect(inventory.materialNumberCapability.observedAnswer, isTrue);
    });

    test('a typed number is trimmed and a blank one clears it', () async {
      if (!hasNumber) {
        markTestSkipped('server predates the material number');
        return;
      }
      final spool = await create('  MN-$stamp ');
      expect(spool.materialNumber, 'MN-$stamp');

      final cleared = await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, materialNumber: ''),
      );
      expect(cleared.materialNumber, isNull);
    });

    test('a new spool of a numbered product inherits the number', () async {
      if (!hasNumber) {
        markTestSkipped('server predates the material number');
        return;
      }
      final first = await create('INH-$stamp');
      expect(first.materialNumber, 'INH-$stamp');

      final second = await create(null);
      expect(second.materialNumber, 'INH-$stamp');
    });

    test('a bulk edit sets it on every selected spool', () async {
      if (!hasNumber) {
        markTestSkipped('server predates the material number');
        return;
      }
      final a = await create(null);
      final b = await create(null);
      final outcome = await source.bulkUpdate([
        a.id,
        b.id,
      ], SpoolBulkPatch(materialNumber: 'BULK-$stamp'));
      expect(outcome.ok, 2);

      final after = await source.fetchSpools();
      for (final id in [a.id, b.id]) {
        expect(
          after.firstWhere((s) => s.id == id).materialNumber,
          'BULK-$stamp',
        );
      }
    });

    test('the stats group spools by number', () async {
      if (!hasNumber) {
        markTestSkipped('server predates the material number');
        return;
      }
      final number = 'STAT-$stamp';
      await create(number);
      await create(number);

      final rows = await inventory.fetchMaterialNumberStats();
      final row = rows.firstWhere((r) => r.materialNumber == number);
      expect(row.spoolCount, 2);
      expect(row.remainingGrams, 2000);
      expect(row.consumedGrams, 0);
      expect(inventory.materialNumberCapability.observedAnswer, isTrue);
    });
  });
}
