import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive_capabilities.dart';
import '../core/models/filament_requirement.dart';
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

  /// Raw server `AppSettings` map. Feature flags (e.g. `use_slicer_api`,
  /// `require_plate_clear`) derive from this. Best-effort: a read failure
  /// degrades to an empty map rather than throwing, so the rest of the app is
  /// unaffected by an unexpected settings shape.
  Future<Map<String, dynamic>> serverSettings() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.appSettings);
      return res.data ?? const {};
    } on DioException {
      return const {};
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

  /// Filament slots a model needs (one per color). Best-effort: any failure
  /// degrades to a single generic slot so the slice modal still works.
  Future<List<FilamentRequirement>> filamentRequirements({
    required int id,
    required bool isArchive,
  }) async {
    final path = isArchive
        ? Endpoints.archiveFilamentRequirements(id)
        : Endpoints.libraryFileFilamentRequirements(id);
    try {
      final res = await _dio.get<Map<String, dynamic>>(path);
      return FilamentRequirement.parseList(res.data ?? const {});
    } on DioException {
      return const [];
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
