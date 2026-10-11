import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> ids(
    List<Spool> spools,
    InventorySort sort, {
    bool descending = true,
  }) => sortSpools(
    spools,
    sort,
    descending: descending,
  ).map((s) => s.id).toList();

  final a = Spool(
    id: 3,
    material: 'PLA',
    weightUsed: 300,
    weightUsedBaseline: 100,
    costPerKg: 20,
    createdAt: DateTime.utc(2026, 1, 2),
  );
  final b = Spool(
    id: 1,
    material: 'PLA',
    weightUsed: 400,
    weightUsedBaseline: 350,
    costPerKg: 30,
    createdAt: DateTime.utc(2026, 3, 1),
  );
  const unknown = Spool(id: 2, material: 'PLA', weightUsed: 50);
  final standard = [a, unknown, b];

  test('standard keeps the order the list was loaded in', () {
    expect(ids(standard, InventorySort.standard), [3, 2, 1]);
  });

  test('usage sorts by lifetime use, not the resettable counter', () {
    // By the counter a (200) would lead b (50); in total b (400) leads a (300).
    expect(ids(standard, InventorySort.usage), [1, 3, 2]);
    expect(ids(standard, InventorySort.usage, descending: false), [2, 3, 1]);
  });

  test('an unknown price or added date goes last in both directions', () {
    expect(ids(standard, InventorySort.price), [1, 3, 2]);
    expect(ids(standard, InventorySort.price, descending: false), [3, 1, 2]);
    expect(ids(standard, InventorySort.added), [1, 3, 2]);
    expect(ids(standard, InventorySort.added, descending: false), [3, 1, 2]);
  });

  test('id sorts in both directions', () {
    expect(ids(standard, InventorySort.id), [3, 2, 1]);
    expect(ids(standard, InventorySort.id, descending: false), [1, 2, 3]);
  });

  test('standard ignores the direction', () {
    expect(ids(standard, InventorySort.standard, descending: false), [3, 2, 1]);
  });

  test('clearing filters keeps the sort and its direction', () {
    const filters = InventoryFilters(
      lowStockOnly: true,
      sort: InventorySort.price,
      descending: false,
    );
    final cleared = filters.cleared();
    expect(cleared.activeCount, 0);
    expect(cleared.sort, InventorySort.price);
    expect(cleared.descending, isFalse);
  });

  test('a chosen sort does not count as an active filter', () {
    const filters = InventoryFilters(
      sort: InventorySort.price,
      descending: false,
    );
    expect(filters.activeCount, 0);
  });

  group('createdAt', () {
    test('native reads created_at as UTC without a zone suffix', () {
      final s = Spool.fromNative({
        'id': 1,
        'material': 'PLA',
        'created_at': '2026-03-01T10:00:00',
      });
      expect(s.createdAt?.toUtc(), DateTime.utc(2026, 3, 1, 10));
    });

    test('Spoolman reads the created_at the backend maps it to', () {
      final s = Spool.fromSpoolman({
        'id': 1,
        'created_at': '2026-03-01T10:00:00Z',
      });
      expect(s.createdAt?.toUtc(), DateTime.utc(2026, 3, 1, 10));
      expect(Spool.fromSpoolman({'id': 2}).createdAt, isNull);
    });
  });
}
