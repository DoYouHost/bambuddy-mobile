import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/archive_merge.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ArchiveRepository repo;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    repo = ArchiveRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  group('mergeCount', () {
    test('reads the groups and settles the latch on', () async {
      replyVersion('1.2.6');
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(200, {'groups': 3}),
      );

      expect(await repo.mergeCount(), 3);
      expect(await repo.mergeCapability.supported, isTrue);
    });

    test('an older server\'s 404 is no merge, not an error', () async {
      replyVersion('1.3.1');
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.mergeCount(), 0);
      expect(await repo.mergeCapability.supported, isFalse);
    });

    // `/archives/{archive_id}` takes the path there and refuses the id.
    test('an older server\'s 422 is no merge either', () async {
      replyVersion('1.3.1');
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(422, {
          'detail': [
            {
              'type': 'int_parsing',
              'loc': ['path', 'archive_id'],
            },
          ],
        }),
      );

      expect(await repo.mergeCount(), 0);
      expect(await repo.mergeCapability.supported, isFalse);
    });

    test('a session without both rights is no merge either', () async {
      replyVersion('1.3.1');
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      expect(await repo.mergeCount(), 0);
      expect(await repo.mergeCapability.supported, isFalse);
    });

    test('a server error is still an error', () {
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.mergeCount, throwsA(isA<AppApiException>()));
    });

    test('a body without the number counts as none', () async {
      adapter.onGet('/api/v1/archives/merge-count', (s) => s.reply(200, {}));

      expect(await repo.mergeCount(), 0);
    });
  });

  group('mergePreview', () {
    test('reads each group, its survivor first, and why one waits', () async {
      adapter.onGet(
        '/api/v1/archives/merge-preview',
        (s) => s.reply(200, {
          'groups': [
            {
              'survivor': {
                'id': 3,
                'print_name': 'Handle',
                'filename': 'handle.3mf',
                'created_at': '2026-10-01T10:00:00',
                'run_count': 1,
              },
              'merged': [
                {
                  'id': 9,
                  'print_name': null,
                  'filename': 'handle.3mf',
                  'created_at': '2026-10-03T10:00:00',
                  'run_count': 2,
                },
              ],
              'skipped': null,
            },
            {
              'survivor': {'id': 4, 'filename': 'box.3mf'},
              'merged': [],
              'skipped': 'busy',
            },
            {'survivor': 'nonsense'},
          ],
        }),
      );

      final groups = await repo.mergePreview();

      expect(groups, hasLength(2), reason: 'a malformed group drops itself');
      expect(groups.first.mergeable, isTrue);
      expect(groups.first.survivor.name, 'Handle');
      expect(groups.first.merged.single.name, 'handle.3mf');
      expect(groups.first.merged.single.runCount, 2);
      expect(
        groups.first.survivor.createdAt!.isAtSameMomentAs(
          DateTime.utc(2026, 10, 1, 10),
        ),
        isTrue,
      );
      expect(groups.last.mergeable, isFalse);
      expect(groups.last.skipReason, ArchiveMergeSkip.busy);
    });

    test('a reason this build does not know still leaves the group out', () {
      final group = ArchiveMergeGroup.tryParse({
        'survivor': {'id': 1, 'filename': 'a'},
        'skipped': 'newer_reason',
      })!;

      expect(group.mergeable, isFalse);
      expect(group.skipReason, isNull);
    });
  });

  group('merge', () {
    test('sends the survivors and reads what was merged and left', () async {
      adapter.onPost(
        '/api/v1/archives/merge',
        (s) => s.reply(200, {
          'merged': [
            {
              'survivor_id': 3,
              'merged_ids': [9],
            },
          ],
          'skipped': [
            {'survivor_id': 4, 'reason': 'busy'},
            {'survivor_id': 'x'},
          ],
        }),
        data: Matchers.any,
      );

      final result = await repo.merge([3, 4]);

      expect(sent.last.data, {
        'survivor_ids': [3, 4],
      });
      expect(result.merged, [3]);
      expect(result.skipped.single.survivorId, 4);
      expect(result.skipped.single.reason, 'busy');
    });

    test('an empty answer is nothing merged', () {
      final result = ArchiveMergeResult.fromJson(const {});

      expect(result.merged, isEmpty);
      expect(result.skipped, isEmpty);
    });
  });
}
