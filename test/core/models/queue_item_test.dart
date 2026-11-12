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

  group('QueueItem.colorSubstitutions', () {
    QueueItem parse(Object? value) => QueueItem.fromJson({
      'id': 1,
      'position': 1,
      'status': 'completed',
      'color_substitutions': value,
    });

    test('reads every field of an entry', () {
      final sub = parse([
        {
          'slot_id': 2,
          'type': 'PLA',
          'wanted': '#FF0000',
          'got': '#00FF00',
          'tray': 5,
        },
      ]).colorSubstitutions.single;
      expect(sub.slotId, 2);
      expect(sub.type, 'PLA');
      expect(sub.wanted, '#FF0000');
      expect(sub.got, '#00FF00');
      expect(sub.tray, 5);
    });

    test('is empty when an older server omits the field or sends null', () {
      expect(
        QueueItem.fromJson(const {
          'id': 1,
          'position': 1,
          'status': 'pending',
        }).colorSubstitutions,
        isEmpty,
      );
      expect(parse(null).colorSubstitutions, isEmpty);
      expect(parse(const []).colorSubstitutions, isEmpty);
    });

    test('drops a malformed entry and keeps the item and its neighbours', () {
      final item = parse([
        {'slot_id': 1, 'type': 'PLA', 'wanted': '#111111', 'got': '#222222'},
        {'slot_id': 'x'},
        {'slot_id': 5, 'wanted': null},
        {'slot_id': 6, 'wanted': '#555555'},
        'nonsense',
        {'slot_id': 3, 'wanted': '#333333', 'got': '#444444'},
      ]);
      expect(item.colorSubstitutions.map((s) => s.slotId), [1, 3]);
      expect(item.colorSubstitutions.last.type, isEmpty);
      expect(item.colorSubstitutions.last.tray, isNull);
    });

    test('a field that is not a list is no substitutions', () {
      expect(parse('[]').colorSubstitutions, isEmpty);
      expect(parse(const {'slot_id': 1}).colorSubstitutions, isEmpty);
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

  group('gateBlockedModels', () {
    QueueItem job(
      int id, {
      String status = 'pending',
      int? printerId,
      String? model = 'X1C',
      String? reason = kModelGateWaitReason,
    }) => QueueItem.fromJson({
      'id': id,
      'position': id,
      'status': status,
      'printer_id': printerId,
      'target_model': model,
      'waiting_reason': reason,
    });

    test('counts the waiting jobs per model, sorted by name', () {
      expect(gateBlockedModels([job(1), job(2, model: 'A1 mini'), job(3)]), [
        (model: 'A1 mini', waiting: 1),
        (model: 'X1C', waiting: 2),
      ]);
    });

    test('only a pending job with no printer, a model and the gate reason', () {
      expect(
        gateBlockedModels([
          job(1, status: 'printing'),
          job(2, printerId: 3),
          job(3, model: null),
          job(4, model: ''),
          job(5, reason: 'All matching printers are busy'),
          job(6, reason: null),
        ]),
        isEmpty,
      );
    });

    test('nothing in, nothing out', () {
      expect(gateBlockedModels(const []), isEmpty);
    });
  });
}
