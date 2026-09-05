import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../core/models/inventory_bulk.dart';
import '../../core/models/inventory_reference.dart';
import '../../core/models/location_sensor.dart';
import '../../core/models/spool_preset_override.dart';
import '../../data/inventory_repository.dart';
import '../../providers.dart';

/// Inventory snapshot for the screen: all spools (including archived) plus a map
/// `spoolId → assignment to AMS slot`. Filtering (search / show archived) is done
/// client-side on this list — data changes infrequently, so a single fetch suffices
/// and toggles respond instantly.
class InventoryState {
  const InventoryState({
    this.spools = const [],
    this.assignmentBySpool = const {},
  });

  final List<Spool> spools;
  final Map<int, SpoolAssignment> assignmentBySpool;

  SpoolAssignment? assignmentFor(int spoolId) => assignmentBySpool[spoolId];

  /// The spool already registered for an RFID tag, or null when the tag is new
  /// to the inventory.
  ///
  /// One field at a time rather than one spool at a time, which is the server's
  /// own order: a `tray_uuid` hit anywhere beats a `tag_uid` hit, because only
  /// the UUID survives the filament being re-spooled onto another core
  /// (`GET /inventory/spools/by-tag`, `backend/app/api/routes/inventory.py`).
  Spool? spoolForTag({String? tagUid, String? trayUuid}) {
    final uuid = normalizeTrayUuid(trayUuid);
    if (uuid.isNotEmpty) {
      for (final s in spools) {
        if (normalizeTrayUuid(s.trayUuid) == uuid) return s;
      }
    }
    final uid = normalizeTagUid(tagUid);
    if (uid.isNotEmpty) {
      for (final s in spools) {
        if (normalizeTagUid(s.tagUid) == uid) return s;
      }
    }
    return null;
  }
}

final inventoryProvider =
    AutoDisposeAsyncNotifierProvider<InventoryNotifier, InventoryState>(
      InventoryNotifier.new,
    );

/// Fetches spools and assignments in one pass. Assignments degrade to an empty map
/// if the endpoint fails/is unavailable — the spool list is more important than
/// knowing which slot they occupy. Rebuilds on profile/backend change.
class InventoryNotifier extends AutoDisposeAsyncNotifier<InventoryState> {
  @override
  Future<InventoryState> build() async {
    ref.watch(serverProfileProvider);
    ref.watch(inventoryBackendProvider);
    return _load();
  }

  Future<InventoryState> _load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    final spools = await repo.fetchSpools(includeArchived: true);

    var bySpool = <int, SpoolAssignment>{};
    try {
      final assignments = await repo.fetchAssignments();
      bySpool = {for (final a in assignments) a.spoolId: a};
    } on Object {
      // Assignments are a bonus — their absence must not break the screen.
      bySpool = const {};
    }

