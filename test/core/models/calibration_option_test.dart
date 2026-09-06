import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading', () {
    test('boolean from an older server', () {
      expect(calibrationFromJson(true), CalibrationOption.on);
      expect(calibrationFromJson(false), CalibrationOption.off);
    });

    test('string from bambuddy 1.2.5+', () {
      expect(calibrationFromJson('on'), CalibrationOption.on);
      expect(calibrationFromJson('off'), CalibrationOption.off);
      expect(calibrationFromJson('auto'), CalibrationOption.auto);
    });

    test('variants the server itself accepts during migration', () {
      // _coerce_tristate accepts 0/1/2 and "true"/"false" — reading a shape
      // the server is willing to write costs nothing.
      expect(calibrationFromJson(0), CalibrationOption.off);
      expect(calibrationFromJson(1), CalibrationOption.on);
      expect(calibrationFromJson(2), CalibrationOption.auto);
      expect(calibrationFromJson('true'), CalibrationOption.on);
      expect(calibrationFromJson('false'), CalibrationOption.off);
    });

    test('letter case and spaces do not matter', () {
      expect(calibrationFromJson(' AUTO '), CalibrationOption.auto);
      expect(calibrationFromJson('On'), CalibrationOption.on);
    });

    test('missing value and junk → auto, never an exception', () {
      for (final junk in [null, '', 'yes', 7, 3.5, <String>[], {}]) {
        expect(
          calibrationFromJson(junk),
          CalibrationOption.auto,
          reason: 'input: $junk',
        );
      }
    });

    test('calibrationOrNull distinguishes "missing" from a value', () {
      expect(calibrationOrNull(null), isNull);
      expect(calibrationOrNull('nonsens'), isNull);
      expect(calibrationOrNull(false), CalibrationOption.off);
    });
  });

  group('writing', () {
    test('on/off always as boolean — every server version understands it', () {
      for (final triState in [true, false]) {
        expect(
          CalibrationOption.on.toWire(triState: triState),
          true,
          reason: 'triState=$triState',
        );
        expect(
          CalibrationOption.off.toWire(triState: triState),
          false,
          reason: 'triState=$triState',
        );
      }
    });

    test(
      'auto as a string only where the server has somewhere to store it',
      () {
        expect(CalibrationOption.auto.toWire(triState: true), 'auto');
        expect(
          CalibrationOption.auto.toWire(triState: false),
          isNull,
          reason: 'null = key omitted, not auto converted to boolean',
        );
      },
    );
  });

  group('queue contract', () {
    // Regression from production: server 1.2.5 sends strings, the generated
    // cast to bool blew up on EVERY record, parseJsonList dropped them and
    // the list came out empty on a valid 200 (docs/plans/07-queue-cali-enum.md).
    Map<String, dynamic> record(Object bed, Object flow, Object nozzle) => {
      'id': 240,
      'position': 1,
      'status': 'pending',
      'bed_levelling': bed,
      'flow_cali': flow,
      'nozzle_offset_cali': nozzle,
      'vibration_cali': false,
      'preheat_override': 'inherit',
    };

    test('a record from server 1.2.5 parses, the list is not empty', () {
      final items = parseJsonList([
        record('off', 'off', 'auto'),
      ], QueueItem.fromJson);
      expect(items, hasLength(1), reason: 'this is that empty screen');
      expect(items.single.bedLevelling, CalibrationOption.off);
      expect(items.single.flowCali, CalibrationOption.off);
      expect(items.single.nozzleOffsetCali, CalibrationOption.auto);
      expect(
        items.single.vibrationCali,
        isFalse,
        reason:
            'vibration_cali did not go through the migration, stays boolean',
      );
    });

    test('a record from an older server still parses the same way', () {
      final items = parseJsonList([
        record(true, false, true),
      ], QueueItem.fromJson);
      expect(items, hasLength(1));
      expect(items.single.bedLevelling, CalibrationOption.on);
      expect(items.single.flowCali, CalibrationOption.off);
      expect(items.single.nozzleOffsetCali, CalibrationOption.on);
    });

    test('both shapes at once do not blow up the whole list', () {
      // Server mid-migration of records: some rows old, some new.
      final items = parseJsonList([
        record(true, false, true),
        record('auto', 'on', 'off'),
      ], QueueItem.fromJson);
      expect(items, hasLength(2));
    });

    test('missing calibration keys → auto, the record stays', () {
      final items = parseJsonList([
        {'id': 1, 'position': 1, 'status': 'pending'},
      ], QueueItem.fromJson);
      expect(items, hasLength(1));
      expect(items.single.bedLevelling, CalibrationOption.auto);
    });
  });
}
