import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/printers/nozzle_rack.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The rack as the printer reports it: physical nozzle ids 16–21 for the six
/// docks, and 0 for whatever is currently mounted on the carriage.
NozzleRackSlot _slot(
  int id, {
  String diameter = '0.4',
  String type = 'HS01',
  String color = '00000000',
}) => NozzleRackSlot(
  id: id,
  nozzleDiameter: diameter,
  nozzleType: type,
  filamentColor: color,
);

void main() {
  group('rackCardPositions', () {
    NozzleRackSlot nozzle(int id, {int? addr, String d = '0.4'}) =>
        NozzleRackSlot(id: id, nozzleDiameter: d, addrId: addr);

    test('no rack dock, no card: the hotends alone are not a rack', () {
      expect(rackCardPositions(null, rackPrinter: false), isNull);
      expect(
        rackCardPositions([nozzle(0), nozzle(1)], rackPrinter: false),
        isNull,
      );
    });

    test('an H2C draws six positions and leaves the picked-up one empty', () {
      // `NozzleRackCard`: no recovery of the gap on the picture.
      final card = rackCardPositions([
        nozzle(0),
        nozzle(1),
        for (final id in [16, 18, 19, 20, 21]) nozzle(id),
      ], rackPrinter: false)!;
      expect(card, hasLength(6));
      expect(card[1].slot, isNull);
      expect(card.where((p) => p.mounted), isEmpty);
      expect([for (final p in card) p.position], [1, 2, 3, 4, 5, 6]);
    });

    test('an H3C draws nine and rings the mounted one at its home', () {
      // The capture in the server's test_h3c_ams3h.py: slot 6's hotend on the
      // toolhead, id 0 with addr_id 6, its dock absent.
      final card = rackCardPositions([
        nozzle(0, addr: 6, d: '0.6'),
        for (var i = 0; i < 9; i++)
          if (i != 6) nozzle(16 + i, addr: i),
      ], rackPrinter: true)!;
      expect(card, hasLength(9));
      expect(card[6].mounted, isTrue);
      expect(card[6].slot?.nozzleDiameter, '0.6');
      expect(card.where((p) => p.mounted), hasLength(1));
      expect(card.where((p) => p.slot == null), isEmpty);
    });

    test('an H3C on a server without addr_id leaves the home empty', () {
      final card = rackCardPositions([
        nozzle(0),
        for (var i = 0; i < 8; i++) nozzle(16 + i),
      ], rackPrinter: true)!;
      expect(card[8].slot, isNull);
      expect(card.where((p) => p.mounted), isEmpty);
    });

    test('an addr_id outside the rack places nothing', () {
      final card = rackCardPositions([
        nozzle(0, addr: 12),
        nozzle(16),
      ], rackPrinter: true)!;
      expect(card.where((p) => p.mounted), isEmpty);
    });
  });

  group('rackByPosition', () {
    test('translates physical nozzle ids into 1-based positions', () {
      final rack = rackByPosition([
        for (var id = 16; id <= 21; id++) _slot(id, diameter: '0.${id - 15}'),
      ]);

      expect(rack.keys.toList()..sort(), rackPositions);
      expect(rack[1]?.nozzleDiameter, '0.1');
      expect(rack[6]?.nozzleDiameter, '0.6');
    });

    test('an empty or absent rack is an empty map, not a crash', () {
      expect(rackByPosition(null), isEmpty);
      expect(rackByPosition(const []), isEmpty);
    });

    test('the mounted nozzle fills the one dock the firmware left out', () {
      // Measured server-side on the maintainer's H2C: ids [16, 1, 21, 19, 18,
      // 0, 20] — rack id 17 is the lone gap because that nozzle is on the
      // carriage. It is also the likeliest position to be picked, being the one
      // the last print left mounted, so ruling it out is the wrong answer.
      final rack = rackByPosition([
        _slot(16),
        _slot(0, diameter: '0.8', type: 'HH01'),
        _slot(18),
        _slot(19),
        _slot(20),
        _slot(21),
      ]);

      expect(rack[2]?.nozzleDiameter, '0.8');
      expect(rack.keys.toList()..sort(), rackPositions);
    });

    test(
      'two gaps stay empty — which nozzle is mounted is then unknowable',
      () {
        final rack = rackByPosition([
          _slot(16),
          _slot(0, diameter: '0.8'),
          _slot(19),
          _slot(20),
          _slot(21),
        ]);

        expect(rack.containsKey(2), isFalse);
        expect(rack.containsKey(3), isFalse);
        expect(rack.keys.toList()..sort(), [1, 4, 5, 6]);
      },
    );

    test('an empty carriage fills nothing', () {
      final rack = rackByPosition([
        _slot(16),
        _slot(0, diameter: '', type: ''),
        _slot(18),
        _slot(19),
        _slot(20),
        _slot(21),
      ]);

      expect(rack.containsKey(2), isFalse);
    });

    test('ids that name no rack position are dropped', () {
      // Physical id 1 is the fixed hotend, not a dock, and a record with no id
      // at all is a frame this build cannot place.
      final rack = rackByPosition([
        _slot(1),
        const NozzleRackSlot(nozzleDiameter: '0.4'),
        _slot(16),
      ]);

      expect(rack.keys.toList(), [1]);
    });
  });

  group('rackSlotFits', () {
    test('the slicer pads the diameter and the printer does not', () {
      expect(
        rackSlotFits(
          _slot(16, diameter: '0.4'),
          diameter: '0.40',
          volumeType: '',
        ),
        isTrue,
      );
    });

    test('a different diameter is refused', () {
      expect(
        rackSlotFits(
          _slot(16, diameter: '0.6'),
          diameter: '0.40',
          volumeType: '',
        ),
        isFalse,
      );
    });

    test('an empty dock fits nothing', () {
      expect(
        rackSlotFits(
          _slot(16, diameter: '', type: ''),
          diameter: '0.4',
          volumeType: 'Standard',
        ),
        isFalse,
      );
    });

    test('a diameter neither side can parse is refused, not guessed', () {
      expect(
        rackSlotFits(
          _slot(16, diameter: 'wide'),
          diameter: '0.4',
          volumeType: '',
        ),
        isFalse,
      );
      expect(
        rackSlotFits(
          _slot(16, diameter: '0.4'),
          diameter: '',
          volumeType: '',
        ),
        isFalse,
      );
    });

    test('flow type is matched across the two spellings of it', () {
      final high = _slot(16, type: 'HH01');
      final standard = _slot(16, type: 'HS01');

      expect(
        rackSlotFits(high, diameter: '0.4', volumeType: 'High Flow'),
        isTrue,
      );
      expect(
        rackSlotFits(standard, diameter: '0.4', volumeType: 'Standard'),
        isTrue,
      );
      expect(
        rackSlotFits(high, diameter: '0.4', volumeType: 'Standard'),
        isFalse,
      );
      expect(
        rackSlotFits(standard, diameter: '0.4', volumeType: 'High Flow'),
        isFalse,
      );
    });

    test('a flow type only one side states does not rule the position out', () {
      // The check exists to stop a 0.4 extrusion going through a 0.2 orifice.
      // Silence about flow is not a mismatch, and treating it as one would hide
      // every position from a printer that omits the code.
      expect(
        rackSlotFits(
          _slot(16, type: ''),
          diameter: '0.4',
          volumeType: 'High Flow',
        ),
        isTrue,
      );
      expect(
        rackSlotFits(
          _slot(16, type: 'HH01'),
          diameter: '0.4',
          volumeType: '',
        ),
        isTrue,
      );
    });
  });

  group('flow type', () {
    test('reads the printer code and the slicer name the same way', () {
      expect(highFlowFromCode('HH01'), isTrue);
      expect(highFlowFromCode('hs00'), isFalse);
      expect(highFlowFromName('High Flow'), isTrue);
      expect(highFlowFromName('Standard'), isFalse);
    });

    test('says nothing when nothing was stated', () {
      expect(highFlowFromCode(null), isNull);
      expect(highFlowFromCode('  '), isNull);
      expect(highFlowFromName(null), isNull);
      expect(highFlowFromName(''), isNull);
    });
  });

  group('nozzleDiameterLabel', () {
    test('one spelling for both sides of the row', () {
      expect(nozzleDiameterLabel('0.40'), '0.4');
      expect(nozzleDiameterLabel('0.4'), '0.4');
      expect(nozzleDiameterLabel(' 0.20 '), '0.2');
      expect(nozzleDiameterLabel('1.00'), '1');
    });

    test('anything unparseable is passed through', () {
      expect(nozzleDiameterLabel(null), '');
      expect(nozzleDiameterLabel('wide'), 'wide');
    });
  });

  /// Against the web itself: every answer comes from `utils/nozzleRack.ts`
  /// (`tool/gen_nozzle_rack_golden.sh`).
  group('as the web assigns and offers positions', () {
    final cases = (readFixture('nozzle_rack_golden.json') as List)
        .cast<Map<String, dynamic>>();

    List<NozzleRackSlot> rackOf(Map<String, dynamic> c) => [
      for (final s in (c['rack'] as List).cast<Map<String, dynamic>>())
        NozzleRackSlot.fromJson(s),
    ];
    Map<int, RackGroup> groupsOf(Map<String, dynamic> c) => {
      for (final MapEntry(:key, :value)
          in (c['groups'] as Map<String, dynamic>).entries)
        int.parse(key): RackGroup.fromJson(value as Map<String, dynamic>),
    };

    test('autoAssignRackPositions', () {
      for (final (i, c) in cases.indexed) {
        final pinned = {
          for (final MapEntry(:key, :value)
              in (c['pinned'] as Map<String, dynamic>).entries)
            int.parse(key): value as int,
        };
        final want = (c['assigned'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(int.parse(k), v as int),
        );
        expect(
          autoAssignRackPositions(rackOf(c), groupsOf(c), pinned),
          want,
          reason: 'case $i',
        );
      }
    });

    test('which of the six positions fit a group', () {
      for (final (i, c) in cases.indexed) {
        final rack = rackByPosition(rackOf(c));
        for (final MapEntry(:key, :value) in groupsOf(c).entries) {
          expect(
            [
              for (final p in rackPositions)
                rack[p] != null &&
                    rackSlotFits(
                      rack[p]!,
                      diameter: value.nozzleDiameter,
                      volumeType: value.volumeType,
                    ),
            ],
            (c['eligible'] as Map<String, dynamic>)['$key'],
            reason: 'case $i group $key',
          );
        }
      }
    });
  });
}
