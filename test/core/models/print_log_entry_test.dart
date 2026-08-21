import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully populated run — every field set to something distinguishable, so a
/// field that goes missing on the way through [PrintLogEntry.copyWith] fails an
/// assertion rather than reading as a null the server never sent.
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
    test('carries every field it was not asked to change', () {
      // The merge after a PATCH is the reason this matters: the response omits
      // cost and energy on a server older than 1.2.6, so the local row is what
      // holds them. A field added to the class and forgotten in `copyWith`
      // would blank itself on every edit, silently — this list has to grow with
      // the class.
      final before = _full();

      final after = before.copyWith(status: 'completed');

      expect(after.status, 'completed');
      expect(after.id, before.id);
      expect(after.archiveId, before.archiveId);
      expect(after.printName, before.printName);
      expect(after.printerName, before.printerName);
      expect(after.printerId, before.printerId);
      expect(after.startedAt, before.startedAt);
      expect(after.completedAt, before.completedAt);
      expect(after.durationSeconds, before.durationSeconds);
      expect(after.filamentType, before.filamentType);
      expect(after.filamentColor, before.filamentColor);
      expect(after.filamentUsedGrams, before.filamentUsedGrams);
      expect(after.cost, before.cost);
      expect(after.energyKwh, before.energyKwh);
      expect(after.energyCost, before.energyCost);
      expect(after.failureReason, before.failureReason);
      expect(after.thumbnailPath, before.thumbnailPath);
      expect(after.createdById, before.createdById);
      expect(after.createdByUsername, before.createdByUsername);
      expect(after.createdAt, before.createdAt);
    });

    test('clearing the cause is its own flag, since null means "unchanged"',
        () {
      expect(_full().copyWith(clearFailureReason: true).failureReason, isNull);
      expect(_full().copyWith().failureReason, 'warping');
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
