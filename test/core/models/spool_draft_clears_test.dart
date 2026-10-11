import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

/// A null field in [SpoolDraft] means "leave it as it is", so a field the user
/// emptied has to be named in `clears` to reach the server at all. The wire
/// shapes below were probed against a real bambuddy (1.2.5.7 and the 1.2.6
/// daily) and a real Spoolman behind it.
void main() {
  const stored = Spool(
    id: 7,
    material: 'PLA',
    subtype: 'HF',
    brand: 'Bambu',
    colorName: 'Teal',
    note: 'dry box',
    category: 'cat',
    storageLocation: 'Shelf A',
    costPerKg: 20.5,
    lowStockThresholdPct: 15,
    nozzleTempMin: 190,
    lastScaleWeight: 800,
    materialNumber: '15',
  );

  group('clearing', () {
    test('names every clearable field the draft emptied', () {
      final draft = const SpoolDraft(material: 'PLA').clearing(stored);
      expect(draft.clears, {
        'subtype',
        'brand',
        'color_name',
        'note',
        'category',
        'storage_location',
        'cost_per_kg',
        'low_stock_threshold_pct',
        'material_number',
      });
    });

    test('leaves a field the draft still holds alone', () {
      final draft = const SpoolDraft(
        material: 'PLA',
        subtype: 'HF',
        brand: 'Bambu',
        colorName: 'Teal',
        note: 'x',
        category: 'cat',
        storageLocation: 'Shelf A',
        costPerKg: 20.5,
        lowStockThresholdPct: 15,
        materialNumber: '15',
      ).clearing(stored);
      expect(draft.clears, isEmpty);
    });

    test('never clears what the form does not manage', () {
      final draft = const SpoolDraft(material: 'PLA').clearing(stored);
      expect(draft.clears, isNot(contains('nozzle_temp_min')));
      expect(draft.clears, isNot(contains('last_scale_weight')));
      expect(draft.clears, isNot(contains('rgba')));
    });

    test('keeps clears it already had', () {
      final draft = const SpoolDraft(
        material: 'PLA',
        clears: {'note'},
      ).clearing(const Spool(id: 1, material: 'PLA'));
      expect(draft.clears, {'note'});
    });

    test('skips a field the user could not see', () {
      final draft = const SpoolDraft(
        material: 'PLA',
      ).clearing(stored, except: {'material_number'});
      expect(draft.clears, isNot(contains('material_number')));
      expect(draft.clears, contains('note'));
    });

    test('has nothing to clear on a spool that held nothing', () {
      const bare = Spool(id: 1, material: 'PLA');
      expect(const SpoolDraft(material: 'PLA').clearing(bare).clears, isEmpty);
    });
  });

  group('on the wire', () {
    final cleared = const SpoolDraft(material: 'PLA').clearing(stored);

    test('native: an explicit null, which the route stores as NULL', () {
      final json = cleared.toNativeJson();
      for (final key in cleared.clears) {
        expect(json.containsKey(key), isTrue, reason: key);
        expect(json[key], isNull, reason: key);
      }
    });

    test('native: an untouched draft sends no null at all', () {
      expect(
        SpoolDraft.fromSpool(stored).clearing(stored).toNativeJson().values,
        isNot(contains(null)),
      );
    });

    test('Spoolman: the slicer preset clears on an empty string', () {
      final json = const SpoolDraft(material: 'PLA')
          .clearing(
            const Spool(
              id: 1,
              material: 'PLA',
              slicerFilament: 'GFA00',
              slicerFilamentName: 'Bambu PLA',
            ),
          )
          .toSpoolmanJson();
      expect(json['slicer_filament'], '');
      expect(json['slicer_filament_name'], '');
    });

    test('Spoolman: only the clears its route understands, in its dialect', () {
      expect(cleared.toSpoolmanJson(), {
        'material': 'PLA',
        'subtype': '',
        'note': '',
        'storage_location': null,
        'color_name': null,
      });
    });
  });
}
