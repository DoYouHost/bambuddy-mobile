import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/models/json_utils.dart';
import '../core/models/pipeline_run.dart';
import '../core/models/slicer_pipeline.dart';

/// The run was refused by its pre-flight and `force` was not set.
///
/// Not an [AppApiException]: the 409's body *is* the eligibility report, so
/// this is an answer to render rather than a failure to report.
class PipelineNotEligible implements Exception {
  const PipelineNotEligible(this.report);
  final EligibilityReport report;
}

/// Slicer pipelines: reusable preset bundles and the runs they dispatch
/// (`/slicer-pipelines`, `/pipeline-runs`). Shares the authenticated Dio.
class PipelinesRepository {
  PipelinesRepository(this._dio);

  final Dio _dio;

  /// Reading: the routes being there, and this session being allowed to look.
  ///
  /// Probed rather than versioned. Every pipeline route landed in one server
  /// commit and first shipped in 0.2.4.9, which predates the renumbering to
  /// 1.2.5 — so a threshold in either scheme misjudges the other, and the wire
  /// schemas have not moved since anyway. `whenUnknown: false`: an entry point
  /// leading to a 404 is worse than no entry point.
  final _read = ObservedCapability.unversioned(whenUnknown: false);

  /// Dispatching a run (`PIPELINES_RUN`) — refused on its own: a key needs
  /// **both** `can_queue` and `can_manage_library`, because a run slices into
  /// the library and then queues prints (`core/auth.py`).
  final _run = ObservedCapability.unversioned();

  /// Authoring — create, edit, delete, and clearing run history. Outside the
  /// API-key scope allowlist entirely, so a key is refused it on every version.
  final _write = ObservedCapability.unversioned();

  /// Whether the pipeline UI may be offered at all.
  Future<bool> get isSupported => _read.supported;

  /// Whether a run may be dispatched, cancelled or retried. Presence first:
  /// each latch answers its own permission only, so absence belongs to [_read].
  Future<bool> get canRun async =>
      await isSupported && await _run.supported;

  /// Whether a pipeline may be created, edited or deleted.
  Future<bool> get canWrite async =>
      await isSupported && await _write.supported;

  /// Ask the list route once so [isSupported] has an answer. Memoised for the
  /// repository's life, so the entry points gating on it share one request.
  Future<bool> probe() => _probe ??= _firstAsk();
  Future<bool>? _probe;

  Future<bool> _firstAsk() async {
    try {
      await list();
    } on AppApiException catch (e) {
      // 404 and 403 are answers, already recorded by list(). Anything else —
      // offline, 500, a token that expired mid-probe — says nothing, so the
      // memo goes and the next caller asks again.
      if (e.statusCode != 404 && e.statusCode != 403) _probe = null;
    }
    return isSupported;
  }

