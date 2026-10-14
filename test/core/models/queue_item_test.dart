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

  group('gateBlockedPrinters', () {
    QueueItem row(
      int id, {
      String status = 'skipped',
      String? error = kPreviousFailureGate,
      int? printerId = 1,
      String? printerName = 'X1C',
    }) => QueueItem.fromJson({
      'id': id,
      'position': 1,
      'status': status,
      'error_message': error,
      'printer_id': printerId,
      'printer_name': printerName,
    });

    String named(int id) => 'Printer #$id';

    test('counts the skipped jobs behind the gate, per printer', () {
      final blocked = gateBlockedPrinters([
        row(1),
        row(2),
        row(3, printerId: 2, printerName: 'A1'),
      ], fallbackName: named);

      expect(blocked, [
        (printerId: 2, name: 'A1', skipped: 1),
        (printerId: 1, name: 'X1C', skipped: 2),
      ], reason: 'by name, as the web sorts them');
    });

    test('another skip reason is not this gate', () {
      expect(
        gateBlockedPrinters([
          row(1, error: 'Filament deficit'),
          row(2, error: null),
        ], fallbackName: named),
        isEmpty,
        reason: 'the resume route restores by the exact gate string only',
      );
    });

    test('only a skipped job counts, whatever it says', () {
      expect(
        gateBlockedPrinters([
          row(1, status: 'pending'),
          row(2, status: 'failed'),
        ], fallbackName: named),
        isEmpty,
      );
    });

    test('a skipped job with no printer has no queue to resume', () {
      expect(
        gateBlockedPrinters([
          row(1, printerId: null, printerName: null),
        ], fallbackName: named),
        isEmpty,
      );
    });

    test('a printer the row does not name gets the fallback', () {
      expect(
        gateBlockedPrinters([
          row(1, printerId: 5, printerName: null),
        ], fallbackName: named).single.name,
        'Printer #5',
      );
    });
  });
}
