import 'package:bambuddy_mobile/core/models/archive_slim.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/core/models/print_run.dart';
import 'package:flutter_test/flutter_test.dart';

/// One run reaches the app through two routes with different payloads, and
/// both have to answer the shared questions the same way — that is the whole
/// point of [PrintRun].
void main() {
  group('the failure vocabulary', () {
    test('is the pair the server analyses and the archive list hides', () {
      expect(printRunIsFailure('failed'), isTrue);
      expect(printRunIsFailure('aborted'), isTrue);
    });

    test('leaves a cancelled or skipped run out of it', () {
      // Cancelling is a decision, not a fault, and grouping causes inside
      // these statuses is what makes a cause visible at all.
      expect(printRunIsFailure('cancelled'), isFalse);
      expect(printRunIsFailure('stopped'), isFalse);
      expect(printRunIsFailure('skipped'), isFalse);
      expect(printRunIsFailure('completed'), isFalse);
      expect(printRunIsFailure(null), isFalse);
    });

    test('does not guess about a status this build has not heard of', () {
      expect(printRunIsFailure('quarantined'), isFalse);
      expect(printRunIsSuccess('quarantined'), isFalse);
    });

    test('`aborted` is countable but not writable', () {
      // The PATCH route rejects it, so the picker must not offer it — a row
      // keeps it only as long as nothing else is written over it.
      expect(printLogStatuses.contains('aborted'), isFalse);
    });

    test('success is completion, whatever the casing', () {
      expect(printRunIsSuccess('completed'), isTrue);
      expect(printRunIsSuccess('Completed'), isTrue);
      expect(printRunIsSuccess('failed'), isFalse);
      expect(printRunIsSuccess(null), isFalse);
    });
  });

  group('both shapes of the same run agree', () {
    final started = DateTime.utc(2026, 3, 12, 14);
    final created = DateTime.utc(2026, 3, 12, 13);

    PrintRun fromLog(String status) => PrintLogEntry(
      id: 1,
      status: status,
      createdAt: created,
      startedAt: started,
      durationSeconds: 900,
      filamentColor: '#aabbcc,#112233',
    );

    PrintRun fromSlim(String status) => ArchiveSlim(
      status: status,
      createdAt: created,
      startedAt: started,
      actualTimeSeconds: 900,
      filamentColor: '#aabbcc,#112233',
    );

    test('on what counts as a failure', () {
      for (final status in ['failed', 'aborted', 'completed', 'cancelled']) {
        expect(
          fromLog(status).countsAsFailure,
          fromSlim(status).countsAsFailure,
          reason: 'disagreed about "$status"',
        );
        expect(
          fromLog(status).isSuccess,
          fromSlim(status).isSuccess,
          reason: 'disagreed about "$status"',
        );
      }
    });

    test('on the measured duration, under two wire names', () {
      // `duration_seconds` on `/print-log/`, `actual_time_seconds` on
      // `/archives/slim` — one column either way.
      expect(fromLog('completed').runSeconds, 900);
      expect(fromSlim('completed').runSeconds, 900);
    });

    test('on the colour and the date the run is filed under', () {
      expect(fromLog('completed').primaryColor, '#AABBCC');
      expect(fromSlim('completed').primaryColor, '#AABBCC');
      expect(fromLog('completed').filamentColors, ['#aabbcc', '#112233']);
      expect(fromSlim('completed').filamentColors, ['#aabbcc', '#112233']);
      expect(fromLog('completed').displayDate, started);
      expect(fromSlim('completed').displayDate, started);
    });

    test('a run that never started is filed under when it was written', () {
      // A queue-skipped run has no `started_at` at all, and the list still has
      // to sort and group it somewhere.
      expect(
        PrintLogEntry(id: 1, status: 'skipped', createdAt: created).displayDate,
        created,
      );
      expect(
        ArchiveSlim(status: 'skipped', createdAt: created).displayDate,
        created,
      );
    });
  });
}