    spools.sort((a, b) {
      // Active before archived; among active, assigned (in AMS or external) before loose.
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final aLoaded = bySpool.containsKey(a.id);
      final bLoaded = bySpool.containsKey(b.id);
      if (aLoaded != bLoaded) return aLoaded ? -1 : 1;
      // Among assigned: lowest remaining weight first to highlight near-empty ones.
      // Loose spools alphabetically by name.
      if (aLoaded && bLoaded) {
        final byRemaining = a.remainingWeight.compareTo(b.remainingWeight);
        if (byRemaining != 0) return byRemaining;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return InventoryState(spools: spools, assignmentBySpool: bySpool);
  }

  /// Pull-to-refresh. Keeps previous data underneath (no spinner flicker), same pattern as maintenance.
  Future<void> refresh() async {
    state = const AsyncValue<InventoryState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
  }

  /// Executes a mutation, then reloads the list (server is source of truth —
  /// no optimistic updates because writes are rare and data is computed).
  /// Exceptions propagate to the caller (UI shows snackbar), but state refreshes anyway.
  /// Returns the created/modified spool (or null).
  Future<Spool?> _mutate(
    Future<Spool?> Function(InventoryRepository) action,
  ) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      return await action(repo);
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  Future<Spool?> createSpool(SpoolDraft draft) =>
      _mutate((repo) => repo.createSpool(draft));

  /// Bulk-creates [quantity] identical spools ("restock") and reloads the list.
  /// Returns how many were actually created. Exceptions propagate to the UI,
  /// but the list refreshes regardless (mirrors [_mutate]).
  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      return await repo.bulkCreateSpools(draft, quantity);
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) =>
      _mutate((repo) => repo.updateSpool(spoolId, draft));

  Future<void> deleteSpool(int spoolId) =>
      _mutate((repo) async => repo.deleteSpool(spoolId).then((_) => null));

  Future<void> archiveSpool(int spoolId) =>
      _mutate((repo) async => repo.archiveSpool(spoolId).then((_) => null));

  Future<void> restoreSpool(int spoolId) =>
      _mutate((repo) async => repo.restoreSpool(spoolId).then((_) => null));

  Future<void> resetUsage(int spoolId) =>
      _mutate((repo) async => repo.resetUsage(spoolId).then((_) => null));

  /// Assigns a spool to a slot, ensuring it occupies EXACTLY one slot:
  /// if it was elsewhere, [from] points to the old slot and we unpin it first (move).
  /// [from] == same slot → just assign.
  Future<void> assignSpool(
    SpoolAssignmentDraft draft, {
    SpoolAssignment? from,
  }) => _mutate((repo) async {
    if (from != null &&
        !(from.printerId == draft.printerId &&
            from.amsId == draft.amsId &&
            from.trayId == draft.trayId)) {
      await repo.unassignSpool(from.printerId, from.amsId, from.trayId);
    }
    await repo.assignSpool(draft);
    _nudgeRepublish(draft.printerId);
    return null;
  });

  Future<void> unassignSpool(int printerId, int amsId, int trayId) => _mutate(
    (repo) async => repo.unassignSpool(printerId, amsId, trayId).then((_) {
      _nudgeRepublish(printerId);
      return null;
    }),
  );

  /// Registers what the slot holds as a new spool and pins it there. The
  /// server does both halves in one call, so the invariant "one spool, one
  /// slot" needs no unpin step here — the slot was empty of a spool to begin
  /// with, which is the only state the UI offers this from.
  Future<int?> createSpoolFromSlot(int printerId, int amsId, int trayId) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      final id = await repo.createSpoolFromSlot(
        printerId: printerId,
        amsId: amsId,
        trayId: trayId,
      );
      _nudgeRepublish(printerId);
      return id;
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  /// Assigning a spool makes the server push an `ams_filament_setting` to the
  /// printer, but the firmware does not reliably echo the new tray back —
  /// notably for non-RFID slots and A1 mini externals. Without a nudge the card
  /// keeps showing the old filament until something else makes the printer
  /// speak.
  void _nudgeRepublish(int printerId) => ref
      .read(printerCommandsRepositoryProvider)
      .nudgeRepublish([printerId]);

  /// Runs a multi-select operation as one bulk call, and reloads ONCE at the
  /// end — a 20-spool archive would otherwise refetch the whole inventory 20
  /// times.
  ///
  /// [perSpool] is the same operation one spool at a time, used when the server
  /// answers 404: the bulk routes arrived in 0.2.5b1 and report an unknown id in
  /// the body rather than as a status, so that 404 means the routes are not
  /// there. Everything else (a 403 from a key without `filaments:update`, a
  /// dead server) propagates — the caller words it.
  Future<BulkOutcome> _bulk(
    Iterable<int> spoolIds,
    Future<BulkOutcome> Function(InventoryRepository, List<int>) bulk,
    Future<void> Function(InventoryRepository, int) perSpool,
  ) async {
    final repo = ref.read(inventoryRepositoryProvider);
    final ids = spoolIds.toList();
    try {
      try {
        return await bulk(repo, ids);
      } on AppApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        return await _perSpoolFallback(repo, ids, perSpool);
      }
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  /// One call per spool, for a server without the bulk routes. One failure
  /// doesn't abort the rest — the tally it builds is the same shape the bulk
  /// routes answer with, minus the detail they carry.
  Future<BulkOutcome> _perSpoolFallback(
    InventoryRepository repo,
    List<int> ids,
    Future<void> Function(InventoryRepository, int) action,
  ) async {
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await action(repo, id);
        ok++;
      } on Object {
        failed++;
      }
    }
    return BulkOutcome(ok: ok, failed: failed);
  }

  /// Applies one partial edit to every selected spool. There is no per-spool
  /// fallback worth having here: replaying a 14-field patch as N PATCHes on a
  /// server that never offered mass edit would be a different feature, so an
  /// older server surfaces the 404 and the UI says the server cannot do it.
  Future<BulkOutcome> bulkUpdateSpools(
    Iterable<int> ids,
    SpoolBulkPatch patch,
  ) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      return await repo.bulkUpdate(ids.toList(), patch);
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  Future<BulkOutcome> archiveSpools(Iterable<int> ids) => _bulk(
        ids,
        (repo, ids) => repo.bulkArchive(ids),
        (repo, id) => repo.archiveSpool(id),
      );

