import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/inventory.dart';
import '../core/models/inventory_reference.dart';
import '../core/models/json_utils.dart';

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

  /// Storage-location catalog names for the location picker. Native only;
  /// Spoolman degrades to empty (the picker still accepts free text).
  Future<List<String>> fetchLocations();
}

/// Native backend `/inventory/*` (default). Auth adds shared `AuthInterceptor`;
/// errors mapped to typed [AppApiException].
class NativeInventorySource implements SpoolInventorySource {
  NativeInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventorySpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Spool.fromNative);
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryAssignments);
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolAssignment.fromNative);
  }

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) => guard(() => _dio.post<dynamic>(
        Endpoints.inventoryAssignments,
        data: draft.toNativeJson(),
      ));

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) => guard(
        () => _dio.delete<dynamic>(
          Endpoints.inventoryAssignment(printerId, amsId, trayId),
        ),
      );

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async {
    final body = await guard(() async {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.inventorySpoolUsage(spoolId));
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolUsageEntry.fromNative);
  }

  @override
  Future<Spool> createSpool(SpoolDraft draft) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.inventorySpools,
          data: draft.toNativeJson(),
        );
        return Spool.fromNative(res.data ?? const {});
      });

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) => guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.inventorySpool(spoolId),
          data: draft.toNativeJson(),
        );
        return Spool.fromNative(res.data ?? const {});
      });

  @override
  Future<void> deleteSpool(int spoolId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.inventorySpool(spoolId)));

  @override
  Future<void> archiveSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.inventorySpoolArchive(spoolId)));

  @override
  Future<void> restoreSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.inventorySpoolRestore(spoolId)));

  @override
  Future<void> resetUsage(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.inventorySpoolResetUsage(spoolId)));

  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryCatalog);
      return res.data ?? const [];
    });
    return parseJsonList(body, CoreWeightEntry.fromJson);
  }

  @override
  Future<List<ColorEntry>> fetchColors() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryColors);
      return res.data ?? const [];
    });
    return parseJsonList(body, ColorEntry.fromJson);
  }

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.filamentCatalog);
      return res.data ?? const [];
    });
    return parseJsonList(body, FilamentPreset.fromJson);
  }

  @override
  Future<List<String>> fetchLocations() => guard(() async {
        final res = await _dio.get<List<dynamic>>(Endpoints.inventoryLocations);
        return [
          for (final e in res.data ?? const [])
            if (e is Map && (e['name'] as String?)?.trim().isNotEmpty == true)
              (e['name'] as String).trim(),
        ];
      });
}

/// Spoolman backend `/spoolman/inventory/*`. Spoolman returns loose passthrough, so
/// [Spool.fromSpoolman]/[SpoolAssignment.fromSpoolman] mappers are more forgiving.
/// Usage history has no stable shape — empty for now.
class SpoolmanInventorySource implements SpoolInventorySource {
  SpoolmanInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.spoolmanSpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Spool.fromSpoolman);
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.spoolmanAssignments);
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolAssignment.fromSpoolman);
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
  Future<Spool> createSpool(SpoolDraft draft) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.spoolmanSpools,
          data: draft.toSpoolmanJson(),
        );
        return Spool.fromSpoolman(res.data ?? const {});
      });

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) => guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.spoolmanSpool(spoolId),
          data: draft.toSpoolmanJson(),
        );
        return Spool.fromSpoolman(res.data ?? const {});
      });

  @override
  Future<void> deleteSpool(int spoolId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.spoolmanSpool(spoolId)));

  @override
  Future<void> archiveSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.spoolmanSpoolArchive(spoolId)));

  @override
  Future<void> restoreSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.spoolmanSpoolRestore(spoolId)));

  @override
  Future<void> resetUsage(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.spoolmanSpoolResetUsage(spoolId)));

  // Reference data comes from native backend catalogs — on Spoolman, form uses
  // manual entry (empty lists).
  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async => const [];

  @override
  Future<List<ColorEntry>> fetchColors() async => const [];

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async => const [];

  // Location catalog is a native-backend feature; on Spoolman the picker falls
  // back to free text + locations already used by spools.
  @override
  Future<List<String>> fetchLocations() async => const [];
}
