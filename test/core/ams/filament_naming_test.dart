import 'package:bambuddy_mobile/core/ams/filament_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePresetName', () {
    test('splits brand, material and variant', () {
      final parsed = parsePresetName('Bambu PLA Basic @BBL X1C');
      expect(parsed.material, 'PLA');
      expect(parsed.brand, 'Bambu');
      expect(parsed.variant, 'Basic');
    });

    test('drops the printer suffix before parsing', () {
      // "@Bambu Lab H2D 0.4 nozzle" holds no filament information, and the
      // sub-brand sent to the printer must not carry it either.
      expect(
        presetNameWithoutPrinter('SUNLU TPU 95A @Bambu Lab H2D 0.4 nozzle'),
        'SUNLU TPU 95A',
      );
    });

    test('reads a support preset as the material it supports', () {
      // "PLA Support for PETG" prints at PETG temperatures; taking the first
      // material in the name would send a range 40 °C too cold.
      final parsed = parsePresetName('PLA Support for PETG');
      expect(parsed.material, 'PETG');
      expect(parsed.variant, 'Support');
    });

    test('prefers the longer of two materials that share a prefix', () {
      expect(parsePresetName('Generic PETG HF').material, 'PETG');
      expect(parsePresetName('Generic PCTG').material, 'PCTG');
    });

    test('matches a material glued to a suffix by a dash', () {
      expect(parsePresetName('Bambu PLA-CF').material, 'PLA');
    });

    test('keeps the text after a material that appears twice', () {
      final parsed = parsePresetName('PETG eSUN PETG Basic');
      expect(parsed.material, 'PETG');
      expect(parsed.variant, 'eSUN PETG Basic');
    });

    test('falls back to the slicer naming convention for an unknown material',
        () {
      final parsed = parsePresetName('Acme XYZ99 Matte');
      expect(parsed.brand, 'Acme');
      expect(parsed.material, 'XYZ99');
      expect(parsed.variant, 'Matte');
    });
  });

  group('filamentIdFromSettingId', () {
    test('turns a Bambu setting id into its filament id', () {
      expect(filamentIdFromSettingId('GFSL05_09'), 'GFL05');
      expect(filamentIdFromSettingId('GFSL05'), 'GFL05');
    });

    test('keeps a user preset id, minus the version suffix', () {
      expect(filamentIdFromSettingId('PFUS9ac902733670a9_02'),
          'PFUS9ac902733670a9');
      expect(filamentIdFromSettingId('PFSP1234'), 'PFSP1234');
    });
  });

  group('genericFilamentId', () {
    test('answers the exact material where Bambu has one', () {
      expect(genericFilamentId('PLA'), 'GFL99');
      expect(genericFilamentId('petg hf'), 'GFG96');
    });

    test('falls back to the plain material for a variant it does not know', () {
      // No generic exists for "PLA Matte" — generic PLA still lets the printer
      // classify the slot, which an empty id would not.
      expect(genericFilamentId('PLA Matte'), 'GFL99');
    });

    test('drops a plus before dropping the fibre suffix', () {
      // "PLA-CF+" should land on generic PLA-CF, not on plain PLA: the
      // reinforced generic is the closer match and the printer treats the two
      // differently.
      expect(genericFilamentId('PLA-CF+'), 'GFL98');
    });

    test('answers empty when the material is not Bambu\'s at all', () {
      expect(genericFilamentId('XYZ99'), '');
    });
  });

  group('nozzleTemperaturesFor', () {
    test('covers a material variant by substring', () {
      expect(nozzleTemperaturesFor('PLA Silk'), (min: 190, max: 230));
      expect(nozzleTemperaturesFor('PETG-CF'), (min: 220, max: 260));
    });

    test('keeps PCTG off the polycarbonate range', () {
      // "PCTG" contains "PC"; ordering the rules the other way would send
      // 260–300 °C to a filament that melts at 220.
      expect(nozzleTemperaturesFor('PCTG'), (min: 220, max: 260));
      expect(nozzleTemperaturesFor('PC'), (min: 260, max: 300));
    });

    test('treats nylon as PA', () {
      expect(nozzleTemperaturesFor('NYLON'), (min: 250, max: 290));
    });

    test('falls back to the PLA range for an unknown material', () {
      // The call requires both ends, so there is no "leave it out" answer —
      // the safest guess is the coldest common one.
      expect(nozzleTemperaturesFor('XYZ99'), (min: 190, max: 230));
    });
  });
}