  Future<BulkOutcome> restoreSpools(Iterable<int> ids) => _bulk(
        ids,
        (repo, ids) => repo.bulkRestore(ids),
        (repo, id) => repo.restoreSpool(id),
      );

  Future<BulkOutcome> deleteSpools(Iterable<int> ids) => _bulk(
        ids,
        (repo, ids) => repo.bulkDelete(ids),
        (repo, id) => repo.deleteSpool(id),
      );

  Future<BulkOutcome> resetUsageMany(Iterable<int> ids) => _bulk(
        ids,
        (repo, ids) => repo.bulkResetUsage(ids),
        (repo, id) => repo.resetUsage(id),
      );
}

/// Resolves which spool from inventory sits in a given slot of a specific printer —
/// to enrich AMS chips on the dashboard (exact remaining weight + name).
/// Built from [InventoryState]; matching depends on assignment structure
/// (see [[inventory-filaments]]).
class AssignedSpools {
  const AssignedSpools(this.printerId, this._byKey, this._byExtruder);

  /// Empty resolver (inventory not loaded / error) — enriches nothing.
  static const empty = AssignedSpools(-1, {}, {});

  final int printerId;

  /// Key `amsId * 1000 + trayId` → spool (AMS unit slots).
  final Map<int, Spool> _byKey;

  /// Extruder (1=left, 0=right) → external spool.
  final Map<int, Spool> _byExtruder;

  /// Spool in an AMS unit slot (`amsId` = unit id, `trayId` = tray number in unit).
  /// Null if nothing is assigned.
  Spool? forAmsSlot(int amsId, int trayId) => _byKey[amsId * 1000 + trayId];

  /// External spool feeding a given extruder (1=left, 0=right).
  Spool? forExtruder(int? extruder) =>
      extruder == null ? null : _byExtruder[extruder];

  bool get isEmpty => _byKey.isEmpty && _byExtruder.isEmpty;
}

/// Assignment resolver for one printer (by `printerId`). Reads `inventoryProvider`
/// (shares the same fetch as the Filaments tab); degrades to empty if inventory
/// hasn't loaded or failed — dashboard works without it.
final assignedSpoolsProvider = Provider.autoDispose.family<AssignedSpools, int>(
  (ref, printerId) {
    final inv = ref.watch(inventoryProvider).valueOrNull;
    if (inv == null) return AssignedSpools.empty;
    final spoolById = {for (final s in inv.spools) s.id: s};
    final byKey = <int, Spool>{};
    final byExtruder = <int, Spool>{};
    for (final a in inv.assignmentBySpool.values) {
      if (a.printerId != printerId) continue;
      final spool = spoolById[a.spoolId];
      if (spool == null) continue;
      if (a.isExternalSpool) {
        final ext = a.extruder;
        if (ext != null) byExtruder[ext] = spool;
      } else {
        byKey[a.amsId * 1000 + a.trayId] = spool;
      }
    }
    return AssignedSpools(printerId, byKey, byExtruder);
  },
);

/// Filament consumed since the counters were last reset, over the whole shelf.
///
/// Archived spools are counted in: it is a running total, and what a spool
/// consumed before being archived is real history — dropping it would make the
/// number fall for no visible reason (the bug bambuddy's own tile was fixed for,
/// server issue #1390).
///
/// A provider rather than a sum inside the list header: the header rebuilds on
/// every search keystroke, and this way the shelf is only walked again when the
/// shelf itself changes.
final inventoryConsumedTotalProvider = Provider.autoDispose<double>((ref) {
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  var total = 0.0;
  for (final spool in spools) {
    total += spool.consumedWeight;
  }
  return total;
});

/// Search text (material/brand/color/location). Filtered client-side in the view.
final inventoryQueryProvider = StateProvider.autoDispose<String>((_) => '');

/// Set of inventory filters (apart from search) — chosen in the filter sheet.
/// All applied client-side on the full spool list. Defaults: active only, no limits.
/// Empty sets = "all".
class InventoryFilters {
  const InventoryFilters({
    this.showArchived = false,
    this.lowStockOnly = false,
    this.materials = const {},
    this.brands = const {},
    this.locations = const {},
  });

  /// false → active only (default); true → archived only.
  final bool showArchived;
  final bool lowStockOnly;
  final Set<String> materials;
  final Set<String> brands;
  final Set<String> locations;

