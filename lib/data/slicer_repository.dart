import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/archive_capabilities.dart';
import '../core/models/filament_requirement.dart';
import '../core/models/json_utils.dart';
import '../core/models/slice_job.dart';
import '../core/models/slicer_preset.dart';

/// Server-side slicing (slicer sidecar, gated by `use_slicer_api`).
///
/// Flow: enqueue a slice ([sliceArchive] / [sliceLibraryFile]) → `202 {job_id}`
/// → poll [job] until terminal. Presets for the modal come from [presets].
/// Shares the authenticated Dio. Each method maps [DioException] to
/// [AppApiException].
class SlicerRepository {
  SlicerRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Fallback for whether the process-override panel can be offered, used until
  /// a [presetValues] call has answered it.
  final ServerVersionService? _serverVersion;

  /// What `GET /slicer/preset-values` actually did, once it has been called.
  ///
  /// The route arrived in 1.2.6 and 404s before it, which settles the question
  /// outright — so it outranks the version number, as
  /// `QueueRepository._observedTriState` does. Note this is about the *route*,
  /// not about `resolved`: a server that answers `resolved: false` still
  /// supports overrides, it just could not read the preset's values.
  bool? _observedPresetValues;

  /// Whether this server accepts `process_overrides` on a slice request.
  ///
  /// Observation first, version second, `false` when neither knows — the panel
  /// stays hidden rather than collecting edits the server would silently drop
  /// (nothing forbids extra fields in `SliceRequest`, so they vanish without a
  /// word on an older server).
  Future<bool> supportsProcessOverrides() async {
    final observed = _observedPresetValues;
    if (observed != null) return observed;
    return await _serverVersion?.supports(ServerFeature.processOverrides) ??
        false;
  }

  /// Whether `auto_orient` / `auto_arrange` reach the slicer. Version-only:
  /// they are request fields with no route of their own to probe, and an older
  /// server drops them silently.
  Future<bool> supportsLayoutOptions() async =>
      await _serverVersion?.supports(ServerFeature.sliceLayoutOptions) ??
          false;

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
  Future<UnifiedPresets> presets({bool refresh = false}) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.slicerPresets,
          queryParameters: refresh ? {'refresh': true} : null,
        );
        return UnifiedPresets.fromJson(res.data ?? const {});
      });

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

  /// GET /slicer/preset-values — the chosen process preset's effective values,
  /// so the override fields start from what it really contains.
  ///
  /// Null means the route is absent (404, server < 1.2.6) — the panel must not
  /// be shown at all. A [PresetValues] with `resolved: false` means the route
  /// answered but the values could not be read, which is a different thing: the
  /// panel opens with schema defaults and explains why.
  ///
  /// Any other failure degrades to [PresetValues.unresolved] rather than
  /// throwing: a blank panel beats an error dialog over a nicety. Auth is the
  /// exception, as in [guardOrNull] — an expired session has to reach the app
  /// or nothing redirects, and the user is left staring at empty fields.
  Future<PresetValues?> presetValues(SlicerPreset preset) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.slicerPresetValues,
        queryParameters: {...preset.toRef(), 'slot': 'process'},
      );
      _observedPresetValues = true;
      return PresetValues.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _observedPresetValues = false;
        return null;
      }
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return PresetValues.unresolved;
    }
  }

  /// GET /archives/{id}/capabilities — used to gate the archive slice button.
  Future<ArchiveCapabilities> archiveCapabilities(int archiveId) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.archiveCapabilities(archiveId),
        );
        return ArchiveCapabilities.fromJson(res.data ?? const {});
      });

  /// POST /archives/{id}/slice — enqueue. Returns the new job id.
  Future<int> sliceArchive(int archiveId, Map<String, dynamic> request) =>
      _enqueue(Endpoints.archiveSlice(archiveId), request);

  /// POST /library/files/{id}/slice — enqueue. Returns the new job id.
  Future<int> sliceLibraryFile(int fileId, Map<String, dynamic> request) =>
      _enqueue(Endpoints.libraryFileSlice(fileId), request);

  Future<int> _enqueue(String path, Map<String, dynamic> request) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(path, data: request);
        final id = toIntOrNull(res.data?['job_id']);
        if (id == null) throw const ApiException(AppErrorCode.malformedResponse);
        return id;
      });

  /// GET /slice-jobs/{id} — poll a job's status/progress/result.
  Future<SliceJob> job(int jobId) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(Endpoints.sliceJob(jobId));
        return SliceJob.fromJson(res.data ?? const {});
      });
}
