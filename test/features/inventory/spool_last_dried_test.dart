import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The last drying (#2863) on the shelf: a mark on the tile that costs the
/// list no height, and the run's figures in the detail sheet.
class _Shelf extends InventoryNotifier {
  _Shelf(this.spools);

  final List<Spool> spools;

  @override
  Future<InventoryState> build() async => InventoryState(spools: spools);

  @override
  Future<void> refresh({bool askBackend = false}) async {}
}

final _dried = DateTime.utc(2026, 10, 6, 12);

Spool _spool(int id, String brand, {DateTime? at, int? temp, double? hours}) =>
    Spool(
      id: id,
      material: 'PLA',
      brand: brand,
      lastDriedAt: at,
      lastDriedTemp: temp,
      lastDriedHours: hours,
      lastDriedReported: true,
    );

void main() {
  group('lastDriedRun', () {
    test('names the temperature and the hours of the run', () {
      expect(
        lastDriedRun(_spool(1, 'A', temp: 55, hours: 7.5)),
        '55 °C · 7.5 h',
      );
    });

    test('whole hours drop their decimal', () {
      expect(lastDriedRun(_spool(1, 'A', temp: 50, hours: 8)), '50 °C · 8 h');
    });

    test('rounds to one decimal like the web', () {
      expect(lastDriedRun(_spool(1, 'A', hours: 7.54)), '7.5 h');
      expect(lastDriedRun(_spool(1, 'A', hours: 7.96)), '8 h');
    });

    test('says nothing for a date set by hand', () {
      expect(lastDriedRun(_spool(1, 'A', at: _dried)), isNull);
    });

    test('a run without a temperature still shows its hours', () {
      expect(lastDriedRun(_spool(1, 'A', hours: 4)), '4 h');
    });
  });

  group('on the shelf', () {
    final shelf = [
      _spool(1, 'Alpha', at: _dried, temp: 55, hours: 7.5),
      _spool(2, 'Beta'),
    ];

    Future<void> pumpShelf(WidgetTester tester, {bool supported = true}) async {
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(() => _Shelf(shelf)),
          noServerProfileOverride,
          lastDriedSupportedProvider.overrideWithValue(AsyncData(supported)),
        ],
      );
      await settle(tester);
    }

    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);
    }

    testWidgets('the sort is offered where the server records a drying', (
      tester,
    ) async {
      await pumpShelf(tester);
      await openFilters(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, pl.inventoryLastDried));
      await settle(tester);
      final filters = ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      ).read(inventoryFiltersProvider);
      expect(filters.sort, InventorySort.lastDried);
    });

    testWidgets('an older server is not offered a sort with nothing to order', (
      tester,
    ) async {
      await pumpShelf(tester, supported: false);
      await openFilters(tester);
      expect(
        find.widgetWithText(ChoiceChip, pl.inventoryLastDried),
        findsNothing,
      );
      expect(
        find.widgetWithText(ChoiceChip, pl.inventorySortAdded),
        findsOneWidget,
      );
    });

    testWidgets('a dried spool carries its date on the tile, others none', (
      tester,
    ) async {
      await pumpShelf(tester);
      final formats = DateTimeFormats.of(
        tester.element(find.byType(InventoryScreen)),
      );
      expect(
        find.text(formats.dayNamedMonth(_dried.toLocal())),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.air), findsOneWidget);
    });

    testWidgets('the sheet gives the date and the run', (tester) async {
      await pumpShelf(tester);
      await tester.tap(find.textContaining('Alpha'));
      await settle(tester);
      final formats = DateTimeFormats.of(
        tester.element(find.byType(InventoryScreen)),
      );
      expect(find.text(pl.inventoryLastDried), findsOneWidget);
      expect(
        find.text('${formats.date(_dried.toLocal())} · 55 °C · 7.5 h'),
        findsOneWidget,
      );
    });

    testWidgets('a spool never dried has no such row', (tester) async {
      await pumpShelf(tester);
      await tester.tap(find.textContaining('Beta'));
      await settle(tester);
      expect(find.text(pl.inventoryLastDried), findsNothing);
    });
  });
}
