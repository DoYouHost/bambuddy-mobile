import 'package:bambuddy_mobile/core/models/print_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an order from a current server reads every field', () {
    final b = PrintBatch.fromJson({
      'id': 7,
      'name': 'Keychains',
      'quantity': 10,
      'status': 'active',
      'created_at': '2026-09-20T10:00:00',
      'due_date': '2026-09-30T21:59:59',
      'external_source': 'shopify',
      'external_ref': '#1042',
      'completed_count': 4,
      'failed_count': 1,
      'has_targets': true,
      'target_count': 10,
      'remaining_count': 6,
      'dispatchable_count': 4,
      'actual_cost': 1.68,
      'plates': [
        {
          'plate_id': 2,
          'plate_name': 'Rings',
          'quantity_target': 4,
          'remaining': 2,
          'can_dispatch': false,
        },
        {'plate_id': null, 'quantity_target': 6, 'remaining': 4},
      ],
    });

    expect(b.status, PrintBatchStatus.active);
    expect(b.externalRef, '#1042');
    // Naive UTC from the server, local here.
    expect(b.dueDate, DateTime.utc(2026, 9, 30, 21, 59, 59).toLocal());
    expect(b.dispatchable, 4);
    expect(b.stranded, 2);
    expect(b.progressTotal, 10);
    expect(b.plates.first.dispatchable, isFalse);
    expect(b.plates.last.plateId, isNull);
    expect(b.plates.last.dispatchable, isTrue);
  });

  test('a v0.2.4 grouping has only counts and owes nothing', () {
    final b = PrintBatch.fromJson({
      'id': 1,
      'name': 'Stand ×3',
      'quantity': 3,
      'status': 'active',
      'created_at': '2026-04-10T08:00:00',
      'pending_count': 1,
      'printing_count': 1,
      'completed_count': 1,
      'cancelled_count': 0,
    });

    expect(b.hasTargets, isFalse);
    expect(b.plates, isEmpty);
    expect(b.dispatchable, 0);
    expect(b.stranded, 0);
    // What was queued, cancelled runs excluded — the web's denominator.
    expect(b.progressTotal, 3);
  });

  test('1.2.5.3 has no dispatchable counts: every owed run is offered', () {
    final b = PrintBatch.fromJson({
      'id': 1,
      'name': 'x',
      'quantity': 2,
      'status': 'active',
      'has_targets': true,
      'target_count': 2,
      'remaining_count': 2,
      'plates': [
        {'plate_id': 1, 'quantity_target': 2, 'remaining': 2},
      ],
    });

    expect(b.dispatchableCount, isNull);
    expect(b.dispatchable, 2);
    expect(b.stranded, 0);
    expect(b.plates.single.canDispatch, isNull);
    expect(b.plates.single.dispatchable, isTrue);
  });

  test('a status this app does not know is unknown, not a parse failure', () {
    final b = PrintBatch.fromJson({
      'id': 1,
      'name': 'x',
      'quantity': 1,
      'status': 'paused',
    });
    expect(b.status, PrintBatchStatus.unknown);
  });

  test('only an active order with a past due date is overdue', () {
    final now = DateTime(2026, 9, 27, 12);
    PrintBatch make(String status, String? due) => PrintBatch.fromJson({
      'id': 1,
      'name': 'x',
      'quantity': 1,
      'status': status,
      'due_date': due,
    });

    expect(make('active', '2026-09-26T10:00:00').isOverdue(now), isTrue);
    expect(make('active', '2026-09-28T10:00:00').isOverdue(now), isFalse);
    expect(make('completed', '2026-09-26T10:00:00').isOverdue(now), isFalse);
    expect(make('active', null).isOverdue(now), isFalse);
  });
}
