import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'fake_suppliers.dart';

/// Suppliers in the mass edit. The server has no bulk route for them, so the
/// app replaces each spool's list with its own merged one — and a replace built
/// from the wrong starting list deletes what the spool had.
class _FakeSource implements SpoolInventorySource {
  _FakeSource(
    this.spools, {
    this.notFound = const [],
    this.errorIds = const [],
  });

  final List<Spool> spools;
  final List<int> notFound;

  /// Spoolman's per-spool `errors`, which come without a `not_found` list.
  final List<int> errorIds;
  final List<SpoolBulkPatch> patches = [];

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async => [
    ...spools,
  ];

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async =>
      const [];

  @override
  Future<BulkOutcome> bulkUpdate(
    List<int> spoolIds,
    SpoolBulkPatch patch,
  ) async {
    patches.add(patch);
    final failed = notFound.length + errorIds.length;
    return BulkOutcome(
      ok: spoolIds.length - failed,
      failed: failed,
      notFound: notFound,
      errorIds: errorIds,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fails the replace of the listed spools with the given error.
class _SelectiveSuppliers extends FakeSuppliers {
  _SelectiveSuppliers(this.failures);

  final Map<int, Object> failures;

  @override
  Future<void> saveSpoolLinks(
    int spoolId,
    List<SpoolSupplierLink> links, {
    required InventoryBackend backend,
  }) async {
    if (failures[spoolId] case final failure?) throw failure;
    return super.saveSpoolLinks(spoolId, links, backend: backend);
  }
}

const _shop = SpoolSupplierLink(
  supplierId: 1,
  supplierName: 'Shop',
  articleNumber: 'A-1',
  quotedPricePerKg: 20,
  isPurchaseSource: true,
);
const _other = SpoolSupplierLink(supplierId: 2, supplierName: 'Other');

void main() {
  group('mergeSupplierLinks', () {
    test('adds a new supplier and keeps the ones already there', () {
      final merged = mergeSupplierLinks([_shop], [_other]);
      expect(merged.map((l) => l.supplierId), [1, 2]);
      expect(merged.first.isPurchaseSource, isTrue);
      expect(merged.last.isPurchaseSource, isFalse);
    });

    test('an empty spool just gets the added list', () {
      final merged = mergeSupplierLinks(const [], [_other]);
      expect(merged.single.supplierId, 2);
    });

    test('nothing added leaves the list as it was', () {
      final merged = mergeSupplierLinks([_shop, _other], const []);
      expect(merged.map((l) => l.toJson()), [_shop.toJson(), _other.toJson()]);
    });

    test('a supplier already on the spool keeps what the edit left blank', () {
      final merged = mergeSupplierLinks(
        [_shop],
        [const SpoolSupplierLink(supplierId: 1, quotedPricePerKg: 25)],
      );
      expect(merged.single.articleNumber, 'A-1');
      expect(merged.single.quotedPricePerKg, 25);
      expect(merged.single.supplierName, 'Shop');
      // Not marked in the edit, so the spool's own mark stays.
      expect(merged.single.isPurchaseSource, isTrue);
    });

    test('a purchase source in the edit takes the flag from the old one', () {
      final merged = mergeSupplierLinks(
        [_shop],
        [
          const SpoolSupplierLink(
            supplierId: 2,
            supplierName: 'Other',
            isPurchaseSource: true,
          ),
        ],
      );
      expect(merged.where((l) => l.isPurchaseSource).single.supplierId, 2);
    });
  });

  group('bulkUpdateSpools with suppliers', () {
    Future<(ProviderContainer, _FakeSource, FakeSuppliers)> harness(
      List<Spool> spools, {
      List<int> notFound = const [],
      List<int> errorIds = const [],
      FakeSuppliers? suppliers,
    }) async {
      final source = _FakeSource(
        spools,
        notFound: notFound,
        errorIds: errorIds,
      );
      suppliers ??= FakeSuppliers();
      final container = ProviderContainer(
        overrides: [
          fakeServerProfileOverride(),
          inventoryBackendOverride(),
          inventorySourceProvider.overrideWith((ref) => source),
          suppliersRepositoryProvider.overrideWithValue(suppliers),
        ],
      );
      addTearDown(container.dispose);
      container.listen(inventoryProvider, (_, _) {});
      await container.read(inventoryProvider.future);
      return (container, source, suppliers);
    }

    test('suppliers alone send no patch and merge into each spool', () async {
      final (container, source, suppliers) = await harness([
        const Spool(id: 1, material: 'PLA', suppliers: [_shop]),
        const Spool(id: 2, material: 'PLA', suppliers: []),
      ]);

      final outcome = await container
          .read(inventoryProvider.notifier)
          .bulkUpdateSpools(
            [1, 2],
            const SpoolBulkPatch(),
            addSuppliers: [_other],
          );

      expect(source.patches, isEmpty);
      expect(outcome.ok, 2);
      expect(outcome.failed, 0);
      final byId = {
        for (final (id, links, _) in suppliers.savedLinks) id: links,
      };
      expect(byId[1]!.map((l) => l.supplierId), [1, 2]);
      expect(byId[2]!.map((l) => l.supplierId), [2]);
    });

    test('a spool whose list never arrived is failed, not wiped', () async {
      final (container, _, suppliers) = await harness([
        const Spool(id: 1, material: 'PLA', suppliers: []),
        const Spool(id: 2, material: 'PLA'),
      ]);

      final outcome = await container
          .read(inventoryProvider.notifier)
          .bulkUpdateSpools(
            [1, 2],
            const SpoolBulkPatch(),
            addSuppliers: [_other],
          );

      expect(suppliers.savedLinks.map((s) => s.$1), [1]);
      expect(outcome.ok, 1);
      expect(outcome.failed, 1);
    });

    test('a refusal on every spool surfaces instead of a zero tally', () async {
      final (container, _, suppliers) = await harness([
        const Spool(id: 1, material: 'PLA', suppliers: []),
      ]);
      suppliers.failNextWrite = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 403,
      );

      expect(
        container
            .read(inventoryProvider.notifier)
            .bulkUpdateSpools(
              [1],
              const SpoolBulkPatch(),
              addSuppliers: [_other],
            ),
        throwsA(isA<AppApiException>()),
      );
    });

    test(
      'with a patch, unknown ids skip the replace and the tallies add up',
      () async {
        final (container, source, suppliers) = await harness(
          [
            const Spool(id: 1, material: 'PLA', suppliers: []),
            const Spool(id: 2, material: 'PLA', suppliers: []),
          ],
          notFound: [2],
        );

        final outcome = await container
            .read(inventoryProvider.notifier)
            .bulkUpdateSpools(
              [1, 2],
              const SpoolBulkPatch(note: 'restocked'),
              addSuppliers: [_other],
            );

        expect(source.patches, hasLength(1));
        expect(suppliers.savedLinks.map((s) => s.$1), [1]);
        expect(outcome.ok, 1);
        expect(outcome.failed, 1);
        expect(outcome.notFound, [2]);
      },
    );

    test(
      'a spool the Spoolman patch failed is neither written nor counted twice',
      () async {
        final (container, _, suppliers) = await harness(
          [
            const Spool(id: 1, material: 'PLA', suppliers: []),
            const Spool(id: 2, material: 'PLA', suppliers: []),
          ],
          errorIds: [2],
        );

        final outcome = await container
            .read(inventoryProvider.notifier)
            .bulkUpdateSpools(
              [1, 2],
              const SpoolBulkPatch(note: 'restocked'),
              addSuppliers: [_other],
            );

        expect(suppliers.savedLinks.map((s) => s.$1), [1]);
        expect(outcome.ok, 1);
        expect(outcome.failed, 1);
      },
    );

    test('once the patch landed, refused replaces close on a tally', () async {
      final (container, source, suppliers) = await harness([
        const Spool(id: 1, material: 'PLA', suppliers: []),
      ]);
      suppliers.failNextWrite = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 404,
      );

      final outcome = await container
          .read(inventoryProvider.notifier)
          .bulkUpdateSpools(
            [1],
            const SpoolBulkPatch(note: 'restocked'),
            addSuppliers: [_other],
          );

      expect(source.patches, hasLength(1));
      expect(outcome.ok, 0);
      expect(outcome.failed, 1);
    });

    test(
      'a refusal still surfaces when another write failed otherwise',
      () async {
        final (container, _, _) = await harness(
          [
            const Spool(id: 1, material: 'PLA', suppliers: []),
            const Spool(id: 2, material: 'PLA', suppliers: []),
          ],
          suppliers: _SelectiveSuppliers({
            1: const ApiException(AppErrorCode.badResponse, statusCode: 404),
            2: StateError('socket closed'),
          }),
        );

        await expectLater(
          container
              .read(inventoryProvider.notifier)
              .bulkUpdateSpools(
                [1, 2],
                const SpoolBulkPatch(),
                addSuppliers: [_other],
              ),
          throwsA(isA<AppApiException>()),
        );
      },
    );
  });
}
