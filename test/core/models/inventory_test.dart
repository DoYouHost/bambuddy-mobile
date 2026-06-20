import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spool.fromNative', () {
    test('parsuje pola i ignoruje nieznane klucze', () {
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
        'nieznane_pole': 'ignoruj',
      });

      expect(spool.id, 7);
      expect(spool.material, 'PETG');
      expect(spool.displayName, 'Professional Lab PETG HF');
      expect(spool.costPerKg, 29.99);
      expect(spool.storageLocation, 'Szafa');
    });

    test('liczby tolerują string i num; brak materiału → Unknown', () {
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

  group('Spool getters', () {
    Spool spool({int label = 1000, double used = 0, int? threshold}) =>
        Spool(
          id: 1,
          material: 'PLA',
          labelWeight: label,
          weightUsed: used,
          lowStockThresholdPct: threshold,
        );

    test('remainingWeight nie schodzi poniżej zera', () {
      expect(spool(label: 1000, used: 1200).remainingWeight, 0);
      expect(spool(label: 1000, used: 650).remainingWeight, 350);
    });

    test('remainingFraction null gdy nie znamy wagi etykiety', () {
      expect(spool(label: 0).remainingFraction, isNull);
      expect(spool(label: 1000, used: 750).remainingFraction, 0.25);
    });

    test('isLowStock wg progu serwera, domyślnie 10%', () {
      // 70 g / 1000 g = 7% ≤ 10% (domyślny próg)
      expect(spool(label: 1000, used: 930).isLowStock, isTrue);
      // 200 g / 1000 g = 20% > 10%
      expect(spool(label: 1000, used: 800).isLowStock, isFalse);
      // próg serwera 25% → 20% poniżej
      expect(spool(label: 1000, used: 800, threshold: 25).isLowStock, isTrue);
    });

    test('isArchived po niepustym archived_at', () {
      expect(
        Spool.fromNative({'id': 1, 'material': 'PLA', 'archived_at': ''})
            .isArchived,
        isFalse,
      );
      expect(
        Spool.fromNative(
                {'id': 1, 'material': 'PLA', 'archived_at': '2026-06-01'})
            .isArchived,
        isTrue,
      );
    });
  });

  group('SpoolAssignment — slot vs szpula zewnętrzna', () {
    SpoolAssignment assign(int amsId, {int trayId = 0}) =>
        SpoolAssignment(
          spoolId: 1,
          printerId: 1,
          amsId: amsId,
          trayId: trayId,
        );

    test('zwykły slot AMS: nie jest zewnętrzny, label AMS·tray+1', () {
      final a = assign(0, trayId: 1);
      expect(a.isExternalSpool, isFalse);
      expect(a.extruder, isNull);
      expect(a.slotLabel, 'AMS0 · 2');
    });

    test('ams_label z serwera ma pierwszeństwo', () {
      const a = SpoolAssignment(
        spoolId: 1,
        printerId: 1,
        amsId: 0,
        trayId: 0,
        amsLabel: 'AMS A',
      );
      expect(a.slotLabel, 'AMS A');
    });

    test('szpula zewnętrzna: 255 → lewy (ekstruder 1), 254 → prawy (0)', () {
      // Kontrakt odwrotny do MQTT vtTray — zweryfikowany fizycznie na X2D:
      // ams_id 255 to LEWY ekstruder, 254 to PRAWY.
      expect(assign(255).isExternalSpool, isTrue);
      expect(assign(255).extruder, 1);
      expect(assign(254).isExternalSpool, isTrue);
      expect(assign(254).extruder, 0);
    });
  });
}
