import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spool.fromNative', () {
    test('parses fields and ignores unknown keys', () {
      final spool = Spool.fromNative({
        'id': 7,
        'material': 'PETG',
        'subtype': 'HF',
        'color_name': 'White',
        'rgba': 'FFFFFFFF',
        'brand': 'Professional Lab',
        'label_weight': 1000,
        'weight_used': 935,
        'cost_per_kg': 29.99,
        'storage_location': 'Szafa',
        'low_stock_threshold_pct': 10,
        'unknown_field': 'ignore',
      });

      expect(spool.id, 7);
      expect(spool.material, 'PETG');
      expect(spool.displayName, 'Professional Lab PETG HF');
      expect(spool.costPerKg, 29.99);
      expect(spool.storageLocation, 'Szafa');
    });

    test('numbers tolerate string and num; missing material → Unknown', () {
      final spool = Spool.fromNative({
        'id': '12',
        'material': '   ',
        'label_weight': '1000',
        'weight_used': 250,
      });

      expect(spool.id, 12);
      expect(spool.material, 'Unknown');
      expect(spool.labelWeight, 1000);
      expect(spool.weightUsed, 250);
    });
  });

  group('consumed counter parsing', () {
    test('the native shape carries the baseline', () {
      final spool = Spool.fromNative({
        'id': 1,
        'material': 'PLA',
        'label_weight': 1000,
        'weight_used': 900.0,
        'weight_used_baseline': 700.0,
      });

      expect(spool.consumedWeight, 200);
      expect(spool.remainingWeight, 100);
    });

    test('Spoolman carries it too, under the same name', () {
      // Spoolman has no such column — the backend derives it from its
      // used_weight / remaining_weight pair and maps it onto the native name.
      final spool = Spool.fromSpoolman({
        'id': 1,
        'material': 'PLA',
        'label_weight': 1000,
        'weight_used': 900.0,
        'weight_used_baseline': 850.0,
      });

      expect(spool.consumedWeight, 50);
    });

    test('a server that says nothing about it counts from zero', () {
      final spool = Spool.fromNative({
        'id': 1,
        'material': 'PLA',
        'weight_used': 120.0,
      });

      expect(spool.weightUsedBaseline, 0);
      expect(spool.consumedWeight, 120);
    });
  });

  group('Spool getters', () {
    Spool spool({int label = 1000, double used = 0, int? threshold}) => Spool(
      id: 1,
      material: 'PLA',
      labelWeight: label,
      weightUsed: used,
      lowStockThresholdPct: threshold,
    );

    test('remainingWeight does not go below zero', () {
      expect(spool(label: 1000, used: 1200).remainingWeight, 0);
      expect(spool(label: 1000, used: 650).remainingWeight, 350);
    });

    test('remainingFraction null when the label weight is unknown', () {
      expect(spool(label: 0).remainingFraction, isNull);
      expect(spool(label: 1000, used: 750).remainingFraction, 0.25);
    });

    test('isLowStock per the server threshold, 10% by default', () {
      // 70g / 1000g = 7% ≤ 10% (default threshold)
      expect(spool(label: 1000, used: 930).isLowStock, isTrue);
      // 200g / 1000g = 20% > 10%
      expect(spool(label: 1000, used: 800).isLowStock, isFalse);
      // server threshold 25% → 20% is below it
      expect(spool(label: 1000, used: 800, threshold: 25).isLowStock, isTrue);
    });

    test('consumedWeight counts from the baseline, not from zero', () {
      // The counter and the remaining weight are independent: a reset stamps
      // the baseline up to weight_used, which zeroes the counter and leaves
      // the spool exactly as empty as it was (server issue #1390).
      const reset = Spool(
        id: 1,
        material: 'PLA',
        labelWeight: 1000,
        weightUsed: 650,
        weightUsedBaseline: 650,
      );

      expect(reset.consumedWeight, 0);
      expect(reset.remainingWeight, 350, reason: 'reset does not refill');
    });

    test('consumedWeight never reads negative', () {
      // A baseline above weight_used is not a state the server writes, but a
      // Spoolman spool whose weights were edited under it can arrive that way.
      const odd = Spool(
        id: 1,
        material: 'PLA',
        weightUsed: 100,
        weightUsedBaseline: 400,
      );

      expect(odd.consumedWeight, 0);
    });

    test('a spool with no baseline counts everything it has used', () {
      expect(spool(label: 1000, used: 240).consumedWeight, 240);
    });

    test('isArchived from a non-empty archived_at', () {
      expect(
        Spool.fromNative({
          'id': 1,
          'material': 'PLA',
          'archived_at': '',
        }).isArchived,
        isFalse,
      );
      expect(
        Spool.fromNative({
          'id': 1,
          'material': 'PLA',
          'archived_at': '2026-06-01',
        }).isArchived,
        isTrue,
      );
    });
  });

  group('SpoolAssignment — slot vs external spool', () {
    SpoolAssignment assign(int amsId, {int trayId = 0}) =>
        SpoolAssignment(spoolId: 1, printerId: 1, amsId: amsId, trayId: trayId);

    test('a regular AMS slot: not external, label AMS·tray+1', () {
      final a = assign(0, trayId: 1);
      expect(a.isExternalSpool, isFalse);
      expect(a.extruder, isNull);
      expect(a.slotLabel, 'AMS0 · 2');
    });

    test('ams_label from the server takes priority', () {
      const a = SpoolAssignment(
        spoolId: 1,
        printerId: 1,
        amsId: 0,
        trayId: 0,
        amsLabel: 'AMS A',
      );
      expect(a.slotLabel, 'AMS A');
    });

    test('external spool: ams=255, distinguishes tray_id (0→left, 1→right)', () {
      // Verified live on an X2D from raw assignments: BOTH external spools
      // have ams_id=255, tray_id distinguishes the extruder. TPU tray=0 = left (1),
      // PLA tray=1 = right (0). Convention as in printer_status: 1=left, 0=right.
      expect(assign(255, trayId: 0).isExternalSpool, isTrue);
      expect(assign(255, trayId: 0).extruder, 1);
      expect(assign(255, trayId: 1).extruder, 0);
    });
  });

  group('RFID tag normalization', () {
    test('upper-cases and keeps only hex digits', () {
      expect(normalizeTagHex('a1b2c3d4'), 'A1B2C3D4');
      expect(normalizeTagHex(' A1:B2-C3 D4 '), 'A1B2C3D4');
    });

    test('no tag at all normalizes to the empty string, never to null', () {
      expect(normalizeTagHex(null), '');
      expect(normalizeTagHex(''), '');
      expect(normalizeTagHex('   '), '');
      // A tag the firmware writes as "unset" carries no hex at all once the
      // separators are stripped.
      expect(normalizeTagHex('--'), '');
    });

    test('a tag UID longer than the column keeps its last 16 characters', () {
      expect(normalizeTagUid('00112233445566778899'), '2233445566778899');
      expect(normalizeTagUid('0011223344556677'), '0011223344556677');
      expect(normalizeTagUid('00112233'), '00112233');
    });

    test('a tray UUID longer than the column keeps its first 32', () {
      final long = 'A' * 40;
      expect(normalizeTrayUuid(long), 'A' * 32);
      expect(normalizeTrayUuid('deadbeef'), 'DEADBEEF');
    });

    test('an all-zero tag is still an identifier here, not an absence', () {
      // Emptying it is the server's job (it nulls the zero tag before the app
      // ever sees it); doing it twice would hide a real, if odd, value.
      expect(normalizeTagUid('0000000000000000'), '0000000000000000');
    });
  });
}
