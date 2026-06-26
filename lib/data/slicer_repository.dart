import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive_capabilities.dart';
import '../core/models/slice_job.dart';
import '../core/models/slicer_preset.dart';

/// Server-side slicing (slicer sidecar, gated by `use_slicer_api`).
///
/// Flow: enqueue a slice ([sliceArchive] / [sliceLibraryFile]) → `202 {job_id}`
/// → poll [job] until terminal. Presets for the modal come from [presets].
/// Shares the authenticated Dio. Each method maps [DioException] to
/// [AppApiException].
class SlicerRepository {
  SlicerRepository(this._dio);

  final Dio _dio;

  /// Whether server-side slicing is enabled (`AppSettings.use_slicer_api`).
  /// When false, no slice UI is shown anywhere. Best-effort: a read failure
  /// degrades to `false` rather than throwing, so the rest of the app is
  /// unaffected by an unexpected settings shape.
  Future<bool> isEnabled() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.appSettings);
      return res.data?['use_slicer_api'] == true;
    } on DioException {
      return false;
    }
  }

  /// GET /slicer/presets — printer/process/filament options across all tiers.
  Future<UnifiedPresets> presets({bool refresh = false}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.slicerPresets,
        queryParameters: refresh ? {'refresh': true} : null,
      );
      return UnifiedPresets.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /archives/{id}/capabilities — used to gate the archive slice button.
  Future<ArchiveCapabilities> archiveCapabilities(int archiveId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archiveCapabilities(archiveId),
      );
      return ArchiveCapabilities.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /archives/{id}/slice — enqueue. Returns the new job id.
  Future<int> sliceArchive(int archiveId, Map<String, dynamic> request) =>
      _enqueue(Endpoints.archiveSlice(archiveId), request);

  /// POST /library/files/{id}/slice — enqueue. Returns the new job id.
  Future<int> sliceLibraryFile(int fileId, Map<String, dynamic> request) =>
      _enqueue(Endpoints.libraryFileSlice(fileId), request);

  Future<int> _enqueue(String path, Map<String, dynamic> request) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: request);
      final id = (res.data?['job_id'] as num?)?.toInt();
      if (id == null) throw const ApiException(AppErrorCode.malformedResponse);
      return id;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /slice-jobs/{id} — poll a job's status/progress/result.
  Future<SliceJob> job(int jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.sliceJob(jobId));
      return SliceJob.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
