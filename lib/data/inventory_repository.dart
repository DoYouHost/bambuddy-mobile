import 'dart:typed_data';

import '../core/models/inventory.dart';
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

  Future<List<CoreWeightEntry>> fetchCoreWeights() => _source.fetchCoreWeights();

  Future<List<ColorEntry>> fetchColors() => _source.fetchColors();

  Future<List<FilamentPreset>> fetchFilamentPresets() =>
      _source.fetchFilamentPresets();

  Future<List<String>> fetchLocations() => _source.fetchLocations();

  Future<Uint8List> renderLabels(
    List<int> spoolIds,
    SpoolLabelTemplate template, {
    bool monochrome = false,
  }) => _source.renderLabels(spoolIds, template, monochrome: monochrome);
}
