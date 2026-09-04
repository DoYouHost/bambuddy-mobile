import 'dart:typed_data';

import '../core/models/inventory.dart';
import '../core/models/inventory_bulk.dart';
import '../core/models/inventory_reference.dart';
import '../core/models/spool_label.dart';
import 'inventory_source.dart';

/// Facade for filament inventory over a selected [SpoolInventorySource]. A thin
/// layer: unifies API for providers and is an extension point for writes (Phase 2).
/// Backend choice (native/Spoolman) is made in the provider, which injects the
/// ready-made source here.
class InventoryRepository {
  InventoryRepository(this._source);

  final SpoolInventorySource _source;

  Future<List<Spool>> fetchSpools({bool includeArchived = false}) =>
      _source.fetchSpools(includeArchived: includeArchived);

  Future<List<SpoolAssignment>> fetchAssignments() =>
      _source.fetchAssignments();

  Future<void> assignSpool(SpoolAssignmentDraft draft) =>
      _source.assignSpool(draft);

  Future<void> unassignSpool(int printerId, int amsId, int trayId) =>
      _source.unassignSpool(printerId, amsId, trayId);

  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  }) =>
      _source.createSpoolFromSlot(
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

  Future<List<CoreWeightEntry>> fetchCoreWeights() => _source.fetchCoreWeights();

  Future<List<ColorEntry>> fetchColors() => _source.fetchColors();

  Future<List<FilamentPreset>> fetchFilamentPresets() =>
      _source.fetchFilamentPresets();

  Future<List<StorageLocation>> fetchLocations() => _source.fetchLocations();

  Future<Uint8List> renderLabels(SpoolLabelRequest request) =>
      _source.renderLabels(request);
}
