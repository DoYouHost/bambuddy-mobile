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

    test('isLowStock is strictly below the threshold the caller passes', () {
      // 70g / 1000g = 7% < 20
      expect(spool(label: 1000, used: 930).isLowStock(20), isTrue);
      // exactly 20% is not below 20: the web's `pct < threshold`
      expect(spool(label: 1000, used: 800).isLowStock(20), isFalse);
      // 19%
      expect(spool(label: 1000, used: 810).isLowStock(20), isTrue);
      // the same spool, a stricter server setting
      expect(spool(label: 1000, used: 810).isLowStock(10), isFalse);
    });

    test('a threshold of the spool\'s own beats the server one', () {
      // 18% left: low for the server's 20, fine for its own 10
      expect(spool(label: 1000, used: 820).isLowStock(20), isTrue);
      expect(
        spool(label: 1000, used: 820, threshold: 10).isLowStock(20),
        isFalse,
      );
      // and the other way round: 22% is fine for 20, low for its own 25
      expect(
        spool(label: 1000, used: 780, threshold: 25).isLowStock(20),
        isTrue,
      );
      // a zero falls through to the server's, like `pct or global`
      expect(
        spool(label: 1000, used: 820, threshold: 0).isLowStock(20),
        isTrue,
      );
    });

    test('a spool with no label weight has no percentage and is never low', () {
      expect(spool(label: 0).remainingPercent, isNull);
      expect(spool(label: 0).isLowStock(20), isFalse);
      expect(spool(label: 1000, used: 1500).remainingPercent, 0);
      expect(spool(label: 1000, used: 1500).isLowStock(20), isTrue);
    });

    group('parseLowStockThresholdInput', () {
      test('takes a number the server takes', () {
        expect(parseLowStockThresholdInput('20'), 20);
        expect(parseLowStockThresholdInput(' 15.5 '), 15.5);
        expect(parseLowStockThresholdInput('15,5'), 15.5);
        expect(parseLowStockThresholdInput('0.1'), lowStockThresholdMin);
        expect(parseLowStockThresholdInput('99.9'), lowStockThresholdMax);
        expect(parseLowStockThresholdInput('5'), 5);
        // What the web's field allows, and what the server holds when it was set
        // through the API with more decimals.
        expect(parseLowStockThresholdInput('.5'), 0.5);
        expect(parseLowStockThresholdInput('12.'), 12);
        expect(parseLowStockThresholdInput('12.04'), 12.04);
      });

      test('refuses what is empty, odd or outside 0.1 to 99.9', () {
        for (final text in [
          '',
          ' ',
          '.',
          ',',
          'abc',
          '1e1',
          '0',
          '0.0',
          '0.05',
          '100',
          '100.5',
          '123',
          '-5',
          '1,2,3',
          '5 %',
        ]) {
          expect(parseLowStockThresholdInput(text), isNull, reason: text);
        }
      });
    });

    test('formatLowStockThreshold drops a pointless .0, and only that', () {
      expect(formatLowStockThreshold(20), '20');
      expect(formatLowStockThreshold(20.0), '20');
      expect(formatLowStockThreshold(15.5), '15.5');
      expect(formatLowStockThreshold(0.1), '0.1');
      expect(formatLowStockThreshold(99.9), '99.9');
      expect(formatLowStockThreshold(12.04), '12.04');
      expect(formatLowStockThreshold(19.99), '19.99');
    });

    group('lowStockThresholdFrom', () {
      test('is the server\'s number inside 0 < v <= 100', () {
        expect(lowStockThresholdFrom({'low_stock_threshold': 15.5}), 15.5);
        expect(lowStockThresholdFrom({'low_stock_threshold': '30'}), 30);
        expect(lowStockThresholdFrom({'low_stock_threshold': 100}), 100);
      });

      test('is 20 when missing, unreadable or out of range', () {
        for (final settings in <Map<String, dynamic>>[
          const {},
          {'low_stock_threshold': null},
          {'low_stock_threshold': 'abc'},
          {'low_stock_threshold': 0},
          {'low_stock_threshold': -5},
          {'low_stock_threshold': 100.1},
        ]) {
          expect(lowStockThresholdFrom(settings), defaultLowStockThreshold);
        }
        expect(defaultLowStockThreshold, 20);
      });
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

    test('a regular AMS slot: not external, named as the web names it', () {
      final a = assign(1, trayId: 1);
      expect(a.isExternalSpool, isFalse);
      expect(a.extruder, isNull);
      expect(a.slotLabel, 'AMS-B · 2');
    });

    test('an AMS-HT slot is the unit alone — it holds one tray', () {
      expect(assign(129).slotLabel, 'HT-B');
    });

    test('a built-in assignment carries its spool, a Spoolman one not', () {
      final native = SpoolAssignment.fromNative({
        'spool_id': 3,
        'printer_id': 1,
        'ams_id': 0,
        'tray_id': 1,
        'spool': {
          'id': 3,
          'material': 'PETG',
          'label_weight': 1000,
          'weight_used': 250,
        },
      });
      expect(native.spool?.id, 3);
      expect(native.spool?.remainingWeight, 750);
      expect(SpoolAssignment.fromNative({'spool_id': 3}).spool, isNull);
      expect(
        SpoolAssignment.fromSpoolman({'spoolman_spool_id': 3}).spool,
        isNull,
      );
    });

    test('ams_label from the server names the unit, the slot stays', () {
      const a = SpoolAssignment(
        spoolId: 1,
        printerId: 1,
        amsId: 0,
        trayId: 0,
        amsLabel: 'Dryer box',
      );
      expect(a.slotLabel, 'Dryer box · 1');
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
  group('Spool.matchesSearch by id', () {
    Spool spool(int id) =>
        Spool.fromNative({'id': id, 'material': 'PLA', 'material_number': '9'});

    test('a bare number matches every id containing it', () {
      expect(spool(23).matchesSearch('23'), isTrue);
      expect(spool(123).matchesSearch(' 23 '), isTrue);
      expect(spool(230).matchesSearch('2'), isTrue);
      expect(spool(24).matchesSearch('23'), isFalse);
    });

    test('a hash-prefixed number matches that one spool only', () {
      expect(spool(23).matchesSearch('#23'), isTrue);
      expect(spool(123).matchesSearch('#23'), isFalse);
      expect(spool(230).matchesSearch('#23'), isFalse);
    });

    test('a lone hash or a hash with text is an ordinary text query', () {
      expect(spool(23).matchesSearch('#'), isFalse);
      expect(spool(23).matchesSearch('#pla'), isFalse);
      expect(spool(23).matchesSearch('#99999999999999999999'), isFalse);
    });

    test('note, slicer preset name and supplier article number match', () {
      final s = Spool.fromNative({
        'id': 1,
        'material': 'PLA',
        'note': 'Opened in May',
        'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
        'suppliers': [
          {
            'supplier_id': 4,
            'supplier_name': 'Shop',
            'supplier_article_number': 'ART-77',
          },
        ],
      });
      expect(s.matchesSearch('opened'), isTrue);
      expect(s.matchesSearch('@bbl'), isTrue);
      expect(s.matchesSearch('art-7'), isTrue);
      expect(s.matchesSearch('art-8'), isFalse);
    });

    test('text fields still match alongside the id', () {
      expect(spool(23).matchesSearch('pla'), isTrue);
      expect(spool(23).matchesSearch('9'), isTrue);
    });
  });
}
