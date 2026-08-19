import 'package:bambuddy_mobile/core/ams/preset_colours.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:flutter_test/flutter_test.dart';

ColorEntry entry(
  String name, {
  String hex = '#112233',
  String? material = 'PLA',
  String manufacturer = 'Bambu Lab',
}) =>
    ColorEntry(
      id: name.hashCode,
      manufacturer: manufacturer,
      colorName: name,
      hexColor: hex,
      material: material,
    );

void main() {
  test('the catalogue material is matched either way round', () {
    // The catalogue spells the variant into the material ("PLA Basic"), and a
    // preset may be plainer or richer than the entry.
    final colours = presetColours(
      [
        entry('Jade White', hex: '#FFFFFF', material: 'PLA Basic'),
        entry('Bambu Green', hex: '#00AE42', material: 'PLA'),
        entry('Grey', hex: '#808080', material: 'PETG'),
      ],
      'Bambu PLA Basic @BBL X1C',
    );

    expect(colours.map((c) => c.colorName), ['Jade White', 'Bambu Green']);
  });

  test('a branded preset takes only that maker', () {
    final colours = presetColours(
      [
        entry('Black', hex: '#000000', manufacturer: 'eSUN'),
        entry('White', hex: '#FFFFFF', manufacturer: 'Bambu Lab'),
      ],
      'eSUN PLA @BBL X1C',
    );

    expect(colours.map((c) => c.colorName), ['Black']);
  });

  test('"Generic PLA" is the preset name, not a maker', () {
    // Read as a manufacturer it would demand a maker called Generic and leave
    // the built-in presets — the ones most people pick — with no colours.
    final colours = presetColours(
      [entry('Bambu Green', hex: '#00AE42')],
      'Generic PLA',
    );

    expect(colours, hasLength(1));
  });

  test('an entry naming no material matches nothing rather than everything', () {
    // "Contains the empty string" is true of every filament there is.
    final colours = presetColours(
      [entry('Loose', material: null), entry('Loose too', material: '')],
      'Generic PETG',
    );

    expect(colours, isEmpty);
  });

  test('one swatch per colour', () {
    // The same hex is listed once per material and maker that sells it, and a
    // row of identical squares reads as a rendering fault.
    final colours = presetColours(
      [
        entry('Black', hex: '#000000', material: 'PLA'),
        entry('Czarny', hex: '000000FF', material: 'PLA Basic'),
      ],
      'Generic PLA',
    );

    expect(colours.map((c) => c.colorName), ['Black']);
  });

  test('an entry whose colour is unusable is dropped', () {
    final colours = presetColours(
      [entry('Broken', hex: 'not-a-colour'), entry('Fine', hex: '#010203')],
      'Generic PLA',
    );

    expect(colours.map((c) => c.colorName), ['Fine']);
  });
}
