import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/slicer/preset_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two optional narrowings the spool form's preset picker offers. Both are
/// written to fail open: what the evidence does not cover stays in the list,
/// because a preset hidden by a filter the user did not ask for looks like a
/// preset the server never sent.
void main() {
  const registry = {
    'Bambu Lab X1 Carbon': 'X1C',
    'Bambu Lab P1S': 'P1S',
    'Bambu Lab A1 mini': 'A1 Mini',
  };

  SlicerPreset preset(String name, {String? type}) =>
      SlicerPreset(source: 'cloud', id: name, name: name, filamentType: type);

  List<String> namesOf(List<SlicerPreset> presets) => [
    for (final p in presets) p.name,
  ];

  group('by printer model', () {
    test('drops what names another printer, keeps what names none', () {
      final kept = filterFilamentPresets(
        [
          preset('Bambu PLA Basic @BBL X1C'),
          preset('Bambu PLA Basic @BBL P1S'),
          preset('My own PLA'),
        ],
        printerModel: 'X1C',
        printerModels: registry,
      );

      expect(namesOf(kept), ['Bambu PLA Basic @BBL X1C', 'My own PLA']);
    });

    test('reads the long form a user-saved preset carries', () {
      final kept = filterFilamentPresets(
        [preset('SUNLU PLA @Bambu Lab X1 Carbon 0.4 nozzle')],
        printerModel: 'X1C',
        printerModels: registry,
      );

      expect(kept, hasLength(1));
    });

    test('the A1M rename is the same printer as A1 Mini', () {
      final kept = filterFilamentPresets(
        [preset('Bambu PLA Basic @BBL A1M')],
        printerModel: 'A1 Mini',
        printerModels: registry,
      );

      expect(kept, hasLength(1));
    });

    test('no model asked for hides nothing', () {
      final all = [preset('Bambu PLA Basic @BBL X1C'), preset('X @BBL P1S')];

      expect(filterFilamentPresets(all, printerModels: registry), hasLength(2));
    });

    test('without the registry the short code still decides, and a model '
        'written into the body of the name no longer resolves at all', () {
      final kept = filterFilamentPresets([
        preset('Bambu PLA Basic @BBL P1S'),
        preset('Bambu PLA Basic @BBL X1C'),
        preset('X1C eSUN PETG-Basic'),
      ], printerModel: 'X1C');

      expect(namesOf(kept), [
        'Bambu PLA Basic @BBL X1C',
        'X1C eSUN PETG-Basic',
      ]);
    });
  });

  group('by material', () {
    test('the declared type is the evidence when the preset has one', () {
      final kept = filterFilamentPresets([
        preset('Some house blend', type: 'PLA'),
        preset('Another house blend', type: 'PETG'),
      ], material: 'pla');

      expect(namesOf(kept), ['Some house blend']);
    });

    test('a declared type that disagrees settles it — the name is not read '
        'as a second opinion', () {
      final kept = filterFilamentPresets([
        preset('PETG that prints under PLA supports', type: 'PETG'),
      ], material: 'PLA');

      expect(kept, isEmpty);
    });

    test('falls back to the name, which is all the cloud tier gives', () {
      final kept = filterFilamentPresets([
        preset('Bambu PLA Matte @BBL X1C'),
        preset('Bambu PETG HF @BBL X1C'),
      ], material: 'PLA');

      expect(namesOf(kept), ['Bambu PLA Matte @BBL X1C']);
    });

    test('a material is a word, not a substring: PC is not PCTG', () {
      final kept = filterFilamentPresets([
        preset('Bambu PCTG'),
        preset('Bambu PC Emerge'),
      ], material: 'PC');

      expect(namesOf(kept), ['Bambu PC Emerge']);
    });

    test('a variant still counts as its base material', () {
      final kept = filterFilamentPresets([
        preset('Bambu PLA-CF @BBL X1C'),
      ], material: 'PLA');

      expect(kept, hasLength(1));
    });

    test('a blank material hides nothing — a new spool has none yet', () {
      final all = [preset('Bambu PLA Basic'), preset('Bambu PETG HF')];

      expect(filterFilamentPresets(all, material: '   '), hasLength(2));
      expect(filterFilamentPresets(all), hasLength(2));
    });
  });

  test('the search box still matches the name or the id', () {
    final all = [
      SlicerPreset(source: 'cloud', id: 'GFA00', name: 'Bambu PLA Basic'),
      SlicerPreset(source: 'cloud', id: 'GFG00', name: 'Bambu PETG HF'),
    ];

    expect(namesOf(filterFilamentPresets(all, query: 'petg')), [
      'Bambu PETG HF',
    ]);
    expect(namesOf(filterFilamentPresets(all, query: 'gfa')), [
      'Bambu PLA Basic',
    ]);
  });

  test('the filters compose — model and material at once', () {
    final kept = filterFilamentPresets(
      [
        preset('Bambu PLA Basic @BBL X1C'),
        preset('Bambu PETG HF @BBL X1C'),
        preset('Bambu PLA Basic @BBL P1S'),
      ],
      printerModel: 'X1C',
      printerModels: registry,
      material: 'PLA',
    );

    expect(namesOf(kept), ['Bambu PLA Basic @BBL X1C']);
  });
}
