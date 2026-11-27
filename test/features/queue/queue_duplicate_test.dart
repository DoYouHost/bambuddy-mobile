import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A server that records what it was asked to copy and answers as it was told.
class _Server extends QueueRepository {
  _Server() : super(Dio());

  final asked = <List<int>>[];
  int fetches = 0;
  QueueDuplicateResult answer = (created: const [], skipped: 0);
  Object? failure;

  @override
  Future<List<QueueItem>> fetchActive() async {
    fetches++;
    return const [];
  }

  @override
  Future<QueueDuplicateResult> duplicate(List<int> itemIds) async {
    asked.add(itemIds);
    final failure = this.failure;
    if (failure != null) throw failure;
    return answer;
  }
}

QueueItem item(int id, String status, {bool cleanup = false, int? archiveId}) =>
    QueueItem(
      id: id,
      position: id,
      status: status,
      cleanupLibraryAfterDispatch: cleanup,
      archiveId: archiveId,
    );

Future<(_Server, QueueNotifier)> open() async {
  final server = _Server();
  final container = ProviderContainer(
    retry: neverRetry,
    overrides: [
      queueRepositoryProvider.overrideWithValue(server),
      fakeServerProfileOverride(),
    ],
  );
  addTearDown(container.dispose);
  container.listen(queueProvider, (_, _) {});
  await container.read(queueProvider.future);
  return (server, container.read(queueProvider.notifier));
}

void main() {
  group('which jobs can be copied', () {
    // `canDuplicate` in QueuePage.tsx and `_DUPLICABLE_STATUSES` on the server:
    // the wire status, compared exactly.
    for (final (status, expected) in const [
      ('pending', true),
      ('printing', true),
      ('scheduled', false),
      ('paused', false),
      ('completed', false),
      ('cancelled', false),
      ('failed', false),
      ('skipped', false),
      ('PENDING', false),
      ('', false),
    ]) {
      test('a $status job ${expected ? 'can' : 'cannot'}', () {
        expect(item(1, status).canDuplicate, expected);
      });
    }

    test('a job whose archive was deleted is left out, as the server does', () {
      final deleted = QueueItem.fromJson({
        'id': 1,
        'position': 1,
        'status': 'pending',
        'archive_id': 7,
        'archive_deleted': true,
      });

      expect(deleted.canDuplicate, isFalse);
    });

    test(
      'a printer-card upload goes with its file, unless it has an archive',
      () {
        expect(item(1, 'pending', cleanup: true).canDuplicate, isFalse);
        expect(
          item(1, 'pending', cleanup: true, archiveId: 9).canDuplicate,
          isTrue,
        );
      },
    );

    test('the flag is read off the queue row, and missing means no', () {
      QueueItem parse(Map<String, Object?> extra) => QueueItem.fromJson({
        'id': 1,
        'position': 1,
        'status': 'pending',
        ...extra,
      });

      expect(
        parse({'cleanup_library_after_dispatch': true}).canDuplicate,
        isFalse,
      );
      expect(parse(const {}).canDuplicate, isTrue);
    });
  });

  group('the notifier', () {
    test(
      'sends what the route can copy and counts the rest as not copied',
      () async {
        final (server, notifier) = await open();
        server.answer = (created: const [31, 32], skipped: 1);

        final result = await notifier
            .duplicate(logId: 'queue.action.duplicate', [
              item(1, 'pending'),
              item(2, 'printing'),
              item(3, 'completed'),
              item(4, 'pending', cleanup: true),
              item(5, 'pending'),
            ]);

        expect(server.asked, [
          [1, 2, 5],
        ]);
        expect(result.outcome.isOk, isTrue);
        expect(result.added, 2);
        // Two left out here, one more by the server.
        expect(result.notCopied, 3);
      },
    );

    test('nothing the route can copy sends nothing', () async {
      final (server, notifier) = await open();

      final result = await notifier.duplicate(logId: 'queue.action.duplicate', [
        item(1, 'completed'),
        item(2, 'cancelled'),
      ]);

      expect(server.asked, isEmpty);
      expect(result.added, 0);
      expect(result.notCopied, 2);
      expect(
        await notifier.duplicate(const [], logId: 'queue.action.duplicate'),
        (outcome: ActionOutcome.ok, added: 0, notCopied: 0),
      );
    });

    test('a failed later piece still reloads the list', () async {
      final (server, notifier) = await open();
      final before = server.fetches;
      server.failure = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 500,
      );

      final result = await notifier.duplicate([
        for (var i = 1; i <= QueueRepository.duplicateBatchLimit + 1; i++)
          item(i, 'pending'),
      ], logId: 'queue.action.duplicate');

      expect(result.outcome.isOk, isFalse);
      expect(
        server.fetches,
        greaterThan(before),
        reason: 'the first 500 may be copied already',
      );
    });

    test(
      'a failed single piece copied nothing, so it does not reload',
      () async {
        final (server, notifier) = await open();
        final before = server.fetches;
        server.failure = const ApiException(
          AppErrorCode.badResponse,
          statusCode: 500,
        );

        await notifier.duplicate([
          item(1, 'pending'),
        ], logId: 'queue.action.duplicate');

        expect(server.fetches, before);
      },
    );

    test('a refusal is the outcome, with nothing counted as added', () async {
      final (server, notifier) = await open();
      server.failure = const ApiException(
        AppErrorCode.forbidden,
        statusCode: 403,
      );

      final result = await notifier.duplicate(logId: 'queue.action.duplicate', [
        item(1, 'pending'),
      ]);

      expect(result.outcome.isForbidden, isTrue);
      expect(result.added, 0);
    });
  });
}