  /// Count of non-default filters — for badge on filter button.
  int get activeCount =>
      (showArchived ? 1 : 0) +
      (lowStockOnly ? 1 : 0) +
      (materials.isNotEmpty ? 1 : 0) +
      (brands.isNotEmpty ? 1 : 0) +
      (locations.isNotEmpty ? 1 : 0);

  InventoryFilters copyWith({
    bool? showArchived,
    bool? lowStockOnly,
    Set<String>? materials,
    Set<String>? brands,
    Set<String>? locations,
  }) => InventoryFilters(
    showArchived: showArchived ?? this.showArchived,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    materials: materials ?? this.materials,
    brands: brands ?? this.brands,
    locations: locations ?? this.locations,
  );
}

final inventoryFiltersProvider = StateProvider.autoDispose<InventoryFilters>(
  (_) => const InventoryFilters(),
);

/// Spool usage history — loaded on demand in details (family by id).
final spoolUsageProvider = FutureProvider.autoDispose
    .family<List<SpoolUsageEntry>, int>(
      (ref, spoolId) =>
          ref.watch(inventoryRepositoryProvider).fetchUsage(spoolId),
    );

/// Spool form reference data (Phase 2). Loaded on form open; degrades to empty list
/// (form allows manual entry), so errors don't block spool creation. Kept briefly
/// after close (`keepAlive`) so reopening doesn't fetch again.
final coreWeightsProvider = FutureProvider.autoDispose<List<CoreWeightEntry>>((
  ref,
) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchCoreWeights();
  } on Object {
    return const [];
  }
});

final colorCatalogProvider = FutureProvider.autoDispose<List<ColorEntry>>((
  ref,
) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchColors();
  } on Object {
    return const [];
  }
});

final filamentPresetsProvider =
    FutureProvider.autoDispose<List<FilamentPreset>>((ref) async {
      ref.keepAlive();
      try {
        return await ref
            .watch(inventoryRepositoryProvider)
            .fetchFilamentPresets();
      } on Object {
        return const [];
      }
    });

/// The printer models the fleet actually has, spelled exactly as the server
/// reports them.
///
/// Not `ownedPrinterCodesProvider`, which reads the same fleet for the same
/// field and upper-cases it: that one narrows a preset *list* by name, where
/// case cannot matter, while this one is the key the server matches an
/// override on — `printer_model` is compared for plain string equality
/// (`services/spool_filament_preset.py::_pick`), so a case-folded key writes a
/// row nothing will ever resolve to. Two readers, deliberately, and neither is
/// safe to point at the other.
///
/// Sorted for a stable order in the spool form; a printer that has not reported
/// a model is left out, having no model to key a row by.
final printerModelsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final printers = await ref.watch(printersRepositoryProvider).fetchPrinters();
  final models = <String>{
    for (final p in printers)
      if ((p.model?.trim() ?? '').isNotEmpty) p.model!.trim(),
  }.toList()
    ..sort();
  return models;
});

/// Whether this server has the per-model preset routes. Cached for the session
/// — the answer is a property of the server, and the latch behind it already
/// updates itself from what the routes actually answer.
final presetOverridesSupportedProvider = FutureProvider<bool>((ref) async {
  ref.keepAlive();
  return ref.watch(inventoryRepositoryProvider).supportsPresetOverrides();
});

/// One spool's per-printer-model preset overrides, as stored right now.
///
/// Errors are NOT swallowed here, unlike the other reference data above: the
/// route replaces the whole list, so a form that opened on a failed read and
/// saved anyway would delete overrides the user never saw. The form reads the
/// error state and keeps its section read-only when it is set.
final spoolPresetOverridesProvider = FutureProvider.autoDispose
    .family<List<SpoolPresetOverride>, int>((ref, spoolId) async {
  if (!await ref.watch(presetOverridesSupportedProvider.future)) return const [];
  return ref.watch(inventoryRepositoryProvider).fetchPresetOverrides(spoolId);
});

/// Server-side storage-location catalog (native backend). Degrades to empty on
/// error; [locationOptionsProvider] still surfaces locations used by spools.
final locationCatalogProvider =
    FutureProvider.autoDispose<List<StorageLocation>>((ref) async {
  // No keepAlive: re-fetch on reopen so a location just created (as a side
  // effect of saving a spool with a new storage_location) shows up next time.
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchLocations();
  } on Object {
    return const [];
  }
});

