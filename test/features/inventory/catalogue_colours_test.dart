import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/features/inventory/catalogue_colours.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/colour_catalogue_kit.dart';

ColorEntry entry(
  String name, {
  String? material = 'PLA Basic',
  String manufacturer = 'Bambu Lab',
}) => ColorEntry(
  id: name.hashCode,
  manufacturer: manufacturer,
  colorName: name,
  hexColor: '#FFFFFF',
  material: material,
);

final catalogue = [
  entry('Jade White'),
  entry('Ivory White', material: 'PLA Matte'),
  entry('White', material: 'PLA Silk+'),
  entry('Gold', material: 'PLA Silk'),
  entry('Black', material: 'PETG HF'),
  entry('Unnamed', material: null),
  entry('Blank', material: ''),
  entry('Warm White', manufacturer: 'eSUN', material: 'PLA+'),
  entry('Fire Red', manufacturer: 'eSUN', material: 'PETG'),
];

List<String> names(List<ColorEntry> list) =>
    list.map((e) => e.colorName).toList();

void main() {
  test('nothing typed narrows to nothing', () {
    expect(catalogueColoursFor(catalogue), isEmpty);
    expect(
      catalogueColoursFor(catalogue, brand: '  ', material: ' ', subtype: 'X'),
      isEmpty,
    );
  });

  test('an empty catalogue gives nothing', () {
    expect(catalogueColoursFor(const [], brand: 'Bambu Lab'), isEmpty);
  });

  test('a brand alone gives every colour of that maker', () {
    expect(names(catalogueColoursFor(catalogue, brand: 'eSUN')), [
      'Warm White',
      'Fire Red',
    ]);
  });

  test('a brand alone that the catalogue does not know gives nothing', () {
    expect(catalogueColoursFor(catalogue, brand: 'Elegoo'), isEmpty);
  });

  test('the brand matches by word, as "mz - Bambu" finds Bambu Lab', () {
    final found = catalogueColoursFor(
      catalogue,
      brand: 'mz - Bambu',
      material: 'PETG',
    );
    expect(names(found), ['Black', 'Unnamed', 'Blank']);
  });

  test('one-letter brand words are ignored and match every maker', () {
    final found = catalogueColoursFor(catalogue, brand: 'X', material: 'PETG');
    expect(names(found), ['Black', 'Unnamed', 'Blank', 'Fire Red']);
  });

  test('material and variant take the exact catalogue spelling only', () {
    final found = catalogueColoursFor(
      catalogue,
      brand: 'Bambu Lab',
      material: 'PLA',
      subtype: 'Matte',
    );
    expect(names(found), ['Ivory White']);
  });

  test('case and surrounding spaces do not matter', () {
    final found = catalogueColoursFor(
      catalogue,
      brand: ' bambu lab ',
      material: '  pla ',
      subtype: 'MATTE ',
    );
    expect(names(found), ['Ivory White']);
  });

  test('a variant with a plus prefers the plus, else drops it', () {
    expect(
      names(
        catalogueColoursFor(
          catalogue,
          brand: 'Bambu Lab',
          material: 'PLA',
          subtype: 'Silk+',
        ),
      ),
      ['White'],
    );
    final withoutPlus = [
      for (final e in catalogue)
        if (e.material != 'PLA Silk+') e,
    ];
    expect(
      names(
        catalogueColoursFor(
          withoutPlus,
          brand: 'Bambu Lab',
          material: 'PLA',
          subtype: 'Silk+',
        ),
      ),
      ['Gold'],
    );
  });

  test('a variant the catalogue lacks falls back to the bare material', () {
    final found = catalogueColoursFor(
      catalogue,
      brand: 'Bambu Lab',
      material: 'PLA',
      subtype: 'Galaxy',
    );
    expect(names(found), [
      'Jade White',
      'Ivory White',
      'White',
      'Gold',
      'Unnamed',
      'Blank',
    ]);
  });

  test('a material alone takes it from every maker', () {
    expect(names(catalogueColoursFor(catalogue, material: 'petg')), [
      'Black',
      'Unnamed',
      'Blank',
      'Fire Red',
    ]);
  });

  test('a material nothing starts with keeps only entries without one', () {
    expect(
      names(catalogueColoursFor(catalogue, brand: 'Bambu', material: 'ASA')),
      ['Unnamed', 'Blank'],
    );
  });

  group('on the catalogue a server seeds', () {
    test('a Bambu Lab PLA Matte spool gets exactly its 25 matte colours', () {
      final colours = catalogueColoursFor(
        realCatalogue,
        brand: 'Bambu Lab',
        material: 'PLA',
        subtype: 'Matte',
      );
      expect(colours, hasLength(25));
      expect(colours.map((c) => c.material).toSet(), {'PLA Matte'});
      expect(
        colours.map((c) => c.colorName),
        containsAll(['Ivory White', 'Bone White']),
      );
    });

    test('the whites of one maker and material all have their own name', () {
      final names = catalogueColoursFor(
        realCatalogue,
        brand: 'Bambu Lab',
        material: 'PLA',
        subtype: 'Matte',
      ).map((c) => c.colorName).toList();
      expect(names.toSet(), hasLength(names.length));
    });
  });
}
