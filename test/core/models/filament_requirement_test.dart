import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilamentRequirement', () {
    test('fromJson parses slot, material and rack group', () {
      final json = {
        'slot_id': 2,
        'type': 'PETG',
        'color': '#00FF00',
        'used_in_plate': true,
        'group_id': 1,
        'group': {
          'on_rack': true,
          'nozzle_diameter': '0.40',
          'volume_type': 'Standard',
          'filament_color': '#00FF00',
        },
      };

      final req = FilamentRequirement.fromJson(json);

      expect(req.slotId, 2);
      expect(req.type, 'PETG');
      expect(req.color, '#00FF00');
      expect(req.usedInPlate, isTrue);
      expect(req.groupId, 1);
      expect(req.group, isNotNull);
      expect(req.group!.onRack, isTrue);
      expect(req.group!.nozzleDiameter, '0.40');
      expect(req.group!.volumeType, 'Standard');
      expect(req.group!.filamentColor, '#00FF00');
    });

    test('parseList parses list of requirements, skipping non-maps', () {
      final json = {
        'filaments': [
          {'slot_id': 1, 'type': 'PLA', 'color': '#FF0000'},
          'invalid_string',
          42,
          {'slot_id': 2, 'type': 'PETG', 'color': '#0000FF', 'used_in_plate': false},
        ],
      };

      final list = FilamentRequirement.parseList(json);

      expect(list, hasLength(2));
      expect(list[0].slotId, 1);
      expect(list[0].type, 'PLA');
      expect(list[0].usedInPlate, isTrue); // default

      expect(list[1].slotId, 2);
      expect(list[1].type, 'PETG');
      expect(list[1].usedInPlate, isFalse);
    });

    test('parseList returns empty list on non-list filaments key', () {
      expect(FilamentRequirement.parseList({'filaments': null}), isEmpty);
      expect(FilamentRequirement.parseList({'filaments': 'not a list'}), isEmpty);
      expect(FilamentRequirement.parseList(const {}), isEmpty);
    });

    test('anyUnused detects unused slots in list', () {
      final allUsed = [
        const FilamentRequirement(slotId: 1, usedInPlate: true),
        const FilamentRequirement(slotId: 2, usedInPlate: true),
      ];
      expect(anyUnused(allUsed), isFalse);

      final withUnused = [
        const FilamentRequirement(slotId: 1, usedInPlate: true),
        const FilamentRequirement(slotId: 2, usedInPlate: false),
      ];
      expect(anyUnused(withUnused), isTrue);
    });

    group('RackGroup', () {
      test('equality and hashCode work by value', () {
        const g1 = RackGroup(
          onRack: true,
          nozzleDiameter: '0.40',
          volumeType: 'Standard',
          filamentColor: '#FF0000',
        );
        const g2 = RackGroup(
          onRack: true,
          nozzleDiameter: '0.40',
          volumeType: 'Standard',
          filamentColor: '#FF0000',
        );
        const g3 = RackGroup(
          onRack: false,
          nozzleDiameter: '0.40',
          volumeType: 'Standard',
          filamentColor: '#FF0000',
        );

        expect(g1, equals(g2));
        expect(g1.hashCode, equals(g2.hashCode));
        expect(g1, isNot(equals(g3)));
      });
    });
  });
}
