import 'package:bambuddy_mobile/core/models/available_filament.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AvailableFilament', () {
    test('fromJson parses full filament structure', () {
      final json = {
        'type': 'PLA',
        'color': '#FF0000',
        'tray_sub_brands': 'PLA Basic',
        'tray_info_idx': 'GFL99',
        'extruder_id': 1,
      };

      final filament = AvailableFilament.fromJson(json);

      expect(filament.type, 'PLA');
      expect(filament.color, '#FF0000');
      expect(filament.traySubBrands, 'PLA Basic');
      expect(filament.trayInfoIdx, 'GFL99');
      expect(filament.extruderId, 1);
      expect(filament.label, 'PLA Basic');
    });

    test('label falls back to type when traySubBrands is null or empty', () {
      const withNullBrand = AvailableFilament(type: 'PETG', color: '#00FF00');
      expect(withNullBrand.label, 'PETG');

      const withEmptyBrand = AvailableFilament(
        type: 'TPU',
        color: '#0000FF',
        traySubBrands: '',
      );
      expect(withEmptyBrand.label, 'TPU');
    });

    test('parseList skips non-maps and empty types', () {
      final list = [
        {'type': 'PLA', 'color': '#FF0000'},
        'invalid item',
        123,
        {'type': '', 'color': '#00FF00'},
        {'color': '#0000FF'},
        {
          'type': 'ABS',
          'color': '#FFFFFF',
          'tray_sub_brands': 'Bambu ABS',
        },
      ];

      final result = AvailableFilament.parseList(list);

      expect(result, hasLength(2));
      expect(result[0].type, 'PLA');
      expect(result[1].type, 'ABS');
      expect(result[1].label, 'Bambu ABS');
    });
  });
}
