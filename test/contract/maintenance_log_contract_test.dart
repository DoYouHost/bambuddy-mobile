import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// The log of resets (server #3557) against a real server: that a reset enters
/// it with its comment and the user, what the CSV holds, and what the cleanup
/// and the delete answer. A server before the log answers 404 or 405.
void main() {
  group('maintenance log contract', skip: contractSkipReason, () {
    late Dio dio;
    late MaintenanceRepository repo;
    late bool served;
    late PrinterMaintenanceOverview printer;
    late MaintenanceStatus item;

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = MaintenanceRepository(dio);
      served = (await contractServerVersion()).supports(
        ServerFeature.maintenanceLog,
      );
      final overview = await repo.fetchOverview();
      printer = overview.firstWhere((p) => p.maintenanceItems.isNotEmpty);
      item = printer.maintenanceItems.first;
    });

    test('a server before the log answers 404 or 405', () async {
      if (served) return markTestSkipped('the server has the log');

      final answer = await dio.get<dynamic>(
        '/api/v1/maintenance/printers/${printer.printerId}/log',
        options: Options(validateStatus: (_) => true),
      );

      expect(answer.statusCode, anyOf(404, 405));
    });

    test('a reset enters the log with its comment and who made it', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      final before = (await repo.fetchLog(printer.printerId)).total;

      await repo.perform(item.id, notes: 'contract reset');

      final page = await repo.fetchLog(printer.printerId);
      expect(page.total, before + 1);
      final latest = page.items.first;
      expect(latest.notes, 'contract reset');
      expect(latest.printerId, printer.printerId);
      expect(latest.maintenanceTypeId, item.maintenanceTypeId);
      expect(latest.maintenanceTypeName, item.maintenanceTypeName);
      expect(latest.performedAtDate, isNotNull);
      addTearDown(() => repo.deleteLogEntry(latest.id));
    });

    test('pages hold what they say, newest first', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'page one');
      await repo.perform(item.id, notes: 'page two');
      final all = await repo.fetchLog(printer.printerId, limit: 500);
      for (final e in all.items.take(2)) {
        addTearDown(() => repo.deleteLogEntry(e.id));
      }

      final first = await repo.fetchLog(printer.printerId, limit: 1);
      final second = await repo.fetchLog(
        printer.printerId,
        limit: 1,
        offset: 1,
      );

      expect(first.items, hasLength(1));
      expect(first.total, all.total);
      expect(first.items.single.id, all.items[0].id);
      expect(second.items.single.id, all.items[1].id);
      expect(first.items.single.notes, 'page two');
    });

    test('the CSV opens with a byte order mark and the header row', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'csv, with a comma');
      final latest = (await repo.fetchLog(printer.printerId)).items.first;
      addTearDown(() => repo.deleteLogEntry(latest.id));

      final file = await repo.exportLog(printerId: printer.printerId);

      expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(file.bytes.skip(3).toList());
      expect(
        text,
        startsWith(
          'Performed at (UTC),Printer,Task,Performed by,Print hours,Comment',
        ),
      );
      expect(text, contains('"csv, with a comma"'));
      expect(file.filename, startsWith('maintenance_log_'));
      expect(file.filename, endsWith('.csv'));
      expect((await repo.exportLog()).bytes, isNotEmpty);
    });

    test('a cleanup of the last day keeps a reset made just now', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'keep me');
      final latest = (await repo.fetchLog(printer.printerId)).items.first;
      addTearDown(() => repo.deleteLogEntry(latest.id));

      // One day is the least the route takes: a reset made a moment ago is out
      // of reach of any cleanup.
      await repo.cleanUpLog(olderThanDays: 1, printerId: printer.printerId);

      final ids = (await repo.fetchLog(
        printer.printerId,
        limit: 500,
      )).items.map((e) => e.id);
      expect(ids, contains(latest.id));
    });

    test('what the screen sends for a cleanup is accepted as it is', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'replayed cleanup');
      final latest = (await repo.fetchLog(printer.printerId)).items.first;
      addTearDown(() => repo.deleteLogEntry(latest.id));

      // `maintenance_log_screen_test.dart` records the cleanup dialog's request.
      final res = (await replayWrites(
        dio,
        recordedWrites('maintenance_log_cleanup'),
        item: printer.printerId,
      )).single;

      expect(res.statusCode, 200);
      expect((res.data as Map<String, dynamic>)['deleted'], isA<int>());
      final after = await repo.fetchLog(printer.printerId, limit: 500);
      expect(
        after.items.any((e) => e.id == latest.id),
        isTrue,
        reason: 'the reset made just now is younger than any age on offer',
      );
    });

    test('what the screen sends for a delete is accepted as it is', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'replayed delete');
      final latest = (await repo.fetchLog(printer.printerId)).items.first;

      final res = (await replayWrites(
        dio,
        recordedWrites('maintenance_log_delete_entry'),
        item: latest.id,
      )).single;

      expect(res.statusCode, 200);
      final after = await repo.fetchLog(printer.printerId, limit: 500);
      expect(after.items.any((e) => e.id == latest.id), isFalse);
    });

    test('a cleanup age out of range is refused, not clamped', () async {
      if (!served) return markTestSkipped('the server predates #3557');

      for (final days in [0, 36501]) {
        final answer = await dio.delete<dynamic>(
          '/api/v1/maintenance/log',
          queryParameters: {'older_than_days': days},
          options: Options(validateStatus: (_) => true),
        );
        expect(answer.statusCode, 422, reason: 'older_than_days=$days');
      }
    });

    test('an entry is deleted once, and a second delete is a 404', () async {
      if (!served) return markTestSkipped('the server predates #3557');
      await repo.perform(item.id, notes: 'delete me');
      final latest = (await repo.fetchLog(printer.printerId)).items.first;

      await repo.deleteLogEntry(latest.id);

      expect(
        (await repo.fetchLog(
          printer.printerId,
          limit: 500,
        )).items.map((e) => e.id),
        isNot(contains(latest.id)),
      );
      await expectLater(
        repo.deleteLogEntry(latest.id),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('a printer that is not there is a 404', () async {
      if (!served) return markTestSkipped('the server predates #3557');

      await expectLater(
        repo.fetchLog(999999),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });
  });
}
