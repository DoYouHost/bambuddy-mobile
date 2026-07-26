import 'package:bambuddy_mobile/core/diagnostics/filament_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical', () {
    test('accepts what the printer and the inventory actually report', () {
      expect(FilamentMaterial.canonical('PLA'), 'PLA');
      expect(FilamentMaterial.canonical('petg'), 'PETG');
      expect(FilamentMaterial.canonical('  TPU  '), 'TPU');
      // The printer spells its support filament with a space.
      expect(FilamentMaterial.canonical('Support W'), 'SUPPORT-W');
      expect(FilamentMaterial.canonical('pa6_cf'), 'PA6-CF');
    });

    test('drops anything outside the list', () {
      // The spool form's material field is free text, and this is the only
      // thing standing between it and a public issue.
      expect(FilamentMaterial.canonical('Professional Lab PETG Basic'), isNull);
      expect(FilamentMaterial.canonical('Ola PLA'), isNull);
      expect(FilamentMaterial.canonical(''), isNull);
      expect(FilamentMaterial.canonical(null), isNull);
    });

    test('does not trim an unknown variant down to a base it knows', () {
      // `PLA-WOOD` is not `PLA`: guessing would put a value in the log that
      // nobody wrote there.
      expect(FilamentMaterial.canonical('PLA-WOOD'), isNull);
    });
  });

  group('join / split', () {
    test('round-trips a known material', () {
      final tagged = FilamentMaterial.join('inventory.spool', 'PETG');

      expect(tagged, 'inventory.spool@PETG');
      expect(FilamentMaterial.split(tagged).id, 'inventory.spool');
      expect(FilamentMaterial.split(tagged).material, 'PETG');
    });

    test('leaves the identifier bare when the material is unknown', () {
      expect(
        FilamentMaterial.join('inventory.spool', 'Zwykły biały'),
        'inventory.spool',
      );
      expect(FilamentMaterial.join('inventory.spool', null), 'inventory.spool');
    });

    test('splitting keeps the id but drops an unvetted material', () {
      // A tag written by hand rather than through `join` must not smuggle a
      // value in through the second half.
      final split = FilamentMaterial.split('inventory.spool@Rain Gauge');

      expect(split.id, 'inventory.spool');
      expect(split.material, isNull);
    });

    test('an untagged identifier passes through untouched', () {
      final split = FilamentMaterial.split('archive.card');

      expect(split.id, 'archive.card');
      expect(split.material, isNull);
    });
  });
}
