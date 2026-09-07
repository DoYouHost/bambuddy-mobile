import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/printers/nozzle_rack.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
