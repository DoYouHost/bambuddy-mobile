import 'dart:convert';

import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every field set to something no default would produce, so a field the copy
  // forgets shows up as a missing key.
  const full = QueueCreateOptions(
    targetModel: 'H2D',
    targetLocation: 'Shelf 2',
    filamentOverrides: [
      {'slot_id': 1, 'type': 'PETG'},
    ],
    amsMapping: [3, -1],
    plateId: 2,
    scheduledTime: '2026-10-23T06:30:00.000Z',
    requirePreviousSuccess: true,
    autoOffAfter: true,
    manualStart: true,
    bedLevelling: CalibrationOption.on,
    flowCali: CalibrationOption.off,
    vibrationCali: false,
    layerInspect: true,
    timelapse: true,
    nozzleOffsetCali: CalibrationOption.auto,
    gcodeInjection: true,
    confirmOutcome: false,
    preheatOverride: 'on',
    preheatChamberTargetOverride: 45,
    nozzleRackChoice: {1: 2},
    batchId: 7,
    costCenterId: 9,
  );

  group('QueueCreateOptions.withOrder', () {
    test('keeps every other field exactly as it was', () {
      final copy = full.withOrder(
        plateId: full.plateId,
        batchId: full.batchId,
        confirmOutcome: full.confirmOutcome,
      );
      expect(copy.toJson(triState: true), full.toJson(triState: true));
      expect(full.toJson(triState: true).keys, hasLength(22));
    });

    test(
      'replaces the plate, the order and the outcome flag, and only those',
      () {
        final copy = full.withOrder(
          plateId: 4,
          batchId: 11,
          confirmOutcome: true,
        );
        final before = full.toJson(triState: true);
        final after = copy.toJson(triState: true);
        expect(after['plate_id'], 4);
        expect(after['batch_id'], 11);
        expect(after['confirm_outcome'], isTrue);
        final changed = {
          for (final k in before.keys)
            // Encoded: a map field is rebuilt on every call, so `!=` would
            // compare identities.
            if (jsonEncode(before[k]) != jsonEncode(after[k])) k,
        };
        expect(changed, {'plate_id', 'batch_id', 'confirm_outcome'});
      },
    );

    test('null clears the three, as a job with no order sends no key', () {
      final json = full
          .withOrder(plateId: null, batchId: null, confirmOutcome: null)
          .toJson(triState: true);
      expect(json.containsKey('plate_id'), isFalse);
      expect(json.containsKey('batch_id'), isFalse);
      expect(json.containsKey('confirm_outcome'), isFalse);
      expect(json['cost_center_id'], 9);
    });
  });
}
