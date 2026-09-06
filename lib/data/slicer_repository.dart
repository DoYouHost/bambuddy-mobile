import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
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

  /// Whether this server accepts `process_overrides` on a slice request.
  ///
  /// What `GET /slicer/preset-values` did outranks the version number: the
  /// route arrived in 1.2.6 and 404s before it, which settles the question
  /// outright. A 403 outranks both — the route being there is no use to a
  /// caller who may not call it, and the slice itself needs the same
  /// permission. Note this is about the *route*, not about `resolved`: a server
  /// that answers `resolved: false` still supports overrides, it just could not
  /// read the preset's values. Unknown → hidden, so the panel does not collect
  /// edits the server would silently drop (nothing forbids extra fields in
  /// `SliceRequest`, so they vanish without a word on an older server).
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

  /// Filament slots a model needs, one per **project** slot.
  ///
  /// `full_slots` is what makes this correct for slicing rather than for
  /// print-time AMS matching, and the server draws that line itself: "Only the
  /// slice modal wants this; print-time AMS matching must keep the used-only
  /// list" (`routes/library.py`). Without it the response holds only the slots
  /// the plate consumes, while `filament_presets` is **positional** — so a file
  /// whose only used slot is 4 offered one picker whose choice the slicer bound
  /// to slot 1, leaving slot 4 on whatever the source had baked in (server
  /// #2712). Each row carries `used_in_plate` so the unused ones can be marked.
  ///
  /// [plateId] is what makes `used_in_plate` mean anything on a file that has
  /// never been sliced. The server can only tell used from unused there by
  /// running a preview slice, and it does that **only** when a plate is named
  /// (`if project_filaments and plate_id is not None`); without one it falls
  /// back to flagging every slot used. It has to name the plate the caller is
  /// really going to print or slice, so that the slots offered are the slots
  /// that plate consumes: the slice form has no plate picker and leaves it at 1
  /// (`SliceRequest.plate` null means plate 1 on the sidecar), while the queue
  /// form passes whichever plate is selected there.
  ///
  /// That preview is a real slice, but it is cached server-side per
  /// `(kind, source_id, plate_id, content hash)`, so it costs once per file
  /// rather than once per opening of the form.
  ///
  /// Not version-gated: both parameters and the flag predate 1.2.6, and an older
  /// server that lacked them would ignore an undeclared query parameter and
  /// answer exactly as it does today.
  ///
  /// Best-effort: any failure degrades to no slots, and the slice form falls
  /// back to a single generic one.
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
  /// Null means the panel must not be shown, for either of two reasons: the
  /// route is absent (404, server < 1.2.6), or this caller is refused it (403 —
  /// the route needs `library:upload`, which the slice itself needs too, so
  /// there is nothing to collect edits for). A [PresetValues] with
  /// `resolved: false` is a different thing: the route answered but could not
  /// read the preset, so the panel opens on schema defaults and explains why.
  ///
  /// Any other failure degrades to [PresetValues.unresolved] rather than
  /// throwing: a blank panel beats an error dialog over a nicety. An expired
  /// session is the one exception, as in [guardOrNull] — swallow the 401 and
  /// nothing redirects, leaving the user staring at empty fields.
  ///
  /// The 403 is answered by [ObservedCapability.watching] and never reaches the
  /// [AuthException] arm below, which a 403 also maps to. That is the point of
  /// keeping the two apart: unlike a 401 it is a permanent per-permission
  /// answer about one route, and throwing it out of a panel read would put a
  /// session dialog in front of a control the user simply cannot have.
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
        // The preset is a query parameter, not a row the route looks up: an
        // unresolvable one comes back `resolved: false`, not 404. So the 404
        // really is the route, absent before 1.2.6 — which is the observation
        // the doc above says outranks the version.
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
  /// status names none of them, so the server's `detail` has to survive —
  /// `sliceRefusalMessage` turns it back into a sentence. A refusal raised
  /// *during* the slice arrives on the job instead, where the dialog shows it.
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
