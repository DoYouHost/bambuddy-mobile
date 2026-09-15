import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
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
  SlicerRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Fallback for whether the process-override panel can be offered, used until
  /// a [presetValues] call has answered it.
  final ServerVersionService? _serverVersion;

  /// Whether this server accepts `process_overrides` on a slice request.
  ///
  /// What `GET /slicer/preset-values` did outranks the version, and a 403
  /// outranks both. This is about the *route*, not about `resolved`: a server
  /// answering `resolved: false` supports overrides, it just could not read the
  /// preset. Unknown → hidden, because nothing forbids extra fields in
  /// `SliceRequest` and an older server drops them without a word.
  late final _processOverrides = ObservedCapability(
    ServerFeature.processOverrides,
    _serverVersion,
  );

  Future<bool> supportsProcessOverrides() => _processOverrides.supported;

  /// Whether `auto_orient` / `auto_arrange` reach the slicer. Version-only:
  /// they are request fields with no route of their own to probe, and an older
  /// server drops them silently.
  Future<bool> supportsLayoutOptions() async =>
      await _serverVersion?.supports(ServerFeature.sliceLayoutOptions) ?? false;

  /// GET /slicer/presets — printer/process/filament options across all tiers.
  Future<UnifiedPresets> presets({bool refresh = false}) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.slicerPresets,
      queryParameters: refresh ? {'refresh': true} : null,
    );
    return UnifiedPresets.fromJson(res.data ?? const {});
  });

  /// Filament slots a model needs, one per **project** slot.
  ///
  /// `full_slots` is what makes this correct for slicing rather than for
  /// print-time AMS matching — the server draws that line itself in
  /// `routes/library.py`. Without it the response holds only the slots the plate
  /// consumes, while `filament_presets` is **positional**, so a file whose only
  /// used slot is 4 offered one picker the slicer bound to slot 1 (server
  /// #2712).
  ///
  /// [plateId] is what makes `used_in_plate` mean anything on a file never
  /// sliced: the server discriminates by running a preview slice, and only when
  /// a plate is named (`if project_filaments and plate_id is not None`). It has
  /// to name the plate the caller will really print — the slice form has no
  /// picker and leaves it at 1, the queue form passes its selection. The preview
  /// is cached per `(kind, source_id, plate_id, content hash)`, so it costs once
  /// per file rather than once per opening.
  ///
  /// Not version-gated (an older server ignores an undeclared query parameter),
  /// and best-effort: any failure degrades to no slots.
  Future<List<FilamentRequirement>> filamentRequirements({
    required int id,
    required bool isArchive,
    int plateId = 1,
  }) async {
    final path = isArchive
        ? Endpoints.archiveFilamentRequirements(id)
        : Endpoints.libraryFileFilamentRequirements(id);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'full_slots': true, 'plate_id': plateId},
      );
      return FilamentRequirement.parseList(res.data ?? const {});
    } on DioException {
      return const [];
    }
  }

  /// GET /slicer/preset-values — the chosen process preset's effective values,
  /// so the override fields start from what it really contains.
  ///
  /// Null means the panel must not be shown: the route is absent (404) or this
  /// caller is refused it (403, the `library:upload` the slice needs too). A
  /// `resolved: false` is a different thing — the route answered but could not
  /// read the preset, so the panel opens on schema defaults.
  ///
  /// Any other failure degrades to [PresetValues.unresolved]; an expired session
  /// is the exception, since swallowing the 401 would leave the user staring at
  /// empty fields with nothing redirecting. The 403 never reaches that arm: it
  /// is a permanent per-permission answer about one route, and a session dialog
  /// over a control the user cannot have is the wrong thing entirely.
  Future<PresetValues?> presetValues(SlicerPreset preset) async {
    try {
      return await _processOverrides.watching(
        () async {
          final res = await _dio.get<Map<String, dynamic>>(
            Endpoints.slicerPresetValues,
            queryParameters: {...preset.toRef(), 'slot': 'process'},
          );
          return PresetValues.fromJson(res.data ?? const {});
        },
        absent: () => null,
        // The preset is a query parameter, not a row the route looks up, so a
        // 404 really is the route and not an unresolvable preset.
        observing: treat404AsAbsent,
      );
    } on AuthException {
      rethrow;
    } on AppApiException {
      return PresetValues.unresolved;
    }
  }

  /// GET /archives/{id}/capabilities — used to gate the archive slice button.
  Future<ArchiveCapabilities> archiveCapabilities(int archiveId) =>
      guard(() async {
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

  /// Not [guard]: these routes answer 400 for three unrelated reasons and the
  /// status names none of them, so the server's `detail` has to survive for
  /// `sliceRefusalMessage` to turn it back into a sentence.
  Future<int> _enqueue(String path, Map<String, dynamic> request) {
    return guardKeepingDetail(() async {
      final res = await _dio.post<Map<String, dynamic>>(path, data: request);
      final id = toIntOrNull(res.data?['job_id']);
      if (id == null) throw const ApiException(AppErrorCode.malformedResponse);
      return id;
    });
  }

  /// GET /slice-jobs/{id} — poll a job's status/progress/result.
  Future<SliceJob> job(int jobId) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(Endpoints.sliceJob(jobId));
    return SliceJob.fromJson(res.data ?? const {});
  });
}
