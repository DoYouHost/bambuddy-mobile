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
/// source here.
class InventoryRepository {
  InventoryRepository(
    SpoolInventorySource source, [
    ServerVersionService? serverVersion,
  ]) : this.resolving(
         () async => source,
         () async => source is SpoolmanInventorySource
             ? InventoryBackend.spoolman
             : InventoryBackend.native,
         serverVersion,
       );

  /// Over a source still being decided: every call waits for [_source], so
  /// none can reach the backend the server is not running.
  InventoryRepository.resolving(
    this._source,
    this.backend, [
    this._serverVersion,
  ]);

  final Future<SpoolInventorySource> Function() _source;

  /// Which backend [_source] talks to, for the writes that address the two
  /// differently (supplier links) or the screens that read one only.
  final Future<InventoryBackend> Function() backend;

  Future<T> _on<T>(Future<T> Function(SpoolInventorySource s) call) async =>
      call(await _source());

  /// Answers [presetOverridesCapability] until the route itself has, and
  /// [labelStartingPositionCapability] always.
  final ServerVersionService? _serverVersion;

  /// Whether this server has the per-model preset routes at all. One latch for
  /// both backends: the native pair and the Spoolman twin landed in the same
  /// release, and only one source is ever live.
  late final presetOverridesCapability = ObservedCapability(
    ServerFeature.spoolModelPresets,
    _serverVersion,
  );

  /// Whether a label sheet may be told where to start (server #2879). Never
  /// observed — see [ServerFeature.labelStartingPosition] for why a PDF
  /// response cannot answer it.
  late final labelStartingPositionCapability = ObservedCapability(
    ServerFeature.labelStartingPosition,
    _serverVersion,
  );

  /// Whether a label request may carry `fields`, `format` and `dpi` (server
  /// #2981). Never observed, like [labelStartingPositionCapability]: an older
  /// server answers a valid PDF to a request that asked for a PNG.
  late final labelFieldsCapability = ObservedCapability(
    ServerFeature.labelFields,
    _serverVersion,
  );

  /// Whether this server stores a material number on a spool (#2870). One
  /// latch for both backends: Spoolman rows carry the key too, and only the
  /// native one is writable.
  late final materialNumberCapability = ObservedCapability(
    ServerFeature.spoolMaterialNumber,
    _serverVersion,
  );

  /// Settles [materialNumberCapability] from a listing: `SpoolResponse` sends
  /// `material_number` on every row from the feature on. An empty inventory
  /// says nothing either way.
  void observeSpools(List<Spool> spools) => materialNumberCapability
      .observeFirst(spools, (s) => s.materialNumberReported);

