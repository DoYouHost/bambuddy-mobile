import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/notifications/low_stock.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's `_check_filament_low` internal path, as far as it can be said
/// without a monitor around it.
void main() {
  Spool spool(
    int id, {
    int label = 1000,
    double used = 0,
    int? own,
    String? archivedAt,
  }) => Spool(
    id: id,
    material: 'PLA',
    labelWeight: label,
    weightUsed: used,
    lowStockThresholdPct: own,
    archivedAt: archivedAt,
  );

  SpoolAssignment slot(
    int spoolId, {
    int printer = 1,
    int ams = 0,
    int tray = 0,
  }) => SpoolAssignment(
    spoolId: spoolId,
    printerId: printer,
    amsId: ams,
    trayId: tray,
  );

  group('lowStockSlots', () {
    test(
      'a slot is the spool in it, keyed by printer, unit, slot and spool',
      () {
        final slots = lowStockSlots(
          spools: [spool(7, used: 900)],
          assignments: [slot(7, printer: 2, ams: 1, tray: 3)],
          globalThreshold: 20,
        );
        expect(slots.keys.single, (
          printerId: 2,
          amsId: 1,
          trayId: 3,
          spoolId: 7,
        ));
        expect(slots.values.single.percent, 10);
        expect(slots.values.single.threshold, 20);
        expect(slots.values.single.isLow, isTrue);
      },
    );

    test('the spool\'s own threshold wins over the server\'s', () {
      final slots = lowStockSlots(
        spools: [spool(7, used: 850, own: 10)],
        assignments: [slot(7)],
        globalThreshold: 20,
      );
      expect(slots.values.single.threshold, 10);
      expect(slots.values.single.isLow, isFalse);
    });

    test('what has no percentage or is not stock is not judged', () {
      final slots = lowStockSlots(
        spools: [
          spool(1, label: 0),
          spool(2, used: 990, archivedAt: '2026-01-01T00:00:00Z'),
          spool(3, used: 990),
        ],
        assignments: [
          slot(1, tray: 0),
          slot(2, tray: 1),
          slot(3, tray: 2),
          slot(99, tray: 3), // a spool the list does not hold
        ],
        globalThreshold: 20,
      );
      expect(slots.keys.map((k) => k.spoolId), [3]);
    });

    test('no assignments, no slots', () {
      expect(
        lowStockSlots(
          spools: [spool(1, used: 990)],
          assignments: const [],
          globalThreshold: 20,
        ),
        isEmpty,
      );
    });
  });

  group('LowStockLatch', () {
    LowStockKey key(int spool, {int tray = 0}) =>
        (printerId: 1, amsId: 0, trayId: tray, spoolId: spool);
    Map<LowStockKey, LowStockSlot> at(double pct, {int spool = 1}) => {
      key(spool): LowStockSlot(pct, 20),
    };

    test('the first look records and reports nothing', () {
      final latch = LowStockLatch();
      expect(latch.look(at(5)), isEmpty);
      expect(latch.said, 1);
      expect(latch.look(at(5)), isEmpty);
    });

    test(
      'a crossing is reported once, then again after the line is regained',
      () {
        final latch = LowStockLatch()..look(at(50));
        expect(latch.look(at(19)), [key(1)]);
        expect(latch.look(at(18)), isEmpty);
        expect(latch.look(at(20)), isEmpty);
        expect(latch.look(at(19)), [key(1)]);
      },
    );

    test('a first look with nothing in it still counts as the first', () {
      final latch = LowStockLatch()..look(const {});
      expect(latch.look(at(5)), [key(1)]);
    });

    test('a key that is not in the look keeps what was said about it', () {
      final latch = LowStockLatch()
        ..look(at(50))
        ..look(at(5));
      latch.look(const {});
      expect(latch.look(at(5)), isEmpty);
    });

    test('a held-back key stays owed', () {
      final latch = LowStockLatch()..look(at(50));
      expect(latch.look(at(5), onlyIf: (_) => false), isEmpty);
      expect(latch.look(at(5)), [key(1)]);
    });

    test('forgetting a printer clears only its keys', () {
      final latch = LowStockLatch()
        ..look({
          key(1): const LowStockSlot(50, 20),
          (printerId: 2, amsId: 0, trayId: 0, spoolId: 2): const LowStockSlot(
            50,
            20,
          ),
        });
      latch.look({
        key(1): const LowStockSlot(5, 20),
        (printerId: 2, amsId: 0, trayId: 0, spoolId: 2): const LowStockSlot(
          5,
          20,
        ),
      });
      expect(latch.said, 2);
      latch.forget({1});
      expect(latch.said, 1);
    });
  });
}
