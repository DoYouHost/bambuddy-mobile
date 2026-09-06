import 'dart:typed_data';

import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/inventory.dart';
import '../core/models/inventory_bulk.dart';
import '../core/models/inventory_reference.dart';
import '../core/models/spool_label.dart';
import '../core/models/spool_preset_override.dart';
import 'inventory_source.dart';

/// Facade for filament inventory over a selected [SpoolInventorySource]. A thin
/// layer: unifies API for providers and is an extension point for writes (Phase 2).
/// Backend choice (native/Spoolman) is made in the provider, which injects the
/// ready-made source here.
class InventoryRepository {
  InventoryRepository(this._source, [this._serverVersion]);

  final SpoolInventorySource _source;

  /// Answers [supportsPresetOverrides] until the route itself has.
  final ServerVersionService? _serverVersion;

  /// Whether this server has the per-model preset routes at all. One latch for
  /// both backends: the native pair and the Spoolman twin landed in the same
  /// release, and only one source is ever live.
  late final _presetOverrides = ObservedCapability(
    ServerFeature.spoolModelPresets,
    _serverVersion,
  );

  Future<List<Spool>> fetchSpools({bool includeArchived = false}) =>
      _source.fetchSpools(includeArchived: includeArchived);

  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) =>
      _source.fetchAssignments(printerId: printerId);

  Future<void> ensureAssignable(SpoolAssignmentDraft draft) =>
      _source.ensureAssignable(draft);

  Future<void> assignSpool(SpoolAssignmentDraft draft) =>
      _source.assignSpool(draft);

  Future<void> unassignSpool(int printerId, int amsId, int trayId) =>
      _source.unassignSpool(printerId, amsId, trayId);

  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  }) => _source.createSpoolFromSlot(
    printerId: printerId,
    amsId: amsId,
    trayId: trayId,
  );

  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) =>
      _source.fetchUsage(spoolId);

  Future<Spool> createSpool(SpoolDraft draft) => _source.createSpool(draft);

  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity) =>
      _source.bulkCreateSpools(draft, quantity);

  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) =>
      _source.updateSpool(spoolId, draft);

  Future<void> deleteSpool(int spoolId) => _source.deleteSpool(spoolId);

  Future<void> archiveSpool(int spoolId) => _source.archiveSpool(spoolId);

  Future<void> restoreSpool(int spoolId) => _source.restoreSpool(spoolId);

  Future<void> resetUsage(int spoolId) => _source.resetUsage(spoolId);

  /// Bulk operations on a selection — see [SpoolInventorySource.bulkUpdate] for
  /// how a server without the routes announces itself.
  Future<BulkOutcome> bulkUpdate(List<int> spoolIds, SpoolBulkPatch patch) =>
      _source.bulkUpdate(spoolIds, patch);

  Future<BulkOutcome> bulkArchive(List<int> spoolIds) =>
      _source.bulkArchive(spoolIds);

  Future<BulkOutcome> bulkRestore(List<int> spoolIds) =>
      _source.bulkRestore(spoolIds);

  Future<BulkOutcome> bulkDelete(List<int> spoolIds) =>
      _source.bulkDelete(spoolIds);

  Future<BulkOutcome> bulkResetUsage(List<int> spoolIds) =>
      _source.bulkResetUsage(spoolIds);

  Future<List<CoreWeightEntry>> fetchCoreWeights() =>
      _source.fetchCoreWeights();

  Future<List<ColorEntry>> fetchColors() => _source.fetchColors();

  Future<List<FilamentPreset>> fetchFilamentPresets() =>
      _source.fetchFilamentPresets();

  Future<List<StorageLocation>> fetchLocations() => _source.fetchLocations();

  Future<Uint8List> renderLabels(SpoolLabelRequest request) =>
      _source.renderLabels(request);

  Future<bool> supportsPresetOverrides() => _presetOverrides.supported;

  /// One spool's per-printer-model preset overrides. A server without the route
  /// answers with an empty list rather than throwing: the section reading this
  /// is additive, so it renders as if the spool simply had none.
  ///
  /// The 404 settles nothing, because the route also raises it for a spool that
  /// is gone (`inventory.py::"Spool not found"`) and the two read alike. The
  /// version row is what answers [supportsPresetOverrides].
  ///
  /// A **403** throws, unlike the 404: `inventory:read` is a permission the key
  /// either has or does not, and a spool form that quietly showed no overrides
  /// would invite a save that wipes them.
  Future<List<SpoolPresetOverride>> fetchPresetOverrides(int spoolId) =>
      _presetOverrides.watching(
        () => _source.fetchPresetOverrides(spoolId),
        absent: () => const [],
        absentOn: const {404},
      );

  /// Replaces every override on [spoolId]. Throws on any failure: the user
  /// pressed Save, so a refusal has to reach them.
  Future<void> savePresetOverrides(
    int spoolId,
    List<SpoolPresetOverride> overrides,
  ) => _presetOverrides.watching(
    () => _source.savePresetOverrides(spoolId, overrides),
  );
}
