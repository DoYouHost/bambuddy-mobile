import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// `POST /queue/duplicate` (server #3441) against a real server: which jobs it
/// copies, how it counts the ones it leaves out (a 200 either way), and what a
/// server before it answers.
void main() {
  group('queue duplicate contract', skip: contractSkipReason, () {
    late Dio dio;
    late QueueRepository queue;
    late int printerId;
    late int fileId;
    late bool served;

    setUpAll(() async {
      dio = await authenticatedDio();
      queue = QueueRepository(dio);
      printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      fileId = (await LibraryRepository(dio).listFiles()).first.id;
      served = (await contractServerVersion()).supports(
        ServerFeature.queueDuplicate,
      );
    });

    Future<void> remove(int id) async {
      try {
        await queue.delete(id);
      } on AppApiException {
        // Already gone, which is all the cleanup wanted.
      }
    }

    /// A staged job: `manual_start` keeps the scheduler away from it, so it is
    /// still `pending` when the test looks.
    Future<QueueItem> stage() async {
      final before = {for (final i in await queue.fetch()) i.id};
      await queue.addFromLibraryFile(
        fileId,
        printerId: printerId,
        options: const QueueCreateOptions(manualStart: true),
      );
      final made = (await queue.fetch()).firstWhere(
        (i) => !before.contains(i.id),
      );
      addTearDown(() => remove(made.id));
      return made;
    }

    Future<List<QueueItem>> copiesOf(QueueDuplicateResult result) async {
      for (final id in result.created) {
        addTearDown(() => remove(id));
      }
      final all = await queue.fetch();
      return [
        for (final item in all)
          if (result.created.contains(item.id)) item,
      ];
    }

    test('a staged job is copied to the end of the queue', () async {
      if (!served) return markTestSkipped('the server predates #3440');
      final a = await stage();
      final b = await stage();

      final result = await queue.duplicate([a.id, b.id]);

      expect(result.created, hasLength(2));
      expect(result.skipped, 0);
      final copies = await copiesOf(result);
      expect(copies, hasLength(2));
      for (final copy in copies) {
        expect(copy.statusKind, QueueItemStatusKind.pending);
        expect(copy.libraryFileId, fileId);
        expect(copy.printerId, printerId);
        expect(copy.position, greaterThan(b.position));
      }
    });

    test('what the selection bar sends is accepted as it is', () async {
      if (!served) return markTestSkipped('the server predates #3440');
      final a = await stage();
      final b = await stage();

      // `queue_duplicate_ui_test.dart` records the bar's request.
      final res = (await replayWrites(
        dio,
        recordedWrites('queue_duplicate'),
        ids: {
          'item_ids': [a.id, b.id],
        },
      )).single;

      expect(res.statusCode, 200);
      final body = res.data as Map<String, dynamic>;
      final created = (body['created_ids'] as List).cast<int>();
      for (final id in created) {
        addTearDown(() => remove(id));
      }
      expect(created, hasLength(2));
      expect(body['skipped_count'], 0);
    });

    test(
      'an id sent twice is copied once, and a missing one is skipped',
      () async {
        if (!served) return markTestSkipped('the server predates #3440');
        final a = await stage();

        final result = await queue.duplicate([a.id, a.id, 999999]);

        expect(result.created, hasLength(1));
        expect(result.skipped, 1);
        await copiesOf(result);
      },
    );

    test('a cancelled job gets no copy, and the 200 says so', () async {
      if (!served) return markTestSkipped('the server predates #3440');
      final a = await stage();
      await queue.cancel(a.id);

      final result = await queue.duplicate([a.id]);

      expect(result.created, isEmpty);
      expect(result.skipped, 1);
    });

    test('more than 500 ids go through in two requests', () async {
      if (!served) return markTestSkipped('the server predates #3440');
      final a = await stage();

      // One real job and 500 that do not exist: the route's own limit is 500
      // per request, which a single request of 501 would break with a 422.
      final result = await queue.duplicate([
        a.id,
        for (var i = 0; i < 500; i++) 900000 + i,
      ]);

      expect(result.created, hasLength(1));
      expect(result.skipped, 500);
      await copiesOf(result);
    });

    test('a server before the route answers 404 or 405', () async {
      if (served) return markTestSkipped('the server has the route');

      final answer = await dio.post<dynamic>(
        '/api/v1/queue/duplicate',
        data: {
          'item_ids': [1],
        },
        options: Options(validateStatus: (_) => true),
      );

      expect(answer.statusCode, anyOf(404, 405));
    });
  });
}
