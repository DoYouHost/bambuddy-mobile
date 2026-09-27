import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _Shelf extends InventoryNotifier {
  static int loads = 0;

  @override
  Future<InventoryState> build() async {
    loads++;
    return const InventoryState(
      spools: [Spool(id: 1, material: 'PLA', brand: 'Bambu')],
    );
  }

  @override
  Future<void> refresh() async {
    loads++;
  }
}

/// What the spool screen does about data that aged while it was not the tab
/// on screen — and about the climate readings beside it, which age on their
/// own because the server polls Home Assistant on its own interval.
void main() {
  late int climateReads;
  var now = DateTime(2026, 9, 19, 11);

  setUp(() {
    _Shelf.loads = 0;
    climateReads = 0;
    now = DateTime(2026, 9, 19, 11);
  });

  Future<void> pumpTab(WidgetTester tester, {required bool shown}) => withClock(
    Clock(() => now),
    () => pumpPhone(
      tester,
      TickerMode(enabled: shown, child: const InventoryScreen()),
      overrides: [
        noServerProfileOverride,
        inventoryProvider.overrideWith(_Shelf.new),
        locationClimateProvider.overrideWith((ref) async {
          climateReads++;
          return const {};
        }),
      ],
    ),
  );

  testWidgets('coming back to the tab re-reads the shelf and the climate', (
    tester,
  ) async {
    await pumpTab(tester, shown: true);
    await settle(tester);
    final shelfReads = _Shelf.loads;
    final climateBefore = climateReads;

    await pumpTab(tester, shown: false);
    now = now.add(const Duration(minutes: 2));
    await pumpTab(tester, shown: true);
    await settle(tester);

    expect(_Shelf.loads, shelfReads + 1);
    expect(
      climateReads,
      climateBefore + 1,
      reason: 'a shelf refreshed beside stale readings is half an answer',
    );
  });
}
