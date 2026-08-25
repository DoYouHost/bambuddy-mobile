import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully populated run — every field set to something distinguishable, so a
/// field that goes missing reads as a wrong value rather than as a null the
/// server never sent.
PrintLogEntry _full() => PrintLogEntry(
      id: 7,
      status: 'failed',
      createdAt: DateTime(2026, 8, 1, 9, 59),
      archiveId: 82,
      printName: 'Benchy',
      printerName: 'P1S',
      printerId: 3,
      startedAt: DateTime(2026, 8, 1, 10),
      completedAt: DateTime(2026, 8, 1, 11, 30),
      durationSeconds: 5400,
      filamentType: 'PLA',
      filamentColor: '#00AE42',
      filamentUsedGrams: 42.5,
      cost: 1.23,
      energyKwh: 0.42,
      energyCost: 0.19,
      failureReason: 'warping',
      thumbnailPath: 'data/thumbs/7.png',
      createdById: 2,
      createdByUsername: 'zosia',
    );

void main() {
  group('copyWith', () {
    // The field list is generated from the constructor now, so "a field added
    // to the class and forgotten in the copy" cannot happen and needs no test
    // enumerating twenty fields. What is still worth pinning is the merge
    // semantics the print-log screen leans on.
    test('carries what it was not asked to change', () {
      final before = _full();

      final after = before.copyWith(status: 'completed');

      expect(after.status, 'completed');
      expect(after.cost, before.cost,
          reason: 'a pre-1.2.6 PATCH answer omits cost; the local row holds it');
      expect(after.energyKwh, before.energyKwh);
      expect(after.energyCost, before.energyCost);
      expect(after.failureReason, before.failureReason);
    });

    // Re-classifying a run to "no cause" has to reach the row as a null. The
    // hand-written copy needed a `clearFailureReason` flag for this, because
    // there a null argument meant "leave it alone"; the generated one nullifies
    // a nullable field on a null and ignores it on a non-nullable one.
    test('a null cause clears it, and an unmentioned field is left alone', () {
      expect(_full().copyWith(failureReason: null).failureReason, isNull);
      expect(_full().copyWith(status: 'completed').failureReason, 'warping');
      expect(_full().copyWith(status: 'completed').status, 'completed');
    });
  });

  group('fromJson', () {
    test('a run whose archive is gone is an orphan, not a broken row', () {
      final entry = PrintLogEntry.fromJson(const {
        'id': 9,
        'status': 'cancelled',
        'archive_id': null,
        'created_at': '2026-08-01T09:00:00',
      });

      expect(entry.isOrphan, isTrue);
      expect(entry.hasThumbnail, isFalse);
      expect(entry.countsAsFailure, isFalse);
    });

    test('the date the list shows falls back when the run never started', () {
      final never = PrintLogEntry.fromJson(const {
        'id': 1,
        'status': 'skipped',
        'created_at': '2026-08-01T09:00:00',
      });
      final started = PrintLogEntry.fromJson(const {
        'id': 2,
        'status': 'completed',
        'created_at': '2026-08-01T09:00:00',
        'started_at': '2026-08-01T10:00:00',
      });

      expect(never.displayDate, never.createdAt);
      expect(started.displayDate, started.startedAt);
    });

    test('`aborted` from the archive side counts as a failure', () {
      // It is outside the PATCH vocabulary but inside what the server's failure
      // analysis groups, which is why the two lists are not one.
      expect(printLogStatusIsFailure('aborted'), isTrue);
      expect(printLogStatuses.contains('aborted'), isFalse);
    });
  });
}