/// One storage location and what the Home Assistant sensors bound to it read
/// right now.
class LocationClimate {
  const LocationClimate({required this.location, required this.readings});

  final StorageLocation location;

  /// The location's card-visible sensors, in the order the server sorted them.
  /// Never empty — a location with nothing to show is left out of
  /// [locationClimateProvider] entirely.
  final List<LocationSensorReading> readings;

  /// Whether any reading is outside the thresholds its binding carries.
  bool get alerting => readings.any((r) => r.alerting);
}

/// Live readings for every storage location that has a sensor bound to it,
/// keyed by [StorageLocation.matchKey] so a spool's free-text
/// `storage_location` can find its own.
///
/// Three requests deep at most, and only on a server that has the feature: the
/// listing says which locations are worth asking about, and locations without
/// a card-visible sensor are never asked. An error anywhere leaves the map
/// short rather than failing the screen — every surface reading it is additive.
final locationClimateProvider =
    FutureProvider.autoDispose<Map<String, LocationClimate>>((ref) async {
  final repo = ref.watch(locationSensorsRepositoryProvider);
  if (!await repo.supportsLocationSensors()) return const {};

  final bindings = await repo.listBindings();
  final wanted = <int>{
    for (final b in bindings)
      if (b.showOnCard) b.locationId,
  };
  if (wanted.isEmpty) return const {};

  final catalog = await ref.watch(locationCatalogProvider.future);
  final locations = [
    for (final loc in catalog)
      if (wanted.contains(loc.id) && loc.name.isNotEmpty) loc,
  ];
  final readings = await Future.wait(
    locations.map((loc) => repo.readings(loc.id)),
  );

  return {
    for (final (i, loc) in locations.indexed)
      if (readings[i].isNotEmpty)
        loc.matchKey: LocationClimate(location: loc, readings: readings[i]),
  };
});

/// The climate of the location a spool is put away in, or null when the spool
/// has no location, the location has no sensor, or the server has none of this.
LocationClimate? climateOfSpool(
  Map<String, LocationClimate> climates,
  Spool spool,
) {
  final name = spool.storageLocation?.trim().toLowerCase();
  if (name == null || name.isEmpty) return null;
  return climates[name];
}

/// Options for the spool "location" picker: server catalog ∪ locations already
/// used by existing spools. Sorted, unique. Mirrors bambuddy's choose-or-add
/// UX — the picker also keeps free text, and the backend auto-creates the
/// catalog entry from `storage_location` on save.
final locationOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final catalog = ref.watch(locationCatalogProvider).valueOrNull ?? const [];
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    for (final l in catalog)
      if (l.name.trim().isNotEmpty) l.name.trim(),
    for (final s in spools)
      if (s.storageLocation != null && s.storageLocation!.trim().isNotEmpty)
        s.storageLocation!.trim(),
  };
  final list = set.toList()..sort();
  return list;
});

/// Material dropdown options: fixed popular ones + materials from catalog profiles
/// and existing spools (preserved user values). Sorted, unique.
const _commonMaterials = [
  'PLA',
  'PETG',
  'ABS',
  'ASA',
  'TPU',
  'PA',
  'PC',
  'PVA',
  'HIPS',
  'PET',
  'PP',
];

/// Common filament subtypes/variants (Subtype field in bambuddy).
const _commonSubtypes = [
  'Basic',
  'Matte',
  'Silk',
  'Tough',
  'Translucent',
  'Glow',
  'Marble',
  'Metal',
  'Wood',
  'CF',
  'GF',
  'Sparkle',
  'Gradient',
];

final materialOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final presets = ref.watch(filamentPresetsProvider).valueOrNull ?? const [];
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    ..._commonMaterials,
    for (final p in presets)
      if (p.type.trim().isNotEmpty) p.type.trim(),
    for (final s in spools) s.material,
  };
  final list = set.toList()..sort();
  return list;
});

final brandOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final presets = ref.watch(filamentPresetsProvider).valueOrNull ?? const [];
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    for (final p in presets)
      if (p.brand != null && p.brand!.trim().isNotEmpty) p.brand!.trim(),
    for (final s in spools)
      if (s.brand != null && s.brand!.trim().isNotEmpty) s.brand!.trim(),
  };
  final list = set.toList()..sort();
  return list;
});

final subtypeOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    ..._commonSubtypes,
    for (final s in spools)
      if (s.subtype != null && s.subtype!.trim().isNotEmpty) s.subtype!.trim(),
  };
  final list = set.toList()..sort();
  return list;
});
