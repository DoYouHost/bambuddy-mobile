import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// `PATCH /queue/bulk` and `POST /queue/printer/{id}/resume` against a real
/// server: what the route does with the keys it gets, and how it counts the rows
/// it will not touch. Both answer 200 for work that was not done, so the counts
/// are what a mocked adapter cannot vouch for.
void main() {
  group('queue bulk edit and resume contract', skip: contractSkipReason, () {
    late Dio admin;
    late QueueRepository queue;
    late int printerId;
    late int fileId;

    setUpAll(() async {
      admin = await authenticatedDio();
      queue = QueueRepository(admin);
      printerId =
          ((await admin.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      fileId = (await LibraryRepository(admin).listFiles()).first.id;
      // The tri-state wire form is read off a queue answer, as in the app.
      await queue.fetch();
    });

    /// A staged job: `manual_start` keeps the scheduler away from it, so it is
    /// still `pending` when the test looks. Removed at the end of the test.
    Future<QueueItem> stage(QueueRepository repo, {int? printer}) async {
      final before = {for (final i in await queue.fetch()) i.id};
      await repo.addFromLibraryFile(
        fileId,
        printerId: printer ?? printerId,
        options: const QueueCreateOptions(manualStart: true),
      );
      final made = (await queue.fetch()).firstWhere(
        (i) => !before.contains(i.id),
      );
      addTearDown(() async {
        try {
          await queue.delete(made.id);
        } on AppApiException {
          // Already gone, which is all the cleanup wanted.
        }
      });
      return made;
    }

    Future<QueueItem> reload(int id) async =>
        (await queue.fetch()).firstWhere((i) => i.id == id);

    test('changes only the keys it was sent, on every pending item', () async {
      final a = await stage(queue);
      final b = await stage(queue);

      final result = await queue.bulkUpdate([
        a.id,
        b.id,
      ], const QueueBulkChanges(timelapse: true, useAms: false));

      expect(result, (updated: 2, skipped: 0));
      for (final id in [a.id, b.id]) {
        final item = await reload(id);
        expect(item.timelapse, isTrue);
        expect(
          item.layerInspect,
          a.layerInspect,
          reason: 'a key that was not sent is left as it was',
        );
        expect(item.printerId, printerId);
      }
    });

    test('a null printer takes the items off theirs', () async {
      final a = await stage(queue);

      final result = await queue.bulkUpdate([
        a.id,
      ], const QueueBulkChanges(printerId: null));

      expect(result, (updated: 1, skipped: 0));
      expect((await reload(a.id)).printerId, isNull);
    });

    test('a printer that does not exist is refused in words', () async {
      final a = await stage(queue);

      await expectLater(
        queue.bulkUpdate([a.id], const QueueBulkChanges(printerId: 999999)),
        throwsA(
          isA<AppApiException>().having(
            (e) => e.detail?.toLowerCase(),
            'detail',
            contains('printer not found'),
          ),
        ),
      );
    });

    test('an item that is not pending is counted, not changed', () async {
      final waiting = await stage(queue);
      final gone = await stage(queue);
      await queue.cancel(gone.id);

      final result = await queue.bulkUpdate([
        waiting.id,
        gone.id,
      ], const QueueBulkChanges(timelapse: true));

      expect(result, (
        updated: 1,
        skipped: 1,
      ), reason: 'a 200 that skipped a row is the whole contract');
      expect((await reload(gone.id)).timelapse, isFalse);
    });

    test(
      'an edit with nothing in it is a 400, so the app never sends one',
      () async {
        final a = await stage(queue);

        await expectLater(
          queue.bulkUpdate([a.id], const QueueBulkChanges()),
          throwsA(
            isA<AppApiException>()
                .having((e) => e.statusCode, 'status', 400)
                .having(
                  (e) => e.detail?.toLowerCase(),
                  'detail',
                  contains('no fields'),
                ),
          ),
        );
      },
    );

    test(
      'auto is stored where the server has it, a boolean everywhere',
      () async {
        final a = await stage(queue);
        final triState = await queue.triStateCapability.supported;

        await queue.bulkUpdate([
          a.id,
        ], const QueueBulkChanges(bedLevelling: CalibrationOption.off));
        expect((await reload(a.id)).bedLevelling, CalibrationOption.off);

        if (!triState) {
          markTestSkipped('this server has no auto to store');
          return;
        }
        await queue.bulkUpdate([
          a.id,
        ], const QueueBulkChanges(bedLevelling: CalibrationOption.auto));
        expect((await reload(a.id)).bedLevelling, CalibrationOption.auto);
      },
    );

    test(
      'a user who may edit only their own items changes only those',
      () async {
        final (dio: student, :me) = await contractUser(admin, const [
          'printers:read',
          'library:read_all',
          'queue:read_own',
          'queue:create',
          'queue:update_own',
          'queue:delete_own',
        ]);
        final theirs = await stage(QueueRepository(student));
        final notTheirs = await stage(queue);
        expect(theirs.createdById, me.id);

        final result = await QueueRepository(student).bulkUpdate([
          theirs.id,
          notTheirs.id,
        ], const QueueBulkChanges(timelapse: true));

        expect(result, (
          updated: 1,
          skipped: 1,
        ), reason: 'the route skips what is not theirs instead of refusing');
        expect((await reload(theirs.id)).timelapse, isTrue);
        expect((await reload(notTheirs.id)).timelapse, isFalse);
      },
    );

    group('resume after failure', () {
      test('a printer with nothing held answers counts, then zeros', () async {
        // The first call may clear what an earlier test left behind; the second
        // never has anything to.
        final first = await queue.resumeAfterFailure(printerId);
        expect(first.acknowledged, greaterThanOrEqualTo(0));
        expect(first.restored, greaterThanOrEqualTo(0));

        expect(await queue.resumeAfterFailure(printerId), (
          acknowledged: 0,
          restored: 0,
        ));
      });

      test('a printer that is gone is a 404', () async {
        await expectLater(
          queue.resumeAfterFailure(999999),
          throwsA(
            isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
          ),
        );
      });

      test('needs queue:update_all, which update_own is not', () async {
        final (dio: student, me: _) = await contractUser(admin, const [
          'printers:read',
          'queue:read_own',
          'queue:update_own',
        ]);

        await expectLater(
          QueueRepository(student).resumeAfterFailure(printerId),
          throwsA(
            isA<AppApiException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.forbidden,
            ),
          ),
        );
      });

      test('the skipped jobs the banner reads come back parsed', () async {
        final skipped = await queue.fetch(status: 'skipped');

        expect(
          skipped.map((i) => i.statusKind).toSet().difference({
            QueueItemStatusKind.skipped,
          }),
          isEmpty,
          reason: 'the status filter is the only way the banner finds them',
        );
        for (final blocked in gateBlockedPrinters(
          skipped,
          fallbackName: (id) => '$id',
        )) {
          expect(blocked.skipped, greaterThan(0));
        }
      });
    });
  });
}
