import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/inventory.dart';
import '../../core/models/inventory_reference.dart';
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
  Future<Spool?> _mutate(Future<Spool?> Function(InventoryRepository) action) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      return await action(repo);
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  Future<Spool?> createSpool(SpoolDraft draft) =>
      _mutate((repo) => repo.createSpool(draft));

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
  Future<void> assignSpool(SpoolAssignmentDraft draft,
          {SpoolAssignment? from}) =>
      _mutate((repo) async {
        if (from != null &&
            !(from.printerId == draft.printerId &&
                from.amsId == draft.amsId &&
                from.trayId == draft.trayId)) {
          await repo.unassignSpool(from.printerId, from.amsId, from.trayId);
        }
        await repo.assignSpool(draft);
        return null;
      });

  Future<void> unassignSpool(int printerId, int amsId, int trayId) => _mutate(
      (repo) async =>
          repo.unassignSpool(printerId, amsId, trayId).then((_) => null));
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
final assignedSpoolsProvider =
    Provider.autoDispose.family<AssignedSpools, int>((ref, printerId) {
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
  }) =>
      InventoryFilters(
        showArchived: showArchived ?? this.showArchived,
        lowStockOnly: lowStockOnly ?? this.lowStockOnly,
        materials: materials ?? this.materials,
        brands: brands ?? this.brands,
        locations: locations ?? this.locations,
      );
}

final inventoryFiltersProvider =
    StateProvider.autoDispose<InventoryFilters>((_) => const InventoryFilters());

/// Spool usage history — loaded on demand in details (family by id).
final spoolUsageProvider = FutureProvider.autoDispose
    .family<List<SpoolUsageEntry>, int>(
  (ref, spoolId) => ref.watch(inventoryRepositoryProvider).fetchUsage(spoolId),
);

/// Spool form reference data (Phase 2). Loaded on form open; degrades to empty list
/// (form allows manual entry), so errors don't block spool creation. Kept briefly
/// after close (`keepAlive`) so reopening doesn't fetch again.
final coreWeightsProvider =
    FutureProvider.autoDispose<List<CoreWeightEntry>>((ref) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchCoreWeights();
  } on Object {
    return const [];
  }
});

final colorCatalogProvider =
    FutureProvider.autoDispose<List<ColorEntry>>((ref) async {
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
    return await ref.watch(inventoryRepositoryProvider).fetchFilamentPresets();
  } on Object {
    return const [];
  }
});

/// Material dropdown options: fixed popular ones + materials from catalog profiles
/// and existing spools (preserved user values). Sorted, unique.
const _commonMaterials = [
  'PLA', 'PETG', 'ABS', 'ASA', 'TPU', 'PA', 'PC', 'PVA', 'HIPS', 'PET', 'PP',
];

/// Common filament subtypes/variants (Subtype field in bambuddy).
const _commonSubtypes = [
  'Basic', 'Matte', 'Silk', 'Tough', 'Translucent', 'Glow', 'Marble',
  'Metal', 'Wood', 'CF', 'GF', 'Sparkle', 'Gradient',
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