  Future<List<Spool>> fetchSpools({bool includeArchived = false}) =>
      _on((s) => s.fetchSpools(includeArchived: includeArchived));

  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) =>
      _on((s) => s.fetchAssignments(printerId: printerId));

  Future<void> assignSpool(SpoolAssignmentDraft draft) =>
      _on((s) => s.assignSpool(draft));

  Future<void> unassignSpool(int printerId, int amsId, int trayId) =>
      _on((s) => s.unassignSpool(printerId, amsId, trayId));

  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  }) => _on(
    (s) => s.createSpoolFromSlot(
      printerId: printerId,
      amsId: amsId,
      trayId: trayId,
    ),
  );

  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) =>
      _on((s) => s.fetchUsage(spoolId));

  Future<Spool> createSpool(SpoolDraft draft) =>
      _on((s) => s.createSpool(draft));

  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity) =>
      _on((s) => s.bulkCreateSpools(draft, quantity));

  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) =>
      _on((s) => s.updateSpool(spoolId, draft));

  Future<void> deleteSpool(int spoolId) => _on((s) => s.deleteSpool(spoolId));

  Future<void> archiveSpool(int spoolId) => _on((s) => s.archiveSpool(spoolId));

  Future<void> restoreSpool(int spoolId) => _on((s) => s.restoreSpool(spoolId));

  Future<void> resetUsage(int spoolId) => _on((s) => s.resetUsage(spoolId));

  /// Bulk operations on a selection — see [SpoolInventorySource.bulkUpdate] for
  /// how a server without the routes announces itself.
  Future<BulkOutcome> bulkUpdate(List<int> spoolIds, SpoolBulkPatch patch) =>
      _on((s) => s.bulkUpdate(spoolIds, patch));

  Future<BulkOutcome> bulkArchive(List<int> spoolIds) =>
      _on((s) => s.bulkArchive(spoolIds));

  Future<BulkOutcome> bulkRestore(List<int> spoolIds) =>
      _on((s) => s.bulkRestore(spoolIds));

  Future<BulkOutcome> bulkDelete(List<int> spoolIds) =>
      _on((s) => s.bulkDelete(spoolIds));

  Future<BulkOutcome> bulkResetUsage(List<int> spoolIds) =>
      _on((s) => s.bulkResetUsage(spoolIds));

  Future<List<CoreWeightEntry>> fetchCoreWeights() =>
      _on((s) => s.fetchCoreWeights());

  Future<List<ColorEntry>> fetchColors() => _on((s) => s.fetchColors());

  Future<List<FilamentPreset>> fetchFilamentPresets() =>
      _on((s) => s.fetchFilamentPresets());

  Future<List<StorageLocation>> fetchLocations() =>
      _on((s) => s.fetchLocations());

  Future<Uint8List> renderLabels(SpoolLabelRequest request) =>
      _on((s) => s.renderLabels(request));

  /// Stock and spend per material number; [from]/[to] are inclusive calendar
  /// days and narrow only the consumption and cost. Empty on Spoolman, whose
  /// source is never asked, and on a server without the route or a session
  /// that may not read it: the card on top of it is additive.
  ///
  /// Only a 404 settles [materialNumberCapability]. The spool rows are the
  /// evidence the gate documents, and a 403 on an aggregate must not hide a
  /// field the rows prove the server has.
  Future<List<MaterialNumberStats>> fetchMaterialNumberStats({
    DateTime? from,
    DateTime? to,
  }) => _on((s) {
    if (s is! NativeInventorySource) {
      return Future.value(const <MaterialNumberStats>[]);
    }
    return materialNumberCapability.watching(
      () => s.fetchMaterialNumberStats(from: from, to: to),
      absent: () => const [],
      observing: const {404},
    );
  });

  /// One spool's per-printer-model preset overrides. A server without the route
  /// answers with an empty list rather than throwing: the section reading this
  /// is additive, so it renders as if the spool simply had none.
  ///
  /// The 404 settles nothing, because the route also raises it for a spool that
  /// is gone (`inventory.py::"Spool not found"`) and the two read alike. The
  /// version row is what answers [presetOverridesCapability].
  ///
  /// A **403** throws, unlike the 404: `inventory:read` is a permission the key
  /// either has or does not, and a spool form that quietly showed no overrides
  /// would invite a save that wipes them.
  Future<List<SpoolPresetOverride>> fetchPresetOverrides(int spoolId) =>
      presetOverridesCapability.watching(
        () => _on((s) => s.fetchPresetOverrides(spoolId)),
        absent: () => const [],
        absentOn: const {404},
      );

  /// Replaces every override on [spoolId]. Throws on any failure: the user
  /// pressed Save, so a refusal has to reach them.
  ///
  /// Its 403 settles nothing: that is a missing `inventory:update`, and taking
  /// it for "no presets here" would hide the section from a session that can
  /// still read it.
  Future<void> savePresetOverrides(
    int spoolId,
    List<SpoolPresetOverride> overrides,
  ) => presetOverridesCapability.watching(
    observing: const {},
    () => _on((s) => s.savePresetOverrides(spoolId, overrides)),
  );
}
