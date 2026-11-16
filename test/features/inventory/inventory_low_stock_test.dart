import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dash_kit/dash_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// What the shelf calls "low": the server's `low_stock_threshold` (20 unless it
/// says otherwise) or the spool's own, strictly below, the way the web counts it
/// (`InventoryPage.tsx`). The app used to hold its own 10 and "at or below".
void main() {
  Spool spool(int id, double used, {int? own}) => Spool(
    id: id,
    material: 'PETG',
    labelWeight: 1000,
    weightUsed: used,
    lowStockThresholdPct: own,
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<Spool> spools, {
    Map<String, dynamic> settings = const {},
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          inventoryProvider.overrideWith(
            () => FixedInventory(InventoryState(spools: spools)),
          ),
          serverSettingsOverride(settings),
          noServerProfileOverride,
        ],
        child: plApp(const InventoryScreen()),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(InventoryScreen)),
    );
  }

  final badge = find.text(pl.inventoryLowStock.toUpperCase());

  testWidgets('15% left is low against the default 20', (tester) async {
    await pump(tester, [spool(1, 850)]);
    expect(badge, findsOneWidget);
  });

  testWidgets('exactly the threshold is not low', (tester) async {
    await pump(tester, [spool(1, 800)]);
    expect(badge, findsNothing);
  });

  testWidgets('the server setting moves the line', (tester) async {
    await pump(tester, [spool(1, 850)], settings: {'low_stock_threshold': 10});
    expect(badge, findsNothing);
  });

  testWidgets('a spool\'s own threshold beats the server one', (tester) async {
    await pump(tester, [spool(1, 850, own: 10), spool(2, 850)]);
    expect(badge, findsOneWidget);
  });

  testWidgets('the Low stock filter keeps exactly what the tile marks', (
    tester,
  ) async {
    final container = await pump(tester, [
      spool(1, 850),
      spool(2, 850, own: 10),
      spool(3, 500),
    ]);
    container.read(inventoryFiltersProvider.notifier).state = container
        .read(inventoryFiltersProvider)
        .copyWith(lowStockOnly: true);
    await settle(tester);
    expect(find.textContaining('#1 ·'), findsOneWidget);
    expect(find.textContaining('#2 ·'), findsNothing);
    expect(find.textContaining('#3 ·'), findsNothing);
  });

  group('the detail sheet', () {
    Future<Color?> sheetBarColour(WidgetTester tester, Spool s) async {
      final container = await pump(tester, [s]);
      container.read(inventoryFiltersProvider.notifier).state = container
          .read(inventoryFiltersProvider)
          .copyWith(showArchived: s.isArchived);
      await settle(tester);
      await tester.tap(find.textContaining('#${s.id} ·'));
      await settle(tester);
      return tester
          .widgetList<DashProgressBar>(find.byType(DashProgressBar))
          .last
          .color;
    }

    testWidgets('colours a low spool red', (tester) async {
      expect(await sheetBarColour(tester, spool(1, 850)), isNotNull);
    });

    testWidgets('does not colour an archived one, as its tile does not', (
      tester,
    ) async {
      final archived = Spool(
        id: 1,
        material: 'PETG',
        labelWeight: 1000,
        weightUsed: 850,
        archivedAt: '2026-01-01T00:00:00Z',
      );
      expect(await sheetBarColour(tester, archived), isNull);
    });
  });
}