  /// GET /slicer-pipelines/ — every saved pipeline, newest first.
  Future<List<SlicerPipeline>> list() => _read.watching(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.slicerPipelines,
        );
        return parseJsonList(res.data?['pipelines'], SlicerPipeline.fromJson);
      });

  /// POST /slicer-pipelines/ — bundle only; the target needs a follow-up
  /// [update], which is the only schema that declares it.
  Future<SlicerPipeline> create(SlicerPipeline pipeline) =>
      _write.watching(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.slicerPipelines,
          data: pipeline.toCreateJson(),
        );
        return SlicerPipeline.fromJson(res.data ?? const {});
      });

  /// PUT /slicer-pipelines/{id} — partial: only the arguments passed are sent.
  ///
  /// **Nothing can be cleared with null.** `update_pipeline` writes every field
  /// under an `is not None` guard, so omitting a key and sending null are the
  /// same request. To un-target, pass the server's sentinels:
  /// `targetPrinterId: 0` and `targetModelClass: ''`.
  Future<SlicerPipeline> update(
    int pipelineId, {
    String? name,
    String? description,
    PresetRef? printerPreset,
    PresetRef? processPreset,
    List<PresetRef>? filamentPresets,
    String? bedType,
    PipelineTargetKind? targetKind,
    int? targetPrinterId,
    String? targetModelClass,
    FanoutStrategy? fanoutStrategy,
  }) =>
      _write.watching(observing: _refusalOnly, () async {
        final body = <String, dynamic>{
          'name': ?name,
          'description': ?description,
          'printer_preset': ?printerPreset?.toJson(),
          'process_preset': ?processPreset?.toJson(),
          if (filamentPresets != null)
            'filament_presets': [for (final f in filamentPresets) f.toJson()],
          'bed_type': ?bedType,
          'target_kind': ?targetKind?.wire,
          'target_printer_id': ?targetPrinterId,
          'target_model_class': ?targetModelClass,
          'fanout_strategy': ?fanoutStrategy?.wire,
        };
        final res = await _dio.put<Map<String, dynamic>>(
          Endpoints.slicerPipeline(pipelineId),
          data: body,
        );
        return SlicerPipeline.fromJson(res.data ?? const {});
      });

  /// DELETE /slicer-pipelines/{id} — soft, so past runs keep their name.
  Future<void> delete(int pipelineId) =>
      _write.watching(observing: _refusalOnly, () async {
        await _dio.delete<void>(Endpoints.slicerPipeline(pipelineId));
      });

  /// POST /slicer-pipelines/{id}/check-eligibility — the pre-flight.
  Future<EligibilityReport> checkEligibility(
    int pipelineId, {
    required PipelineSource source,
  }) =>
      _read.watching(observing: _refusalOnly, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.slicerPipelineCheckEligibility(pipelineId),
          data: source.toJson(),
        );
        return EligibilityReport.fromJson(res.data ?? const {});
      });

  /// POST /slicer-pipelines/{id}/run — slice once, dispatch [copies] prints.
  /// Throws [PipelineNotEligible] on the 409, whose body is the report.
  Future<PipelineRun> run(
    int pipelineId, {
    required PipelineSource source,
    int copies = 1,
    bool force = false,
  }) =>
      _run.watching(observing: _refusalOnly, () async {
        try {
          final res = await _dio.post<Map<String, dynamic>>(
            Endpoints.slicerPipelineRun(pipelineId),
            data: {
              ...source.toJson(),
              'copies': copies,
              if (force) 'force': true,
            },
          );
          return PipelineRun.fromJson(res.data ?? const {});
        } on DioException catch (e) {
          final report = _eligibilityFrom(e);
          if (report != null) throw PipelineNotEligible(report);
          rethrow;
        }
      });

  /// The report inside a 409's `detail`, or null for any other conflict —
  /// recognised by its `ok` flag, so a plain-string 409 stays an error.
  EligibilityReport? _eligibilityFrom(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final data = e.response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is! Map || !detail.containsKey('ok')) return null;
    return EligibilityReport.fromJson(
      Map<String, dynamic>.from(detail),
    );
  }

  /// GET /pipeline-runs — newest first, with `total` for the paginator.
  /// [limit] is clamped server-side to 1..100 rather than refused.
  ///
  /// The target filters JOIN to the pipeline's **current** target, not the one
  /// the run was dispatched with, so re-targeting a pipeline moves its whole
  /// history — the server's semantic (`list_all_runs`), and why this is
  /// filtered there rather than here.
  Future<PipelineRunPage> runs({
    int limit = pageSize,
    int offset = 0,
    PipelineRunFilter filter = const PipelineRunFilter(),
  }) =>
      _read.watching(observing: _refusalOnly, () async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.pipelineRuns,
          queryParameters: {
            'limit': limit,
            'offset': offset,
            ...filter.queryParameters,
          },
        );
        return PipelineRunPage.fromJson(res.data ?? const {});
      });

  /// One page of runs — the route's own default.
  static const pageSize = 25;

  /// The server's cap on `limit`, applied silently rather than refused.
  static const maxPageSize = 100;

  /// GET /pipeline-runs/{id}.
  Future<PipelineRun> runById(int runId) =>
      _read.watching(observing: _refusalOnly, () async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.pipelineRun(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/{id}/cancel — idempotent; a terminal run comes back
  /// unchanged rather than refused.
  Future<PipelineRun> cancel(int runId) =>
      _run.watching(observing: _refusalOnly, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunCancel(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/{id}/retry-failed — a **new** run of the parent's
  /// failed + cancelled copies, forced past the pre-flight.
  Future<PipelineRun> retryFailed(int runId) =>
      _run.watching(observing: _refusalOnly, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunRetryFailed(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/clear — drop every terminal run. Returns how many.
  Future<int> clearTerminalRuns() =>
      _write.watching(observing: _refusalOnly, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunsClear,
        );
        return toIntOrNull(res.data?['deleted']) ?? 0;
      });

  /// For a route where only a refusal is worth recording: these are addressed
  /// by row id, and a 404 there is that pipeline or that run being gone. [list]
  /// and [create] keep the default — they address the collection, so a 404 from
  /// them really does mean the routes are absent.
  static const _refusalOnly = {403};
}

/// The file a run slices: exactly one of the two ids, which the server enforces
/// with a validator (both or neither is a 422).
class PipelineSource {
  const PipelineSource.libraryFile(this.id) : isArchive = false;
  const PipelineSource.archive(this.id) : isArchive = true;

  final int id;
  final bool isArchive;

  Map<String, dynamic> toJson() => {
        if (isArchive) 'source_archive_id': id else 'source_library_file_id': id,
      };
}
