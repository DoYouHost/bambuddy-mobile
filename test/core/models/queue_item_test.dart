import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('QueueItem.fromJson', () {
    test('parses a printing queue item, ignoring unknown fields', () {
      final item = QueueItem.fromJson(
        readFixture('queue_item.json') as Map<String, dynamic>,
      );

      expect(item.id, 78);
      expect(item.position, 1);
      expect(item.status, 'printing');
      expect(item.statusKind, QueueItemStatusKind.printing);
      expect(item.isActive, isTrue);
      expect(item.printerName, 'X2D-3DP');
      expect(
        item.filamentType,
        'PETG, PLA',
        reason: 'the comma-joined types must be preserved',
      );
      expect(
        item.filamentColor,
        contains(','),
        reason: 'a multicolor color is comma-separated',
      );
      expect(item.archiveId, 77);
      expect(item.beenJumped, isFalse);
      expect(item.createdAt, isA<DateTime>());
    });

    test('an unknown status lands in QueueItemStatusKind.unknown', () {
      final item = QueueItem.fromJson(const {
        'id': 1,
        'position': 1,
        'status': 'weird_new_status',
        'extra_unknown_key': 'value_we_dont_know',
      });

      expect(item.statusKind, QueueItemStatusKind.unknown);
      expect(item.isActive, isFalse);
    });

    test('slicer AMS mapping: no field = none (old server)', () {
      final item = QueueItem.fromJson(const {
        'id': 1,
        'position': 1,
        'status': 'pending',
      });
      expect(item.archiveHasSlicerAmsMapping, isFalse);
    });

    test('slicer AMS mapping read when the server reports it', () {
      final item = QueueItem.fromJson(const {
        'id': 1,
        'position': 1,
        'status': 'pending',
        'archive_has_slicer_ams_mapping': true,
      });
      expect(item.archiveHasSlicerAmsMapping, isTrue);
    });
  });

  group('QueueItemStatusKind classification', () {
    QueueItemStatusKind kind(String s) =>
        QueueItem(id: 1, position: 1, status: s).statusKind;

    test('pending and queued → pending', () {
      expect(kind('pending'), QueueItemStatusKind.pending);
      expect(kind('queued'), QueueItemStatusKind.pending);
    });

    test('scheduled → scheduled', () {
      expect(kind('scheduled'), QueueItemStatusKind.scheduled);
    });

    test('printing → printing', () {
      expect(kind('printing'), QueueItemStatusKind.printing);
    });

    test('paused → paused', () {
      expect(kind('paused'), QueueItemStatusKind.paused);
    });

    test('completed → completed', () {
      expect(kind('completed'), QueueItemStatusKind.completed);
    });

    test('cancelled and canceled → cancelled', () {
      expect(kind('cancelled'), QueueItemStatusKind.cancelled);
      expect(kind('canceled'), QueueItemStatusKind.cancelled);
    });

    test('failed and error → failed', () {
      expect(kind('failed'), QueueItemStatusKind.failed);
      expect(kind('error'), QueueItemStatusKind.failed);
    });

    test('an unknown status → unknown', () {
      expect(kind('weird_new_status'), QueueItemStatusKind.unknown);
    });
  });

  group('QueueItem.isActive', () {
    bool active(String s) => QueueItem(id: 1, position: 1, status: s).isActive;

    test('active statuses return true', () {
      expect(active('printing'), isTrue);
      expect(active('paused'), isTrue);
      expect(active('pending'), isTrue);
      expect(active('queued'), isTrue);
      expect(active('scheduled'), isTrue);
    });

    test('finished/failed statuses return false', () {
      expect(active('completed'), isFalse);
      expect(active('cancelled'), isFalse);
      expect(active('failed'), isFalse);
      expect(active('weird_new_status'), isFalse);
    });
  });
}
