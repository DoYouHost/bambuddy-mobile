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
      expect(repo.isSupported, isTrue);
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
      expect(repo.isSupported, isFalse);
    });

    test('a 403 hides it too — the routes exist but are not ours', () async {
      // Every API-key session lands here: the server denies a key all three
      // pipeline permissions outright.
      adapter.onGet(
        '/api/v1/slicer-pipelines/',
        (s) => s.reply(403, {'detail': 'Forbidden'}),
      );

      expect(await repo.probe(), isFalse);
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
      expect(repo.isSupported, isTrue);

      await expectLater(
        repo.update(999, name: 'x'),
        throwsA(isA<AppApiException>()),
      );
      // Still supported: the collection answered, only that row is missing.
      expect(repo.isSupported, isTrue);
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
