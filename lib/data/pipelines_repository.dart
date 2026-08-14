import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
/// (`/slicer-pipelines`, `/pipeline-runs`).
///
/// Shares the authenticated Dio and maps [DioException] to [AppApiException]
/// like every other repository here.
class PipelinesRepository {
  PipelinesRepository(this._dio);

  final Dio _dio;

  /// Whether the routes answered, once something has asked them.
  ///
  /// Probed rather than versioned, unlike most gates here. The shapes have not
  /// moved since the routes landed (`schemas/slicer_pipeline.py` is identical
  /// across 0.2.4.9, 1.2.5.x and 1.2.6), so only presence is in question — and
  /// presence is what a version answers *worst*: they arrived in 0.2.4.9, which
  /// predates the renumbering to 1.2.5, so a threshold in either scheme
  /// misjudges the other.
  bool? _observedPipelines;

  /// Whether this session was refused the routes outright. The common case, not
  /// an edge one: `core/auth.py` denies an **API-key session all three pipeline
  /// permissions**, so every key gets a 403 whatever `/auth/me` claimed.
  bool _forbidden = false;

  /// Whether the pipeline UI may be offered. `false` until something has been
  /// tried — an entry point leading to a 404 is worse than no entry point.
  bool get isSupported => _observedPipelines == true && !_forbidden;

  /// Ask the list route once so [isSupported] has an answer. Cached for the
  /// repository's life, which ends when credentials change.
  Future<bool> probe() async {
    if (_observedPipelines != null || _forbidden) return isSupported;
    try {
      await list();
    } on AppApiException {
      // list() has already recorded 404 / 403; anything else (offline, 500) is
      // deliberately not cached — it says nothing about the route existing.
    }
    return isSupported;
  }

  /// GET /slicer-pipelines/ — every saved pipeline, newest first.
  Future<List<SlicerPipeline>> list() => _observing(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.slicerPipelines,
        );
        final raw = res.data?['pipelines'];
        return [
          for (final p in (raw as List? ?? const []))
            if (p is Map<String, dynamic>) SlicerPipeline.fromJson(p),
        ];
      });

  /// POST /slicer-pipelines/ — create from a slice form's current selection.
  /// Bundle only; the target needs a follow-up [update].
  Future<SlicerPipeline> create(SlicerPipeline pipeline) =>
      _observing(() async {
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
      _observing(() async {
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

  /// DELETE /slicer-pipelines/{id} — soft server-side, so past runs keep their
  /// name.
  Future<void> delete(int pipelineId) => _observing(() async {
        await _dio.delete<void>(Endpoints.slicerPipeline(pipelineId));
      });

  /// POST /slicer-pipelines/{id}/check-eligibility — the pre-flight.
  Future<EligibilityReport> checkEligibility(
    int pipelineId, {
    required PipelineSource source,
  }) =>
      _observing(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.slicerPipelineCheckEligibility(pipelineId),
          data: source.toJson(),
        );
        return EligibilityReport.fromJson(res.data ?? const {});
      });

  /// POST /slicer-pipelines/{id}/run — slice once, dispatch [copies] prints.
  /// Throws [PipelineNotEligible] on the 409 so the caller can show the report
  /// and offer to repeat with [force].
  Future<PipelineRun> run(
    int pipelineId, {
    required PipelineSource source,
    int copies = 1,
    bool force = false,
  }) =>
      _observing(() async {
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

  /// GET /pipeline-runs — newest first.
  Future<PipelineRunPage> runs({
    int limit = 25,
    int offset = 0,
    int? pipelineId,
    String? status,
  }) =>
      _observing(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.pipelineRuns,
          queryParameters: {
            'limit': limit,
            'offset': offset,
            'pipeline_id': ?pipelineId,
            'status': ?status,
          },
        );
        return PipelineRunPage.fromJson(res.data ?? const {});
      });

  /// GET /pipeline-runs/{id} — the poll target while a run is in flight.
  Future<PipelineRun> runById(int runId) => _observing(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.pipelineRun(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/{id}/cancel — idempotent; a terminal run comes back
  /// unchanged rather than refused.
  Future<PipelineRun> cancel(int runId) => _observing(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunCancel(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/{id}/retry-failed — a **new** run of the parent's
  /// failed + cancelled copies, forced past the pre-flight.
  Future<PipelineRun> retryFailed(int runId) => _observing(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunRetryFailed(runId),
        );
        return PipelineRun.fromJson(res.data ?? const {});
      });

  /// POST /pipeline-runs/clear — drop every terminal run. Returns how many.
  Future<int> clearTerminalRuns() => _observing(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.pipelineRunsClear,
        );
        return toIntOrNull(res.data?['deleted']) ?? 0;
      });

  /// [guard], plus the two answers that settle [isSupported] — 404: not there,
  /// 403: not ours. Every call records them, so the gate keeps improving
  /// without a dedicated request.
  Future<T> _observing<T>(Future<T> Function() body) async {
    try {
      final out = await body();
      _observedPipelines = true;
      _forbidden = false;
      return out;
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 404:
          // Only the collection route settles this. A 404 from `/{id}` means
          // that one pipeline is gone — reading it as "no pipelines here" would
          // hide the whole feature the first time a stale row is opened.
          if (e.requestOptions.path == Endpoints.slicerPipelines) {
            _observedPipelines = false;
          }
        case 403:
          _forbidden = true;
      }
      throw mapDioException(e);
    }
  }
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
