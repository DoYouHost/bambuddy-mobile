import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/features/stats/stats_sections.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../inventory/fake_suppliers.dart';

const _rows = [
  SupplierStats(
    supplierId: 3,
    supplierName: 'Extrudr',
    spoolCount: 2,
    remainingGrams: 1500,
    consumedGrams: 820,
    cost: 19.4,
  ),
  SupplierStats(supplierId: 5, supplierName: 'Filamentworld', spoolCount: 1),
];

void main() {
  List<Override> overridesFor(
    FakeSuppliers suppliers, {
    InventoryBackend backend = InventoryBackend.native,
  }) => [
    noServerProfileOverride,
    suppliersRepositoryProvider.overrideWithValue(suppliers),
    inventoryBackendOverride(backend),
  ];

  group('supplierStatsProvider', () {
    Future<List<SupplierStats>> read(
      FakeSuppliers suppliers, {
      InventoryBackend backend = InventoryBackend.native,
      StatsRange range = StatsRange.allTime,
    }) async {
      final container = ProviderContainer(
        overrides: overridesFor(suppliers, backend: backend),
      );
      addTearDown(container.dispose);
      container.read(statsFilterProvider.notifier).setRange(range);
      final sub = container.listen(supplierStatsProvider, (_, _) {});
      addTearDown(sub.close);
      return container.read(supplierStatsProvider.future);
    }

    test('asks for the screen\'s range as calendar days', () async {
      final suppliers = FakeSuppliers(stats: _rows);
      final rows = await read(suppliers, range: StatsRange.last7Days);

      expect(rows, hasLength(2));
      final (from, to) = suppliers.statsAsked.single;
      final today = DateTime.now();
      expect(to, DateTime(today.year, today.month, today.day));
      expect(to!.difference(from!).inDays, 6);
    });

    test('all time sends no range at all', () async {
      final suppliers = FakeSuppliers(stats: _rows);
      await read(suppliers);
      expect(suppliers.statsAsked.single, (null, null));
    });

    test('never asks in Spoolman mode, where the aggregate is empty', () async {
      final suppliers = FakeSuppliers(stats: _rows);
      final rows = await read(suppliers, backend: InventoryBackend.spoolman);
      expect(rows, isEmpty);
      expect(suppliers.statsAsked, isEmpty);
    });

    test('never asks a server without suppliers', () async {
      final suppliers = FakeSuppliers(stats: _rows, supported: false);
      expect(await read(suppliers), isEmpty);
      expect(suppliers.statsAsked, isEmpty);
    });
  });

  group('SupplierStatsCard', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('pl'));
    });

    Future<void> pumpCard(WidgetTester tester, List<Override> overrides) =>
        pumpPhone(
          tester,
          const Scaffold(
            body: SingleChildScrollView(child: SupplierStatsCard()),
          ),
          overrides: overrides,
        ).then((_) => settle(tester));

    testWidgets('one bar per supplier, stock and spend under it', (
      tester,
    ) async {
      await pumpCard(tester, overridesFor(FakeSuppliers(stats: _rows)));

      expect(find.text(l10n.statsBySupplier), findsOneWidget);
      expect(find.text('Extrudr'), findsOneWidget);
      expect(find.text('820 g'), findsOneWidget);
      expect(
        find.text(
          l10n.statsSupplierDetail(
            l10n.inventorySpoolCount(2),
            '1.50 kg',
            '19.40',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Filamentworld'), findsOneWidget);
    });

    testWidgets('nothing at all when nothing was bought anywhere', (
      tester,
    ) async {
      await pumpCard(tester, overridesFor(FakeSuppliers()));
      expect(find.text(l10n.statsBySupplier), findsNothing);
    });

    testWidgets('a failed read says so instead of passing for empty', (
      tester,
    ) async {
      await pumpCard(tester, [
        supplierStatsProvider.overrideWith(
          (_) => throw const ApiException(
            AppErrorCode.badResponse,
            statusCode: 500,
          ),
        ),
      ]);
      expect(find.text(l10n.statsBySupplierFailed), findsOneWidget);
    });
  });
}
