import 'package:bambuddy_mobile/core/models/k_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KProfile', () {
    test('fromJson parses full profile correctly', () {
      final json = {
        'slot_id': 3,
        'name': 'Bambu PLA Basic 0.4',
        'k_value': '0.020000',
        'extruder_id': 1,
        'nozzle_diameter': '0.4',
        'filament_id': 'GFL99',
        'setting_id': 'set-123',
      };

      final profile = KProfile.fromJson(json);

      expect(profile.slotId, 3);
      expect(profile.name, 'Bambu PLA Basic 0.4');
      expect(profile.kValue, '0.020000');
      expect(profile.extruderId, 1);
      expect(profile.nozzleDiameter, '0.4');
      expect(profile.filamentId, 'GFL99');
      expect(profile.settingId, 'set-123');
      expect(profile.k, closeTo(0.02, 0.0001));
      expect(profile.optionId, 'Bambu PLA Basic 0.4|0.020000|GFL99');
    });

    test('fromJson handles defaults for missing/null values', () {
      final json = <String, dynamic>{};

      final profile = KProfile.fromJson(json);

      expect(profile.slotId, 0);
      expect(profile.name, '');
      expect(profile.kValue, '0');
      expect(profile.extruderId, 0);
      expect(profile.nozzleDiameter, '');
      expect(profile.filamentId, '');
      expect(profile.settingId, isNull);
      expect(profile.k, 0.0);
      expect(profile.optionId, '|0|');
    });

    test('optionId distinguishes profiles with different filamentId but same name and k', () {
      const p1 = KProfile(
        slotId: 1,
        name: 'Generic PETG',
        kValue: '0.035000',
        filamentId: 'GFB00',
      );
      const p2 = KProfile(
        slotId: 2,
        name: 'Generic PETG',
        kValue: '0.035000',
        filamentId: 'GFB01',
      );

      expect(p1.optionId, isNot(equals(p2.optionId)));
    });

    test('optionId folds duplicate profiles across extruders', () {
      const pExtruder0 = KProfile(
        slotId: 1,
        extruderId: 0,
        name: 'Bambu PLA Basic',
        kValue: '0.020000',
        filamentId: 'GFL99',
      );
      const pExtruder1 = KProfile(
        slotId: 5,
        extruderId: 1,
        name: 'Bambu PLA Basic',
        kValue: '0.020000',
        filamentId: 'GFL99',
      );

      expect(pExtruder0.optionId, equals(pExtruder1.optionId));
    });
  });
}
