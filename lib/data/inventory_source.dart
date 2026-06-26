import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/inventory.dart';
import '../core/models/inventory_reference.dart';

/// Filament inventory backend. User has native, but app should also work on Spoolman —
/// selected via setting (see `inventoryBackendProvider`).
enum InventoryBackend { native, spoolman }

/// Common interface for inventory data source — UI and providers don't know which
/// backend is running (swappable pattern like `BackgroundMonitor`). Each implementation
/// maps raw JSON from its API to normalized models.
///
/// Read (Phase 1) + spool management (Phase 2: create/update/delete/archive/restore/
/// reset-usage). AMS assignments and catalog come later. Writes require API key
/// permission (missing → [AuthException] forbidden).
abstract class SpoolInventorySource {
  /// All spools. `includeArchived` includes archived ones.
  Future<List<Spool>> fetchSpools({bool includeArchived = false});

  /// Spool assignments to AMS slots (shows where a spool is placed).
  Future<List<SpoolAssignment>> fetchAssignments();

  /// Assigns a spool to a slot (printer/AMS unit/tray).
  Future<void> assignSpool(SpoolAssignmentDraft draft);

  /// Unassigns a spool from a slot.
  Future<void> unassignSpool(int printerId, int amsId, int trayId);

  /// Usage history for a single spool (loaded on-demand in details).
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId);

  /// Creates a new spool; returns the created, normalized record.
  Future<Spool> createSpool(SpoolDraft draft);

  /// Updates spool fields; returns the updated record.
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft);

  /// Permanently deletes a spool (irreversible — UI confirms).
  Future<void> deleteSpool(int spoolId);

  /// Archives / restores a spool (soft hide from active list).
  Future<void> archiveSpool(int spoolId);
  Future<void> restoreSpool(int spoolId);

  /// Resets spool usage (full again).
  Future<void> resetUsage(int spoolId);

  /// Form reference data (core weight catalog, color database, filament profiles).
  /// Degrade to empty lists — form allows manual entry.
  Future<List<CoreWeightEntry>> fetchCoreWeights();
  Future<List<ColorEntry>> fetchColors();
  Future<List<FilamentPreset>> fetchFilamentPresets();
}

/// Defensive list parsing: skip unparseable entries to avoid one bad record breaking the screen.
List<T> _parseList<T>(
  List<dynamic> body,
  T Function(Map<String, dynamic>) fromJson,
) {
  final out = <T>[];
  for (final item in body) {
    if (item is! Map<String, dynamic>) continue;
    try {
      out.add(fromJson(item));
    } on Object {
      continue;
    }
  }
  return out;
}

/// Native backend `/inventory/*` (default). Auth adds shared `AuthInterceptor`;
/// errors mapped to typed [AppApiException].
class NativeInventorySource implements SpoolInventorySource {
  NativeInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventorySpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return _parseList(res.data ?? const [], Spool.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.inventoryAssignments);
      return _parseList(res.data ?? const [], SpoolAssignment.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.inventoryAssignments,
        data: draft.toNativeJson(),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async {
    try {
      await _dio.delete<dynamic>(
        Endpoints.inventoryAssignment(printerId, amsId, trayId),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async {
    try {
      final res = await _dio
          .get<List<dynamic>>(Endpoints.inventorySpoolUsage(spoolId));
      return _parseList(res.data ?? const [], SpoolUsageEntry.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> createSpool(SpoolDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.inventorySpools,
        data: draft.toNativeJson(),
      );
      return Spool.fromNative(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.inventorySpool(spoolId),
        data: draft.toNativeJson(),
      );
      return Spool.fromNative(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> deleteSpool(int spoolId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.inventorySpool(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> archiveSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolArchive(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> restoreSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolRestore(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> resetUsage(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolResetUsage(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryCatalog);
      return _parseList(res.data ?? const [], CoreWeightEntry.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ColorEntry>> fetchColors() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryColors);
      return _parseList(res.data ?? const [], ColorEntry.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.filamentCatalog);
      return _parseList(res.data ?? const [], FilamentPreset.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Spoolman backend `/spoolman/inventory/*`. Spoolman returns loose passthrough, so
/// [Spool.fromSpoolman]/[SpoolAssignment.fromSpoolman] mappers are more forgiving.
/// Usage history has no stable shape — empty for now.
class SpoolmanInventorySource implements SpoolInventorySource {
  SpoolmanInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.spoolmanSpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return _parseList(res.data ?? const [], Spool.fromSpoolman);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.spoolmanAssignments);
      return _parseList(res.data ?? const [], SpoolAssignment.fromSpoolman);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // Spoolman manages slot assignments server-side — backend doesn't expose writes here.
  // User's default backend is native; if someone switches to Spoolman, UI gets a
  // clear error message instead of silent failure.
  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async =>
      throw UnsupportedError('Spoolman backend does not support slot assignment');

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async =>
      throw UnsupportedError('Spoolman backend does not support slot assignment');

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async => const [];

  @override
  Future<Spool> createSpool(SpoolDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.spoolmanSpools,
        data: draft.toSpoolmanJson(),
      );
      return Spool.fromSpoolman(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.spoolmanSpool(spoolId),
        data: draft.toSpoolmanJson(),
      );
      return Spool.fromSpoolman(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> deleteSpool(int spoolId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.spoolmanSpool(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> archiveSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolArchive(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> restoreSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolRestore(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> resetUsage(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolResetUsage(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // Reference data comes from native backend catalogs — on Spoolman, form uses
  // manual entry (empty lists).
  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async => const [];

  @override
  Future<List<ColorEntry>> fetchColors() async => const [];

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async => const [];
}
