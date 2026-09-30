import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/suppliers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Filament suppliers (server #2988): the master list, a spool's assignments
/// and the per-supplier aggregate — and, on a server without them, that the
/// app is told so by the answers themselves rather than by a version number.
void main() {
  group('suppliers contract', skip: contractSkipReason, () {
    late Dio dio;
    late SuppliersRepository suppliers;
    late InventoryRepository inventory;
    late bool hasSuppliers;
    final supplierIds = <int>[];
    final spoolIds = <int>[];
    final keyIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      dio = await authenticatedDio();
      suppliers = SuppliersRepository(dio, ServerVersionService(dio));
      inventory = InventoryRepository(NativeInventorySource(dio));
      final probe = await dio.get<dynamic>(
        Endpoints.inventorySuppliers,
        options: Options(validateStatus: (_) => true),
      );
      hasSuppliers = probe.statusCode == 200;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
      for (final id in supplierIds) {
        await dio.delete<dynamic>(
          Endpoints.inventorySupplier(id),
          options: quiet,
        );
      }
      for (final id in keyIds) {
        await dio.delete<dynamic>(Endpoints.apiKeyById(id), options: quiet);
      }
    });

    Future<Spool> newSpool() async {
      final spool = await inventory.createSpool(
        SpoolDraft(material: 'PLA-Supplier-$stamp', labelWeight: 1000),
      );
      spoolIds.add(spool.id);
      return spool;
    }

    Future<Spool> reread(int spoolId) async => (await inventory.fetchSpools(
      includeArchived: true,
    )).firstWhere((s) => s.id == spoolId);

    test('an older server is recognised from its own answers', () async {
      if (hasSuppliers) {
        markTestSkipped('server has suppliers');
        return;
      }
      await newSpool();
      final spools = await inventory.fetchSpools();
      expect(spools.first.suppliers, isNull);

      suppliers.observeSpools(spools);
      expect(suppliers.capability.observedAnswer, isFalse);
      expect(await suppliers.listSuppliers(), isEmpty);
      expect(await suppliers.fetchStats(), isEmpty);
    });

    test(
      'every spool row carries the key, even with nothing assigned',
      () async {
        if (!hasSuppliers) {
          markTestSkipped('server predates suppliers');
          return;
        }
        await newSpool();
        final spools = await inventory.fetchSpools();
        expect(spools.every((s) => s.suppliers != null), isTrue);
        suppliers.observeSpools(spools);
        expect(suppliers.capability.observedAnswer, isTrue);
      },
    );

    test('master list: create, rename-collision, clear a field', () async {
      if (!hasSuppliers) {
        markTestSkipped('server predates suppliers');
        return;
      }
      final created = await suppliers.createSupplier(
        SupplierDraft(
          name: 'Extrudr $stamp',
          website: 'https://example.invalid',
          customerNumber: 'K-1',
        ),
      );
      supplierIds.add(created.id);
      expect(created.website, 'https://example.invalid');
      expect(created.spoolCount, 0);

      // Case-insensitive uniqueness is what the UI words the 409 as.
      await expectLater(
        suppliers.createSupplier(SupplierDraft(name: 'EXTRUDR $stamp')),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
        ),
      );

      final cleared = await suppliers.updateSupplier(
        created.id,
        SupplierDraft(name: 'Extrudr $stamp', customerNumber: 'K-2'),
      );
      expect(cleared.website, isNull);
      expect(cleared.customerNumber, 'K-2');

      final listed = await suppliers.listSuppliers();
      expect(listed.any((s) => s.id == created.id), isTrue);
    });

    test('a spool keeps what was written, and pins its supplier', () async {
      if (!hasSuppliers) {
        markTestSkipped('server predates suppliers');
        return;
      }
      final supplier = await suppliers.createSupplier(
        SupplierDraft(name: 'Shop A $stamp'),
      );
      final alternative = await suppliers.createSupplier(
        SupplierDraft(name: 'Shop B $stamp'),
      );
      supplierIds.addAll([supplier.id, alternative.id]);
      final spool = await newSpool();

      await suppliers.saveSpoolLinks(spool.id, [
        SpoolSupplierLink(
          supplierId: supplier.id,
          articleNumber: 'ART-1',
          quotedPricePerKg: 21.5,
          isPurchaseSource: true,
        ),
        SpoolSupplierLink(supplierId: alternative.id),
      ], backend: InventoryBackend.native);

      final links = (await reread(spool.id)).suppliers!;
      expect(links.map((l) => l.supplierId), [supplier.id, alternative.id]);
      expect(links.first.supplierName, 'Shop A $stamp');
      expect(links.first.articleNumber, 'ART-1');
      expect(links.first.quotedPricePerKg, 21.5);
      expect(links.map((l) => l.isPurchaseSource), [true, false]);

      final counted = (await suppliers.listSuppliers()).firstWhere(
        (s) => s.id == supplier.id,
      );
      expect(counted.spoolCount, 1);
      await expectLater(
        suppliers.deleteSupplier(supplier.id),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
        ),
      );

      // Only the purchase source counts in the aggregate.
      final stats = await suppliers.fetchStats();
      final row = stats.firstWhere((s) => s.supplierId == supplier.id);
      expect(row.spoolCount, 1);
      expect(row.remainingGrams, 1000);
      expect(stats.any((s) => s.supplierId == alternative.id), isFalse);

      await suppliers.saveSpoolLinks(
        spool.id,
        const [],
        backend: InventoryBackend.native,
      );
      expect((await reread(spool.id)).suppliers, isEmpty);
      await suppliers.deleteSupplier(supplier.id);
      supplierIds.remove(supplier.id);
    });

    test('two purchase sources on one spool are refused', () async {
      if (!hasSuppliers) {
        markTestSkipped('server predates suppliers');
        return;
      }
      final a = await suppliers.createSupplier(
        SupplierDraft(name: 'Twin A $stamp'),
      );
      final b = await suppliers.createSupplier(
        SupplierDraft(name: 'Twin B $stamp'),
      );
      supplierIds.addAll([a.id, b.id]);
      final spool = await newSpool();

      await expectLater(
        suppliers.saveSpoolLinks(spool.id, [
          SpoolSupplierLink(supplierId: a.id, isPurchaseSource: true),
          SpoolSupplierLink(supplierId: b.id, isPurchaseSource: true),
        ], backend: InventoryBackend.native),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 400),
        ),
      );
    });

    test('an API key reads with read-status and writes with '
        'manage-inventory', () async {
      if (!hasSuppliers) {
        markTestSkipped('server predates suppliers');
        return;
      }
      final keys = ApiKeysRepository(dio);
      Future<Dio> clientWith(Set<ApiKeyScope> scopes) async {
        final created = await keys.create(
          ApiKeyCreateInput(name: 'contract: suppliers', scopes: scopes),
        );
        keyIds.add(created.apiKey.id);
        await pollUntil(
          'key ${created.apiKey.id} to be committed',
          () async => (await keys.list()).any((k) => k.id == created.apiKey.id)
              ? true
              : null,
          within: const Duration(seconds: 10),
          every: const Duration(milliseconds: 100),
        );
        return Dio(BaseOptions(baseUrl: contractBaseUrl))
          ..options.headers['X-API-Key'] = created.key
          ..options.validateStatus = (_) => true;
      }

      final reader = await clientWith({ApiKeyScope.readStatus});
      expect(
        (await reader.get<dynamic>(Endpoints.inventorySuppliers)).statusCode,
        200,
      );
      expect(
        (await reader.post<dynamic>(
          Endpoints.inventorySuppliers,
          data: SupplierDraft(name: 'Key read $stamp').toJson(),
        )).statusCode,
        403,
      );

      final writer = await clientWith({
        ApiKeyScope.readStatus,
        ApiKeyScope.manageInventory,
      });
      final res = await writer.post<Map<String, dynamic>>(
        Endpoints.inventorySuppliers,
        data: SupplierDraft(name: 'Key write $stamp').toJson(),
      );
      expect(res.statusCode, 201);
      supplierIds.add(Supplier.fromJson(res.data!).id);
    });
  });
}
