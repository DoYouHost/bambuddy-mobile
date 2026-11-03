import 'package:bambuddy_mobile/core/models/profile_default.dart';
import 'package:bambuddy_mobile/core/models/spool_preset_override.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileProduct', () {
    test('matches the server key: trimmed and case-folded', () {
      const a = ProfileProduct(
        brand: 'Bambu Lab',
        material: 'PLA',
        subtype: 'Basic',
        colorName: 'Red',
      );
      const b = ProfileProduct(
        brand: ' bambu lab ',
        material: 'pla',
        subtype: 'BASIC ',
        colorName: 'RED',
      );
      expect(a.matchKey, b.matchKey);
    });

    test('a colour, or a different field, is another product', () {
      const base = ProfileProduct(material: 'PLA', brand: 'Bambu Lab');
      expect(
        base.matchKey,
        isNot(
          const ProfileProduct(
            material: 'PLA',
            brand: 'Bambu Lab',
            colorName: 'Red',
          ).matchKey,
        ),
      );
      // The separator keeps ("ab", "c") apart from ("a", "bc").
      expect(
        const ProfileProduct(material: 'c', brand: 'ab').matchKey,
        isNot(const ProfileProduct(material: 'bc', brand: 'a').matchKey),
      );
    });

    test('allColours drops only the colour', () {
      const red = ProfileProduct(
        brand: 'Bambu Lab',
        material: 'PLA',
        subtype: 'Basic',
        colorName: 'Red',
      );
      expect(red.allColours.colorName, '');
      expect(red.allColours.subtype, 'Basic');
      expect(red.allColours.brand, 'Bambu Lab');
    });

    test('the label skips empty parts and never shows the colour', () {
      expect(
        const ProfileProduct(
          brand: 'Bambu Lab',
          material: 'PLA',
          subtype: 'Basic',
          colorName: 'Red',
        ).label,
        'Bambu Lab PLA Basic',
      );
      expect(const ProfileProduct(material: ' PETG ').label, 'PETG');
    });

    test('toJson trims and always carries the colour key', () {
      expect(const ProfileProduct(material: ' PLA ', brand: ' X ').toJson(), {
        'brand': 'X',
        'material': 'PLA',
        'subtype': '',
        'color_name': '',
      });
    });
  });

  group('ProfileDefault.fromJson', () {
    test('reads the product, the presets and keeps K profiles raw', () {
      final d = ProfileDefault.fromJson({
        'id': 4,
        'brand': 'Bambu Lab',
        'material': 'PLA',
        'subtype': 'Basic',
        'color_name': '',
        'slicer_filament': 'GFA00',
        'slicer_filament_name': 'Bambu PLA Basic',
        'presets': [
          {
            'printer_model': 'X1C',
            'nozzle_diameter': '0.4',
            'slicer_filament': 'GFA01',
            'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
          },
        ],
        'k_profiles': [
          {
            'printer_id': 2,
            'extruder': 1,
            'nozzle_diameter': '0.6',
            'k_value': 0.02,
            'name': 'High flow',
            'a_field_a_newer_server_adds': 'kept',
          },
        ],
        'updated_at': '2026-10-30T10:00:00',
      });

      expect(d.id, 4);
      expect(d.product.label, 'Bambu Lab PLA Basic');
      expect(d.product.colorName, '');
      expect(d.slicerFilamentName, 'Bambu PLA Basic');
      expect(d.presets.single.key, 'X1C|0.4');
      expect(d.kProfiles.single['a_field_a_newer_server_adds'], 'kept');
      expect(d.kProfiles.single['k_value'], 0.02);
    });

    test('missing and malformed collections read as empty', () {
      final d = ProfileDefault.fromJson({
        'id': 1,
        'material': 'PETG',
        'presets': 'nonsense',
        'k_profiles': {'not': 'a list'},
      });
      expect(d.presets, isEmpty);
      expect(d.kProfiles, isEmpty);
      expect(d.slicerFilament, isNull);
      expect(d.product.brand, '');
    });

    test('a K profile entry that is not an object is dropped', () {
      final d = ProfileDefault.fromJson({
        'id': 1,
        'material': 'PLA',
        'k_profiles': [
          7,
          {'printer_id': 1, 'k_value': 0.03},
        ],
      });
      expect(d.kProfiles, hasLength(1));
    });
  });

  group('ProfileDefaultDraft.toJson', () {
    test('sends the whole replacement body, K profiles untouched', () {
      final k = {'printer_id': 2, 'k_value': 0.02, 'extra': true};
      final body = ProfileDefaultDraft(
        product: const ProfileProduct(
          material: 'PLA',
          brand: 'Bambu Lab',
          colorName: 'Red',
        ),
        slicerFilament: 'GFA00',
        slicerFilamentName: 'Bambu PLA Basic',
        presets: const [
          SpoolPresetOverride(
            printerModel: 'X1C',
            slicerFilament: 'GFA01',
            slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
          ),
        ],
        kProfiles: [k],
      ).toJson();

      expect(body['color_name'], 'Red');
      expect(body['slicer_filament'], 'GFA00');
      expect(body['slicer_filament_name'], 'Bambu PLA Basic');
      expect((body['presets'] as List).single, {
        'printer_model': 'X1C',
        'nozzle_diameter': '',
        'slicer_filament': 'GFA01',
        'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
      });
      expect(body['k_profiles'], [k]);
    });

    test('a name without a preset is not sent', () {
      final body = const ProfileDefaultDraft(
        product: ProfileProduct(material: 'PLA'),
        slicerFilamentName: 'orphan',
      ).toJson();
      expect(body['slicer_filament'], isNull);
      expect(body['slicer_filament_name'], isNull);
      expect(body['presets'], isEmpty);
      expect(body['k_profiles'], isEmpty);
    });
  });
}
