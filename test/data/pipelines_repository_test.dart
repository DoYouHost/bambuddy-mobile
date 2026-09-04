import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// One pipeline as `SlicerPipelineResponse` really serialises it.
Map<String, dynamic> pipelineJson({
  int id = 7,
  String? targetKind = 'printer_class',
  int? targetPrinterId,
  String? targetModelClass,
}) =>
    {
      'id': id,
      'name': 'X2D 0.6 Gridfinity PETG',
      'description': null,
      'printer_preset': {'source': 'local', 'id': '3'},
      'process_preset': {'source': 'standard', 'id': '0.30mm Gridfinity'},
      'filament_presets': [
        {'source': 'local', 'id': '11'},
        {'source': 'standard', 'id': 'Generic ABS'},
      ],
      'bed_type': 'Engineering Plate',
      'target_kind': targetKind,
      'target_printer_id': targetPrinterId,
      'target_model_class': targetModelClass,
      'fanout_strategy': 'max_parallel',
      'created_by': 1,
      'created_at': '2026-08-01T10:00:00',
      'updated_at': '2026-08-01T10:00:00',
    };

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PipelinesRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = PipelinesRepository(dio);
  });

  group('list', () {
    test('parses the bundle and its target', () async {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {
          'pipelines': [
            pipelineJson(targetModelClass: 'X2D'),
          ],
        }),
      );

      final list = await repo.list();

      expect(list, hasLength(1));
      final p = list.single;
      expect(p.name, 'X2D 0.6 Gridfinity PETG');
      expect(p.printerPreset, const PresetRef(source: 'local', id: '3'));
      expect(p.filamentPresets, hasLength(2));
      expect(p.bedType, 'Engineering Plate');
      expect(p.targetKind, PipelineTargetKind.printerClass);
      expect(p.targetModelClass, 'X2D');
      expect(p.fanoutStrategy, FanoutStrategy.maxParallel);
      expect(await repo.isSupported, isTrue);
    });

    test('an unknown target kind or strategy falls back, never throws',
        () async {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {
          'pipelines': [
            {
              ...pipelineJson(),
              'target_kind': 'some_future_kind',
              'fanout_strategy': 'spiral',
            },
          ],
        }),
      );

      final p = (await repo.list()).single;

      expect(p.targetKind, PipelineTargetKind.printerClass);
      expect(p.fanoutStrategy, FanoutStrategy.maxParallel);
    });
  });

  group('isRunnable', () {
    test('a pipeline saved from the slice form has no target yet', () async {
      // The create schema cannot carry one, so this is what every freshly
      // saved bundle looks like — the run button has to say so rather than
      // letting the server answer class_not_set.
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {
          'pipelines': [pipelineJson()],
        }),
      );

      expect((await repo.list()).single.isRunnable, isFalse);
    });

    test('a pinned printer makes it runnable', () async {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {
          'pipelines': [
            pipelineJson(targetKind: 'specific_printer', targetPrinterId: 4),
          ],
        }),
      );

      expect((await repo.list()).single.isRunnable, isTrue);
    });

    test('a class target needs the model, not just the kind', () async {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {
          'pipelines': [
            pipelineJson(targetKind: 'printer_class', targetModelClass: '  '),
          ],
        }),
      );

      expect((await repo.list()).single.isRunnable, isFalse);
    });
  });

  group('create', () {
    test('sends the bundle without the target fields', () async {
      // The create schema does not declare them and Pydantic drops undeclared
      // keys silently, so sending them would look like it had worked.
      late Map<String, dynamic> sent;
      adapter.onPost(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(201, pipelineJson()),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = Map<String, dynamic>.from(o.data as Map);
        h.next(o);
      }));

      await repo.create(
        const SlicerPipeline(
          id: 0,
          name: 'Nightly PETG',
          printerPreset: PresetRef(source: 'local', id: '3'),
          processPreset: PresetRef(source: 'local', id: '9'),
          filamentPresets: [PresetRef(source: 'local', id: '11')],
          bedType: 'Textured PEI Plate',
          // Set here, and still expected not to reach the wire.
          targetKind: PipelineTargetKind.specificPrinter,
          targetPrinterId: 4,
        ),
      );

      expect(sent['name'], 'Nightly PETG');
      expect(sent['printer_preset'], {'source': 'local', 'id': '3'});
      expect(sent['filament_presets'], [
        {'source': 'local', 'id': '11'},
      ]);
      expect(sent['bed_type'], 'Textured PEI Plate');
      expect(sent.containsKey('target_kind'), isFalse);
      expect(sent.containsKey('target_printer_id'), isFalse);
    });
  });

  group('update', () {
    test('omits every field the caller left out', () async {
      late Map<String, dynamic> sent;
      adapter.onPut(
        '/api/v1/slicer-pipelines/7',
        (s) => s.reply(200, pipelineJson()),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = Map<String, dynamic>.from(o.data as Map);
        h.next(o);
      }));

      await repo.update(7, name: 'Renamed');

      expect(sent, {'name': 'Renamed'});
    });

    test('carries the clear sentinels the API defines', () async {
      // `null` cannot clear anything — the route writes every field under an
      // `is not None` guard — so 0 and '' are the only way to un-target.
      late Map<String, dynamic> sent;
      adapter.onPut(
        '/api/v1/slicer-pipelines/7',
        (s) => s.reply(200, pipelineJson()),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = Map<String, dynamic>.from(o.data as Map);
        h.next(o);
      }));

      await repo.update(
        7,
        targetKind: PipelineTargetKind.printerClass,
        targetPrinterId: 0,
        targetModelClass: 'X1C',
        fanoutStrategy: FanoutStrategy.roundRobin,
      );

      expect(sent['target_kind'], 'printer_class');
      expect(sent['target_printer_id'], 0);
      expect(sent['target_model_class'], 'X1C');
      expect(sent['fanout_strategy'], 'round_robin');
    });
  });

  group('run', () {
    test('a 409 yields the eligibility report, not a generic failure',
        () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/run',
        (s) => s.reply(409, {
          'detail': {
            'ok': false,
            'target_kind': 'specific_printer',
            'target_printer_id': 4,
            'target_printer_name': 'X1C left',
            'issues': [
              {'kind': 'printer_offline'},
              {
                'kind': 'filament_type_mismatch',
                'slot_index': 1,
                'expected': 'PETG',
                'actual': 'PLA',
              },
            ],
          },
        }),
        data: Matchers.any,
      );

      await expectLater(
        repo.run(7, source: const PipelineSource.libraryFile(12)),
        throwsA(isA<PipelineNotEligible>().having(
          (e) => e.report.allIssues.map((i) => i.kind),
          'issue kinds',
          containsAll([
            EligibilityIssueKind.printerOffline,
            EligibilityIssueKind.filamentTypeMismatch,
          ]),
        )),
      );
    });

    test('a 409 that is not a report stays an ordinary failure', () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/run',
        (s) => s.reply(409, {'detail': 'Something else conflicted'}),
        data: Matchers.any,
      );

      await expectLater(
        repo.run(7, source: const PipelineSource.libraryFile(12)),
        throwsA(isA<AppApiException>()),
      );
    });

    test('sends exactly one source key plus copies and force', () async {
      late Map<String, dynamic> sent;
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/run',
        (s) => s.reply(202, {'id': 1, 'copies': 3, 'status': 'queued'}),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = Map<String, dynamic>.from(o.data as Map);
        h.next(o);
      }));

      await repo.run(
        7,
        source: const PipelineSource.archive(31),
        copies: 3,
        force: true,
      );

      expect(sent['source_archive_id'], 31);
      expect(sent.containsKey('source_library_file_id'), isFalse);
      expect(sent['copies'], 3);
      expect(sent['force'], isTrue);
    });
  });

  group('support probe', () {
    test('a 404 on the collection means the server has no pipelines',
        () async {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.probe(), isFalse);
      expect(await repo.isSupported, isFalse);
    });

    test('a 403 on the collection hides it — the routes are not ours', () async {
      // Where an API key lands on a server before 1.2.5.3, which denied a key
      // all three pipeline permissions. Nothing can be read, so nothing is
      // offered.
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(403, {'detail': 'Forbidden'}),
      );

      expect(await repo.probe(), isFalse);
      expect(await repo.canRun, isFalse);
      expect(await repo.canWrite, isFalse);
    });

    test('a 404 on one pipeline does not hide the feature', () async {
      // A stale row being gone says nothing about the routes; reading it as
      // "no pipelines here" would take the whole screen away on first open.
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {'pipelines': []}),
      );
      adapter.onGet(
        '/api/v1/slicer-pipelines/999',
        (s) => s.reply(404, {'detail': 'Pipeline not found'}),
      );

      await repo.probe();
      expect(await repo.isSupported, isTrue);

      await expectLater(
        repo.update(999, name: 'x'),
        throwsA(isA<AppApiException>()),
      );
      // Still supported: the collection answered, only that row is missing.
      expect(await repo.isSupported, isTrue);
    });

    test('an offline server is not cached as unsupported', () async {
      // Nothing was learned about the route, so the next attempt must ask
      // again rather than hiding the feature for the session.
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/'),
            reason: 'offline',
          ),
        ),
      );

      expect(await repo.probe(), isFalse);

      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {'pipelines': []}),
      );
      expect(await repo.probe(), isTrue);
    });
  });

  group('the three permission tiers are latched apart', () {
    // `core/auth.py` splits pipelines across three permissions and grants an
    // API key two of them: PIPELINES_READ maps to `can_read_status`,
    // PIPELINES_RUN to `can_queue` + `can_manage_library`, and PIPELINES_WRITE
    // is absent from the scope allowlist, so it answers 403 for a key on every
    // version. One shared flag would take the whole feature away on the first
    // refusal of any one of them.
    setUp(() {
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(200, {'pipelines': []}),
      );
    });

    test('a refused write leaves reading and running alone', () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(403, {'detail': 'API keys cannot be used for '
            'administrative operations'}),
        data: Matchers.any,
      );

      await repo.probe();
      await expectLater(
        repo.create(const SlicerPipeline(
          id: 0,
          name: 'Nightly PETG',
          printerPreset: PresetRef(source: 'local', id: '3'),
          processPreset: PresetRef(source: 'local', id: '9'),
          filamentPresets: [PresetRef(source: 'local', id: '11')],
        )),
        throwsA(isA<AppApiException>()),
      );

      expect(await repo.canWrite, isFalse);
      expect(await repo.isSupported, isTrue,
          reason: 'the list route answered; authoring is a separate permission');
      expect(await repo.canRun, isTrue);
    });

    test('a refused run leaves reading alone', () async {
      // A key carrying `can_read_status` but not both of `can_queue` and
      // `can_manage_library` reads pipelines and cannot dispatch one.
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/run',
        (s) => s.reply(403, {'detail': 'Forbidden'}),
        data: Matchers.any,
      );

      await repo.probe();
      await expectLater(
        repo.run(7, source: const PipelineSource.libraryFile(12)),
        throwsA(isA<AppApiException>()),
      );

      expect(await repo.canRun, isFalse);
      expect(await repo.isSupported, isTrue);
    });

    test('a 404 on one run does not cost the run permission', () async {
      // Cancelling a run that has already been cleared is a missing row, not a
      // missing route — and not a permission this session lost.
      adapter.onPost(
        '/api/v1/pipeline-runs/999/cancel',
        (s) => s.reply(404, {'detail': 'Pipeline run not found'}),
      );

      await repo.probe();
      await expectLater(
        repo.cancel(999),
        throwsA(isA<AppApiException>()),
      );

      expect(await repo.canRun, isTrue);
      expect(await repo.isSupported, isTrue);
    });

    test('absent routes take every tier with them', () async {
      // Each tier answers its own permission only, so presence has to come
      // from the read tier — a server without the routes must not look like one
      // that merely refused the authoring call.
      final bare = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
      DioAdapter(dio: bare).onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );
      final old = PipelinesRepository(bare);

      expect(await old.probe(), isFalse);
      expect(await old.canRun, isFalse);
      expect(await old.canWrite, isFalse);
    });

    test('the probe asks once, however many entry points gate on it', () async {
      var calls = 0;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/api/v1/slicer-pipelines/') calls++;
        h.next(o);
      }));

      await Future.wait([repo.probe(), repo.probe(), repo.probe()]);
      await repo.probe();

      expect(calls, 1);
    });
  });

  group('tolerant parsing', () {
    // These models go through `parseJsonList` / `parseJsonObjectOrNull` rather
    // than a hand-written `is Map<String, dynamic>` filter. Two things that
    // buys, both of which the private versions had lost: a record relayed over
    // a platform channel (typed `Map<Object?, Object?>`) still reads, and one
    // bad entry costs itself instead of the whole list.
    test('one unusable entry does not empty the list around it', () async {
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {
          'runs': [
            {
              'id': 5,
              'copies': 1,
              'status': 'completed',
              'eligibility_overridden': false,
              'created_at': '2026-08-10T09:00:00',
              'jobs': [
                {'id': 1, 'pipeline_run_id': 5, 'copy_index': 0, 'status': 'completed'},
                'not an object at all',
                {'id': 2, 'pipeline_run_id': 5, 'copy_index': 1, 'status': 'failed'},
              ],
            },
            42,
          ],
          'total': 1,
        }),
        queryParameters: {'limit': 25, 'offset': 0},
      );

      final page = await repo.runs();

      expect(page.runs, hasLength(1), reason: 'the number is dropped, not read');
      expect(page.runs.single.jobs.map((j) => j.id), [1, 2],
          reason: 'the string between them costs only itself');
    });

    test('a nested ref survives a map that is not Map<String, dynamic>',
        () async {
      // What a platform channel hands back. The strict type test dropped it,
      // and a pipeline then lost the preset it points at silently.
      final relayed = <Object?, Object?>{'source': 'local', 'id': '3'};
      final pipeline = SlicerPipeline.fromJson({
        'id': 7,
        'name': 'Relayed',
        'printer_preset': relayed,
        'process_preset': {'source': 'local', 'id': '9'},
        'filament_presets': [relayed],
      });

      expect(pipeline.printerPreset, const PresetRef(source: 'local', id: '3'));
      expect(pipeline.filamentPresets, hasLength(1));
    });

    test('a missing preset ref reads as gone from the catalog, not as a throw',
        () async {
      final pipeline = SlicerPipeline.fromJson({
        'id': 7,
        'name': 'Half a bundle',
        'process_preset': {'source': 'local', 'id': '9'},
      });

      expect(pipeline.printerPreset.id, isEmpty);
      expect(pipeline.filamentPresets, isEmpty);
    });
  });

  group('PipelineRunFilter', () {
    test('sends only the keys that are set', () async {
      // The route reads `None` as "do not filter"; an explicit null in a query
      // string arrives as the four characters `None` and filters on that.
      const filter = PipelineRunFilter(status: 'failed', targetModelClass: 'X1C');

      expect(filter.queryParameters, {
        'status': 'failed',
        'target_model_class': 'X1C',
      });
      expect(filter.activeCount, 2);
      expect(filter.isEmpty, isFalse);
      expect(const PipelineRunFilter().queryParameters, isEmpty);
      expect(const PipelineRunFilter().isEmpty, isTrue);
    });

    test('copyWith clears a field with null and leaves an omitted one', () {
      // The opposite rule from the pipeline update body, and the right one for
      // a filter the user is switching off.
      const filter = PipelineRunFilter(
        pipelineId: 7,
        status: 'failed',
        targetPrinterId: 4,
      );

      final cleared = filter.copyWith(status: (value: null));

      expect(cleared.status, isNull);
      expect(cleared.pipelineId, 7, reason: 'omitted, so untouched');
      expect(cleared.targetPrinterId, 4);
      expect(filter.copyWith(pipelineId: (value: 9)).pipelineId, 9);
    });

    test('two filters with the same fields are the same filter', () {
      // The list notifier rebuilds on a filter change, so equality is what
      // stops a re-pick of the value already showing from refetching page one.
      expect(
        const PipelineRunFilter(pipelineId: 7),
        const PipelineRunFilter(pipelineId: 7),
      );
      expect(
        const PipelineRunFilter(pipelineId: 7).hashCode,
        const PipelineRunFilter(pipelineId: 7).hashCode,
      );
      expect(
        const PipelineRunFilter(pipelineId: 7),
        isNot(const PipelineRunFilter(pipelineId: 8)),
      );
    });

    test('the status filter reaches the query, and page 1 comes back',
        () async {
      late Map<String, dynamic> query;
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {'runs': [], 'total': 0}),
        queryParameters: {
          'limit': 25,
          'offset': 50,
          'pipeline_id': 7,
          'status': 'partial_failure',
          'target_printer_id': 4,
          'target_model_class': 'X1C',
        },
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        query = Map<String, dynamic>.from(o.queryParameters);
        h.next(o);
      }));

      await repo.runs(
        offset: 50,
        filter: const PipelineRunFilter(
          pipelineId: 7,
          status: 'partial_failure',
          targetPrinterId: 4,
          targetModelClass: 'X1C',
        ),
      );

      expect(query['limit'], PipelinesRepository.pageSize);
      expect(query['offset'], 50);
      expect(query['pipeline_id'], 7);
      expect(query['status'], 'partial_failure');
      expect(query['target_printer_id'], 4);
      expect(query['target_model_class'], 'X1C');
    });
  });

  group('PipelineRunStatus', () {
    test('every filterable status survives the round trip', () {
      // The filter sends `wire` and the list parses what comes back; a status
      // that did not round-trip would filter to an empty list forever.
      for (final status in PipelineRunStatus.filterable) {
        final wire = status.wire;
        expect(wire, isNotNull, reason: '$status has no wire value');
        expect(PipelineRunStatus.parse(wire), status);
      }
    });

    test('unknown is not offered as something to filter by', () {
      // It stands for a status this build has not heard of, so there is no
      // value to ask the server for.
      expect(PipelineRunStatus.unknown.wire, isNull);
      expect(PipelineRunStatus.filterable,
          isNot(contains(PipelineRunStatus.unknown)));
      expect(PipelineRunStatus.filterable,
          hasLength(PipelineRunStatus.values.length - 1),
          reason: 'every status but unknown can be filtered by');
    });
  });

  group('runs', () {
    test('parses a run, its roll-ups and its per-copy jobs', () async {
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {
          'runs': [
            {
              'id': 5,
              'pipeline_id': 7,
              'pipeline_name': 'Gridfinity',
              'source_library_file_id': 12,
              'source_filename': 'bin.3mf',
              'copies': 4,
              'copies_completed': 2,
              'copies_failed': 1,
              'copies_cancelled': 0,
              'copies_in_progress': 1,
              'status': 'partial_failure',
              'eligibility_overridden': true,
              'created_at': '2026-08-10T09:00:00',
              'jobs': [
                {
                  'id': 1,
                  'pipeline_run_id': 5,
                  'copy_index': 0,
                  'status': 'completed',
                  'assigned_printer_name': 'X1C left',
                },
                {
                  'id': 2,
                  'pipeline_run_id': 5,
                  'copy_index': 1,
                  'status': 'failed',
                  'error_message': 'AMS jam',
                },
              ],
            },
          ],
          'total': 1,
        }),
        queryParameters: {'limit': 25, 'offset': 0},
      );

      final page = await repo.runs();
      final run = page.runs.single;

      expect(page.total, 1);
      expect(run.status, PipelineRunStatus.partialFailure);
      expect(run.status.isTerminal, isTrue);
      expect(run.copiesFinished, 3);
      expect(run.eligibilityOverridden, isTrue);
      expect(run.jobs.map((j) => j.status), [
        PipelineJobStatus.completed,
        PipelineJobStatus.failed,
      ]);
      // failed + cancelled > 0 and the pipeline still exists.
      expect(run.canRetry, isTrue);
    });

    test('an unknown run status is not treated as finished', () async {
      // Stopping the poll on a state this build cannot name would strand the
      // dashboard on a run that is still moving.
      adapter.onGet(
        '/api/v1/pipeline-runs',
        (s) => s.reply(200, {
          'runs': [
            {'id': 1, 'copies': 1, 'status': 'awaiting_slice_slot'},
          ],
          'total': 1,
        }),
        queryParameters: {'limit': 25, 'offset': 0},
      );

      final run = (await repo.runs()).runs.single;

      expect(run.status, PipelineRunStatus.unknown);
      expect(run.status.isTerminal, isFalse);
      expect(run.canRetry, isFalse);
    });
  });

  group('canRetry', () {
    // `retry-failed` has three preconditions server-side and answers 400 on
    // each (`routes/pipeline_runs.py::retry_failed`). Offering the button on a
    // run that fails one of them is a dead end the operator has to read an
    // error to discover.
    PipelineRun run({
      String status = 'partial_failure',
      int? pipelineId = 3,
      int? libraryFileId = 12,
      int? archiveId,
      int failed = 1,
    }) =>
        PipelineRun.fromJson({
          'id': 5,
          'pipeline_id': pipelineId,
          'source_library_file_id': libraryFileId,
          'source_archive_id': archiveId,
          'copies': 2,
          'copies_completed': 2 - failed,
          'copies_failed': failed,
          'status': status,
          'eligibility_overridden': false,
          'created_at': '2026-08-10T09:00:00',
        });

    test('a terminal run with failed copies and both links intact can retry',
        () {
      expect(run().canRetry, isTrue);
      expect(run(libraryFileId: null, archiveId: 4).canRetry, isTrue,
          reason: 'an archive source is the other half of the XOR');
    });

    test('a run still in flight cannot', () {
      expect(run(status: 'in_progress').canRetry, isFalse);
    });

    test('nothing failed, nothing to retry', () {
      expect(run(failed: 0).canRetry, isFalse);
    });

    test('a deleted pipeline takes the retry with it', () {
      expect(run(pipelineId: null).canRetry, isFalse);
    });

    test('a deleted source does too', () {
      // The reachable one: both source columns are `ondelete="SET NULL"`
      // (`models/pipeline_run.py::PipelineRun`), and deleting a library file is
      // a routine act that the run history is designed to outlive. The server
      // then answers 400 "Original source was deleted; cannot retry".
      expect(run(libraryFileId: null).canRetry, isFalse);
      expect(run(libraryFileId: null, archiveId: null).canRetry, isFalse);
    });
  });

  group('checkEligibility', () {
    test('a class report is ok when one printer passes', () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/check-eligibility',
        (s) => s.reply(200, {
          'ok': true,
          'target_kind': 'printer_class',
          'target_model_class': 'X1C',
          'issues': [],
          'printer_reports': [
            {'printer_id': 1, 'printer_name': 'left', 'ok': true, 'issues': []},
            {
              'printer_id': 2,
              'printer_name': 'right',
              'ok': false,
              'issues': [
                {'kind': 'printer_offline'},
              ],
            },
          ],
        }),
        data: Matchers.any,
      );

      final report = await repo.checkEligibility(
        7,
        source: const PipelineSource.libraryFile(12),
      );

      expect(report.ok, isTrue);
      expect(report.eligibleCount, 1);
      expect(report.printerReports, hasLength(2));
      // Per-printer detail is reachable even though the run may proceed.
      expect(report.allIssues.single.kind, EligibilityIssueKind.printerOffline);
    });

    test('filament_unverified is advisory, not blocking', () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/check-eligibility',
        (s) => s.reply(200, {
          'ok': true,
          'target_kind': 'specific_printer',
          'issues': [
            {'kind': 'filament_unverified', 'slot_index': 0},
          ],
        }),
        data: Matchers.any,
      );

      final report = await repo.checkEligibility(
        7,
        source: const PipelineSource.libraryFile(12),
      );

      expect(report.ok, isTrue);
      expect(report.allIssues.single.isAdvisory, isTrue);
    });

    test('an unknown issue kind keeps its raw name', () async {
      adapter.onPost(
        '/api/v1/slicer-pipelines/7/check-eligibility',
        (s) => s.reply(200, {
          'ok': false,
          'issues': [
            {'kind': 'nozzle_diameter_mismatch'},
          ],
        }),
        data: Matchers.any,
      );

      final issue = (await repo.checkEligibility(
        7,
        source: const PipelineSource.libraryFile(12),
      ))
          .allIssues
          .single;

      expect(issue.kind, EligibilityIssueKind.unknown);
      expect(issue.rawKind, 'nozzle_diameter_mismatch');
      expect(issue.isAdvisory, isFalse);
    });
  });

  group('PipelineSource', () {
    test('sets exactly one id — the server 422s on both or neither', () {
      expect(const PipelineSource.libraryFile(3).toJson(),
          {'source_library_file_id': 3});
      expect(const PipelineSource.archive(3).toJson(), {'source_archive_id': 3});
    });
  });
}
