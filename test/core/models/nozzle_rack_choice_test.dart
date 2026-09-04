import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading the H2C rack pick off the wire, in all three places it appears.
///
/// Every one of them has to keep answering "no rack" for a server that predates
/// the feature, because that answer is the whole compatibility gate: the print
/// form offers the choice only when the plate declares filament groups AND the
/// printer reports a rack, so an older server silently gets the behaviour it
/// has always had.
void main() {
  group('PrinterStatus.nozzleRack', () {
    test('reads the six docks and the mounted nozzle', () {
      final status = PrinterStatus.fromJson({
        'id': 1,
        'nozzle_rack': [
          {
            'id': 16,
            'nozzle_type': 'HS01',
            'nozzle_diameter': '0.4',
            'filament_color': 'FF0000FF',
            'filament_type': 'PLA',
          },
          {'id': 0, 'nozzle_type': 'HH01', 'nozzle_diameter': '0.8'},
        ],
      });

      expect(status.nozzleRack, hasLength(2));
      expect(status.nozzleRack!.first.id, 16);
      expect(status.nozzleRack!.first.filamentType, 'PLA');
      expect(status.nozzleRack!.last.nozzleType, 'HH01');
    });

    test('a printer without a rack reads as null, not as an empty rack', () {
      // The WebSocket frame carries `nozzle_rack: []` for every printer, rack
      // or not. Honouring the empty list would let one such frame blank the
      // rack a REST poll had just reported — a rack is fitted hardware, it does
      // not become empty.
      expect(PrinterStatus.fromJson({'id': 1}).nozzleRack, isNull);
      expect(
        PrinterStatus.fromJson({'id': 1, 'nozzle_rack': []}).nozzleRack,
        isNull,
      );
    });

    test('a frame without the field inherits the rack it already knew', () {
      final known = PrinterStatus.fromJson({
        'id': 1,
        'nozzle_rack': [
          {'id': 16, 'nozzle_diameter': '0.4'},
        ],
      });

      final merged = PrinterStatus.fromJson({'id': 1}).mergedWith(known);

      expect(merged.nozzleRack, hasLength(1));
    });

    test('the rack survives the printer going offline', () {
      // Same reason `nozzles` does: it is what the machine physically has, not
      // what it is doing, and it is still there when the power comes back.
      final known = PrinterStatus.fromJson({
        'id': 1,
        'connected': true,
        'nozzle_rack': [
          {'id': 16, 'nozzle_diameter': '0.4'},
        ],
      });

      final offline =
          PrinterStatus.fromJson({'id': 1, 'connected': false}).mergedWith(known);

      expect(offline.nozzleRack, hasLength(1));
    });
  });

  group('FilamentRequirement rack groups', () {
    test('reads the group and its hotend requirement', () {
      final reqs = FilamentRequirement.parseList({
        'filaments': [
          {
            'slot_id': 1,
            'type': 'PLA',
            'color': '#FF0000',
            'group_id': 2,
            'group': {
              'on_rack': true,
              'nozzle_diameter': '0.40',
              'volume_type': 'High Flow',
              'filament_color': '#FF0000',
            },
          },
        ],
      });

      expect(reqs.single.groupId, 2);
      expect(reqs.single.group?.onRack, isTrue);
      expect(reqs.single.group?.nozzleDiameter, '0.40');
      expect(reqs.single.group?.volumeType, 'High Flow');
    });

    test('a slot on the fixed hotend is a group that wants no position', () {
      final reqs = FilamentRequirement.parseList({
        'filaments': [
          {
            'slot_id': 1,
            'group_id': 0,
            'group': {'on_rack': false, 'nozzle_diameter': '0.4'},
          },
        ],
      });

      expect(reqs.single.group?.onRack, isFalse);
    });

    test('a server that does not annotate groups leaves both fields null', () {
      final reqs = FilamentRequirement.parseList({
        'filaments': [
          {'slot_id': 1, 'type': 'PLA', 'color': '#FF0000'},
        ],
      });

      expect(reqs.single.groupId, isNull);
      expect(reqs.single.group, isNull);
    });
  });

  group('QueueItem.nozzleRackChoice', () {
    test('the group ids JSON had to stringify come back as ints', () {
      final item = QueueItem.fromJson({
        'id': 5,
        'position': 1,
        'status': 'pending',
        'nozzle_rack_choice': {'2': 1, '1': 3},
      });

      expect(item.nozzleRackChoice, {2: 1, 1: 3});
    });

    test('no pick and no field both read as null', () {
      QueueItem parse(Map<String, dynamic> extra) => QueueItem.fromJson({
            'id': 5,
            'position': 1,
            'status': 'pending',
            ...extra,
          });

      expect(parse(const {}).nozzleRackChoice, isNull);
      expect(parse({'nozzle_rack_choice': null}).nozzleRackChoice, isNull);
    });
  });
}
