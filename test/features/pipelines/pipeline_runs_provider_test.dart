import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// One run as `PipelineRunResponse` serialises it, with only the fields the
/// dashboard reads filled in.
Map<String, dynamic> runJson(int id, {String status = 'completed'}) => {
  'id': id,
  'pipeline_id': 3,
  'pipeline_name': 'Gridfinity PETG',
  'source_library_file_id': 12,
  'copies': 1,
  'copies_completed': status == 'completed' ? 1 : 0,
  'status': status,
  'eligibility_overridden': false,
  'created_at': '2026-08-10T09:00:00',
  'jobs': const [],
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PipelinesRepository repo;
  late ProviderContainer container;

  /// A `total` larger than the page is what makes `hasMore` true, so every
  /// case here states it rather than counting the rows it happens to send.
  void page({
    required int offset,
    required List<int> ids,
    required int total,
    int limit = PipelinesRepository.pageSize,
  }) => adapter.onGet(
    '/api/v1/pipeline-runs',
    (s) => s.reply(200, {
      'runs': [for (final id in ids) runJson(id)],
      'total': total,
    }),
    queryParameters: {'limit': limit, 'offset': offset},
  );

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = PipelinesRepository(dio);
    container = ProviderContainer(
      overrides: [
        pipelinesRepositoryProvider.overrideWithValue(repo),
        // The notifier subscribes to `pipelineRunUpdates` in build(). The stream
        // is all these cases need — `patch` is driven directly, so the socket
        // never has to open.
        wsClientProvider.overrideWithValue(
          WsClient(
            url: Uri.parse('wss://s.local/api/v1/ws'),
            authHeaders: () async => const {},
            connect: (_, _) => throw StateError('no socket in these tests'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // The list is autoDispose, kept alive in the app by the screen watching it.
    // Without a subscription here every read would rebuild it from loading and
    // no case could see what the one before it left behind.
    container.listen(pipelineRunsProvider, (_, _) {}, fireImmediately: true);
  });

  group('paging', () {
    test('the first page arrives with the total behind it', () async {
      page(offset: 0, ids: [9, 8, 7], total: 7);

      final view = await container.read(pipelineRunsProvider.future);

      expect(view.runs.map((r) => r.id), [9, 8, 7]);
      expect(view.total, 7);
      expect(view.hasMore, isTrue);
      expect(view.loadingMore, isFalse);
    });

    test('loadMore appends rather than replacing', () async {
      page(offset: 0, ids: [9, 8, 7], total: 5);
      page(offset: 3, ids: [6, 5], total: 5);

      await container.read(pipelineRunsProvider.future);
      await container.read(pipelineRunsProvider.notifier).loadMore();

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs.map((r) => r.id), [9, 8, 7, 6, 5]);
      expect(
        view.hasMore,
        isFalse,
        reason: 'five loaded of five — the footer stops offering more',
      );
    });

    test('loadMore is a no-op once everything is loaded', () async {
      // The scroll listener fires on every pixel, so this has to be cheap and
      // silent rather than a request that 200s with an empty page.
      page(offset: 0, ids: [9, 8], total: 2);

      await container.read(pipelineRunsProvider.future);
      await container.read(pipelineRunsProvider.notifier).loadMore();

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs.map((r) => r.id), [9, 8]);
    });

    test('a failed loadMore keeps the pages already read', () async {
      // Emptying a list the user was reading because the next page failed is
      // the worst of both: the error and the loss.
      page(offset: 0, ids: [9, 8, 7], total: 9);
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: {'limit': PipelinesRepository.pageSize, 'offset': 3},
      );

      await container.read(pipelineRunsProvider.future);
      await expectLater(
        container.read(pipelineRunsProvider.notifier).loadMore(),
        throwsA(isA<AppApiException>()),
      );

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs.map((r) => r.id), [9, 8, 7]);
      expect(view.loadingMore, isFalse, reason: 'only the spinner goes');
      expect(view.hasMore, isTrue, reason: 'so the user can try again');
    });

    test('a shrinking total ends the paging instead of stalling it', () async {
      // Runs cleared between two requests: without taking the fresh `total`
      // the footer would keep offering a page that can never arrive.
      page(offset: 0, ids: [9, 8], total: 40);
      page(offset: 2, ids: [7], total: 3);

      await container.read(pipelineRunsProvider.future);
      await container.read(pipelineRunsProvider.notifier).loadMore();

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.total, 3);
      expect(view.hasMore, isFalse);
    });
  });

  group('refreshLoaded', () {
    test('re-reads the window in one request, never below a page', () async {
      // The poll must not throw away the pages past the first, which is what
      // invalidating the provider would do — and it would jump the scroll.
      // A window shorter than a page still asks for a page: there is nothing
      // to gain from a narrower request, and the extra rows are already there.
      page(offset: 0, ids: [9, 8, 7], total: 5);
      page(offset: 3, ids: [6, 5], total: 5);

      await container.read(pipelineRunsProvider.future);
      await container.read(pipelineRunsProvider.notifier).loadMore();
      expect(
        container.read(pipelineRunsProvider).requireValue.runs,
        hasLength(5),
      );

      // One request at the page floor, replacing all five rows.
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {
          'runs': [
            runJson(9, status: 'failed'),
            for (final id in [8, 7, 6, 5]) runJson(id),
          ],
          'total': 5,
        }),
        queryParameters: {'limit': PipelinesRepository.pageSize, 'offset': 0},
      );
      await container.read(pipelineRunsProvider.notifier).refreshLoaded();

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs.map((r) => r.id), [9, 8, 7, 6, 5]);
      expect(
        view.runs.first.status,
        PipelineRunStatus.failed,
        reason: 'the whole window is re-read, not just the first page',
      );
    });

    test('a window past one page is asked for whole', () async {
      final first = [for (var i = 30; i > 5; i--) i]; // 25 rows
      page(offset: 0, ids: first, total: 30);
      page(offset: 25, ids: [5, 4, 3, 2, 1], total: 30);

      await container.read(pipelineRunsProvider.future);
      await container.read(pipelineRunsProvider.notifier).loadMore();
      expect(
        container.read(pipelineRunsProvider).requireValue.runs,
        hasLength(30),
      );

      page(offset: 0, ids: [...first, 5, 4, 3, 2, 1], total: 30, limit: 30);
      await container.read(pipelineRunsProvider.notifier).refreshLoaded();

      expect(
        container.read(pipelineRunsProvider).requireValue.runs,
        hasLength(30),
      );
    });

    test('stops at the cap the route applies silently', () async {
      // `list_all_runs` clamps `limit` to 1..100 without refusing, so asking
      // for more would refresh only as far as the cap while the response looked
      // complete. The request is held to the cap so the two agree.
      const size = PipelinesRepository.pageSize;
      final ids = [for (var i = 150; i > 0; i--) i];
      for (var offset = 0; offset < ids.length; offset += size) {
        page(
          offset: offset,
          ids: ids.skip(offset).take(size).toList(),
          total: ids.length,
        );
      }

      await container.read(pipelineRunsProvider.future);
      while (container.read(pipelineRunsProvider).requireValue.hasMore) {
        await container.read(pipelineRunsProvider.notifier).loadMore();
      }
      expect(
        container.read(pipelineRunsProvider).requireValue.runs,
        hasLength(150),
      );

      final sent = captureRequests(dio);
      page(
        offset: 0,
        ids: ids.take(PipelinesRepository.maxPageSize).toList(),
        total: ids.length,
        limit: PipelinesRepository.maxPageSize,
      );
      await container.read(pipelineRunsProvider.notifier).refreshLoaded();

      expect(
        sent.last.queryParameters['limit'],
        PipelinesRepository.maxPageSize,
      );
      // The window shrinks to what one request can carry, and `total` still
      // says there is more — so the footer keeps offering it.
      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs, hasLength(PipelinesRepository.maxPageSize));
      expect(view.hasMore, isTrue);
    });

    test('a failed refresh keeps the rows and says it failed', () async {
      // The caller is a timer: an exception escaping here is an unhandled async
      // error with nothing waiting to show it, and emptying the list because
      // one poll missed is worse than a stale row.
      page(offset: 0, ids: [9, 8], total: 2);
      await container.read(pipelineRunsProvider.future);

      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(503, {'detail': 'gone away'}),
        queryParameters: {'limit': PipelinesRepository.pageSize, 'offset': 0},
      );

      expect(
        await container.read(pipelineRunsProvider.notifier).refreshLoaded(),
        isFalse,
      );
      expect(
        container.read(pipelineRunsProvider).requireValue.runs.map((r) => r.id),
        [9, 8],
      );
    });
  });

  group('the pushed update', () {
    test('replaces the row it names, in place', () async {
      page(offset: 0, ids: [9, 8, 7], total: 3);
      await container.read(pipelineRunsProvider.future);

      container
          .read(pipelineRunsProvider.notifier)
          .patch(PipelineRun.fromJson(runJson(8, status: 'failed')));

      final view = container.read(pipelineRunsProvider).requireValue;
      expect(view.runs.map((r) => r.id), [9, 8, 7], reason: 'order kept');
      expect(view.runs[1].status, PipelineRunStatus.failed);
      expect(view.runs[0].status, PipelineRunStatus.completed);
    });

    test('a run the list does not hold is ignored, not prepended', () async {
      // Where it belongs in the order depends on the active filter, which a
      // single frame cannot answer — the poll brings it in instead.
      page(offset: 0, ids: [9, 8], total: 2);
      await container.read(pipelineRunsProvider.future);

      container
          .read(pipelineRunsProvider.notifier)
          .patch(PipelineRun.fromJson(runJson(42)));

      expect(
        container.read(pipelineRunsProvider).requireValue.runs.map((r) => r.id),
        [9, 8],
      );
    });

    test('the frame the socket carries is what patch takes', () {
      // Pins the field the server puts the run under: the dashboard parses
      // `frame.run`, and a rename would leave the list silently unpatched.
      final msg = parseWsMessage(
        jsonEncode({'type': 'pipeline_run_updated', 'run': runJson(8)}),
      );

      expect(msg, isA<WsPipelineRunUpdated>());
      final run = PipelineRun.fromJson((msg! as WsPipelineRunUpdated).run);
      expect(run.id, 8);
      expect(run.pipelineName, 'Gridfinity PETG');
    });
  });

  group('the filter', () {
    test('changing it starts the list over', () async {
      page(offset: 0, ids: [9, 8, 7], total: 9);
      await container.read(pipelineRunsProvider.future);

      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {
          'runs': [runJson(4, status: 'failed')],
          'total': 1,
        }),
        queryParameters: {
          'limit': PipelinesRepository.pageSize,
          'offset': 0,
          'status': 'failed',
        },
      );
      container
          .read(pipelineRunFilterProvider.notifier)
          .replace(const PipelineRunFilter(status: 'failed'));

      final view = await container.read(pipelineRunsProvider.future);
      expect(
        view.runs.map((r) => r.id),
        [4],
        reason: 'offsets and total both describe one filtered set',
      );
      expect(view.total, 1);
    });

    test('clear puts every field back', () {
      final notifier = container.read(pipelineRunFilterProvider.notifier);
      notifier.replace(
        const PipelineRunFilter(pipelineId: 7, status: 'failed'),
      );

      notifier.clear();

      expect(container.read(pipelineRunFilterProvider).isEmpty, isTrue);
    });
  });
}
