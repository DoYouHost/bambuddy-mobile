// The setUpAll drives a whole print through the stand-in printer.
@Timeout(Duration(minutes: 6))
library;

import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// An archive's prints as the server lists them (`GET /archives/{id}/runs`),
/// and the two writes that address one print: its note and its verdict.
///
/// On a server before the archive redesign both writes answer 200 and store
/// nothing; that silent drop is why `ArchiveRepository.runsCapability` gates
/// them, and the second half of each test proves the premise.
///
/// **This file moves the seeded printer off its running job**, so it is named
/// to sort last, like the other `ws_` files.
void main() {
  group('archive runs', skip: brokerSkipReason, () {
    late Dio dio;
    late ArchiveRepository archives;
    late PrintLogRepository log;
    late bool served;
    late int archiveId;
    late PrintLogEntry run;

    setUpAll(() async {
      dio = await authenticatedDio();
      archives = ArchiveRepository(dio);
      log = PrintLogRepository(dio);
      served = (await contractServerVersion()).supports(
        ServerFeature.archiveRuns,
      );
      final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      final serial = (printers.first as Map)['serial_number'] as String;

      // Off the seeded job first: a print only starts from an idle printer.
      await publishReport(serial, {'gcode_state': 'FINISH', 'mc_percent': 100});
      await Future<void>.delayed(const Duration(seconds: 3));
      const file = {
        'subtask_name': 'runs-probe.3mf',
        'gcode_file': 'runs-probe.3mf',
      };
      await publishReport(serial, {
        'gcode_state': 'RUNNING',
        'mc_percent': 5,
        ...file,
      });
      archiveId = await pollUntil(
        'the runs-probe archive',
        () async {
          final rows = (await dio.get<List<dynamic>>(Endpoints.archives)).data!;
          for (final row in rows.whereType<Map<String, dynamic>>()) {
            if ('${row['print_name']}'.contains('runs-probe')) {
              return row['id'] as int;
            }
          }
          return null;
        },
        within: const Duration(minutes: 2),
        every: const Duration(seconds: 2),
      );
      await publishReport(serial, {
        'gcode_state': 'FINISH',
        'mc_percent': 100,
        ...file,
      });
      run = await pollUntil(
        'the finished run of the runs-probe archive',
        () async => (await archives.runs(
          archiveId,
        )).where((r) => r.status == 'completed').firstOrNull,
        within: const Duration(minutes: 2),
        every: const Duration(seconds: 2),
      );
    });

    test('the listing carries the per-print keys from the redesign on', () {
      expect(run.archiveId, archiveId);
      expect(run.ownMediaReported, served);
    });

    test('a print takes a note of its own on a server that has it', () async {
      final answered = await log.updateEntry(run.id, notes: 'contract note');
      final stored = (await archives.runs(
        archiveId,
      )).firstWhere((r) => r.id == run.id);

      if (served) {
        expect(answered.notes, 'contract note');
        expect(stored.notes, 'contract note');
        await log.updateEntry(run.id, notes: '');
        final cleared = (await archives.runs(
          archiveId,
        )).firstWhere((r) => r.id == run.id);
        expect(cleared.notes, isNull, reason: 'an empty note clears it');
      } else {
        expect(stored.notes, isNull, reason: 'an older server drops the key');
      }
    });

    test('a verdict with run_id is that print\'s', () async {
      final result = await archives.setVerdict(
        archiveId,
        PrintVerdict.good,
        runId: run.id,
      );
      final stored = (await archives.runs(
        archiveId,
      )).firstWhere((r) => r.id == run.id);

      if (served) {
        expect(result.applied, isTrue);
        expect(stored.userVerdict, PrintVerdict.good);
      } else {
        // `run_id` is dropped and the verdict lands on the archive instead,
        // which is the one print an older server knows.
        expect(result.archive.userVerdict, PrintVerdict.good);
      }
    });

    test('the note the print\'s sheet sends is stored on that print', () async {
      if (!served) return markTestSkipped('the server predates the redesign');
      final answers = await replayWrites(
        dio,
        recordedWrites('archive_run_note'),
        item: run.id,
        itemIn: RegExp(r'(?<=/print-log/)\d+'),
      );

      expect(answers.single.statusCode, 200);
      final stored = (await archives.runs(
        archiveId,
      )).firstWhere((r) => r.id == run.id);
      expect(stored.notes, 'Lids fit');
    });

    test('the verdict the print\'s sheet sends is that print\'s', () async {
      if (!served) return markTestSkipped('the server predates the redesign');
      final answers = await replayWrites(
        dio,
        recordedWrites('archive_run_verdict'),
        item: archiveId,
        itemIn: RegExp(r'(?<=/archives/)\d+'),
        ids: {'run_id': run.id},
      );

      expect(answers.single.statusCode, 200);
      final stored = (await archives.runs(
        archiveId,
      )).firstWhere((r) => r.id == run.id);
      expect(stored.userVerdict, PrintVerdict.good);
      expect(stored.userVerdictSource, 'dialog');
    });
  });
}
