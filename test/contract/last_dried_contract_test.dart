import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The spool's last drying (server #2863): a date typed by hand is stored as
/// the instant it names, an untouched edit leaves it alone, an explicit null
/// removes it — and, on a server without it, the app learns so from the rows
/// and the write is dropped without a refusal.
void main() {
  group('last dried contract', skip: contractSkipReason, () {
    late Dio dio;
    late InventoryRepository inventory;
    late NativeInventorySource source;
    late bool hasField;
    final spoolIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final material = 'PLA-Dried-$stamp';
    final dried = DateTime.utc(2026, 10, 6, 13, 5, 30);

    Future<Spool> create() async {
      final spool = await source.createSpool(
        SpoolDraft(material: material, brand: 'Contract', labelWeight: 1000),
      );
      spoolIds.add(spool.id);
      return spool;
    }

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      inventory = InventoryRepository(source, ServerVersionService(dio));
      final probe = await create();
      hasField = probe.lastDriedReported;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
    });

    test('an older server is recognised from its own rows', () async {
      if (hasField) {
        markTestSkipped('server records the last drying');
        return;
      }
      final spools = await source.fetchSpools();
      expect(spools.every((s) => !s.lastDriedReported), isTrue);

      inventory.observeSpools(spools);
      expect(inventory.lastDriedCapability.observedAnswer, isFalse);
    });

    test('a date the server cannot store is dropped, not refused', () async {
      if (hasField) {
        markTestSkipped('server records the last drying');
        return;
      }
      final spool = await create();
      final after = await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, lastDriedAt: dried),
      );
      expect(after.lastDriedAt, isNull);
    });

    test('the key rides on every row, null or not', () async {
      if (!hasField) {
        markTestSkipped('server predates the last drying');
        return;
      }
      final spool = await create();
      expect(spool.lastDriedAt, isNull);
      final spools = await source.fetchSpools();
      expect(spools, isNotEmpty);
      expect(spools.every((s) => s.lastDriedReported), isTrue);

      inventory.observeSpools(spools);
      expect(inventory.lastDriedCapability.observedAnswer, isTrue);
    });

    test('a date set by hand is stored as the instant it names', () async {
      if (!hasField) {
        markTestSkipped('server predates the last drying');
        return;
      }
      final spool = await create();
      final after = await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, lastDriedAt: dried),
      );
      expect(after.lastDriedAt!.isAtSameMomentAs(dried), isTrue);
      // A date by hand has no AMS cycle behind it.
      expect(after.lastDriedTemp, isNull);
      expect(after.lastDriedHours, isNull);
    });

    test('an edit that does not name the date leaves it alone', () async {
      if (!hasField) {
        markTestSkipped('server predates the last drying');
        return;
      }
      final spool = await create();
      await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, lastDriedAt: dried),
      );
      final after = await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, note: 'edited'),
      );
      expect(after.lastDriedAt!.isAtSameMomentAs(dried), isTrue);
    });

    test('an explicit null removes the record', () async {
      if (!hasField) {
        markTestSkipped('server predates the last drying');
        return;
      }
      final spool = await create();
      await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, lastDriedAt: dried),
      );
      final after = await source.updateSpool(
        spool.id,
        SpoolDraft(material: material, clears: const {'last_dried_at'}),
      );
      expect(after.lastDriedAt, isNull);
      expect(after.lastDriedReported, isTrue);
    });

    test('a time with an offset lands on the same instant', () async {
      if (!hasField) {
        markTestSkipped('server predates the last drying');
        return;
      }
      final spool = await create();
      // Raw, not through SpoolDraft: the draft converts to UTC before it sends,
      // and the offset is what the server has to cope with (`naive_utc`).
      final response = await dio.patch<Map<String, dynamic>>(
        Endpoints.inventorySpool(spool.id),
        data: {'last_dried_at': '2026-10-06T15:05:30+02:00'},
      );
      final after = Spool.fromNative(response.data!);
      expect(after.lastDriedAt!.isAtSameMomentAs(dried), isTrue);
    });
  });
}
