import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive.dart';
import '../../core/models/printer.dart';
import '../../providers.dart';

/// Upper bound on how many archives we load in one shot. Filtering/sorting runs
/// client-side over the full set (matching bambuddy), so we fetch everything
/// once rather than paginating on the wire. Mirrors bambuddy's `limit=10000`.
const _fullListLimit = 10000;

/// How archives are ordered in the list. Values match bambuddy's sort options.
enum ArchiveSort { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

/// File-kind filter: all files, sliced (gcode) only, or source projects only.
enum ArchiveFileType { all, gcode, source }

/// Whether multiple selected colors are combined with OR (any match) or
/// AND (must have all). Mirrors bambuddy's `colorFilterMode`.
enum ColorFilterMode { or, and }

/// Client-side archive filters, all applied over the full loaded list.
/// Empty collections / falsey flags mean "no constraint". [sort] is a view
/// preference, not a filter, so it is excluded from [activeCount].
class ArchiveFilters {
  const ArchiveFilters({
    this.query = '',
    this.printerId,
    this.material,
    this.colors = const {},
    this.colorMode = ColorFilterMode.or,
    this.favoritesOnly = false,
    this.hideFailed = false,
    this.hideDuplicates = false,
    this.fileType = ArchiveFileType.all,
    this.sort = ArchiveSort.dateDesc,
  });

  final String query;
  final int? printerId;
  final String? material;
  final Set<String> colors;
  final ColorFilterMode colorMode;
  final bool favoritesOnly;
  final bool hideFailed;
  final bool hideDuplicates;
  final ArchiveFileType fileType;
  final ArchiveSort sort;

  /// Number of active filters — drives the badge on the filter button. Search
  /// and sort are surfaced separately, so they don't count here.
  int get activeCount =>
      (printerId != null ? 1 : 0) +
      (material != null ? 1 : 0) +
      (colors.isNotEmpty ? 1 : 0) +
      (favoritesOnly ? 1 : 0) +
      (hideFailed ? 1 : 0) +
      (hideDuplicates ? 1 : 0) +
      (fileType != ArchiveFileType.all ? 1 : 0);

  /// Nullable fields (`printerId`, `material`) can't be cleared through the
  /// usual `?? this` idiom, so each takes an explicit "clear" flag.
  ArchiveFilters copyWith({
    String? query,
    int? printerId,
    bool clearPrinter = false,
    String? material,
    bool clearMaterial = false,
    Set<String>? colors,
    ColorFilterMode? colorMode,
    bool? favoritesOnly,
    bool? hideFailed,
    bool? hideDuplicates,
    ArchiveFileType? fileType,
    ArchiveSort? sort,
  }) => ArchiveFilters(
    query: query ?? this.query,
    printerId: clearPrinter ? null : (printerId ?? this.printerId),
    material: clearMaterial ? null : (material ?? this.material),
    colors: colors ?? this.colors,
    colorMode: colorMode ?? this.colorMode,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    hideFailed: hideFailed ?? this.hideFailed,
    hideDuplicates: hideDuplicates ?? this.hideDuplicates,
    fileType: fileType ?? this.fileType,
    sort: sort ?? this.sort,
  );
}

final archiveFiltersProvider = StateProvider.autoDispose<ArchiveFilters>(
  (_) => const ArchiveFilters(),
);

/// Apply [filters] to [archives] client-side: search, printer, material, color,
/// favorites, hide-failed, hide-duplicates and file-type, then sort. Pure so it
/// can be unit-tested in isolation. Matches bambuddy's filtering semantics.
List<Archive> applyArchiveFilters(
  List<Archive> archives,
  ArchiveFilters filters,
) {
  final q = filters.query.trim().toLowerCase();
  final result = archives.where((a) {
    if (q.isNotEmpty && !a.displayName.toLowerCase().contains(q)) return false;
    if (filters.printerId != null && a.printerId != filters.printerId) {
      return false;
    }
    // Material is stored as a comma+space list for multi-material prints.
    if (filters.material != null) {
      final types = a.filamentType?.split(', ') ?? const [];
      if (!types.contains(filters.material)) return false;
    }
    if (filters.colors.isNotEmpty) {
      final archiveColors = a.filamentColors;
      final matches = filters.colorMode == ColorFilterMode.or
          ? archiveColors.any(filters.colors.contains)
          : filters.colors.every(archiveColors.contains);
      if (!matches) return false;
    }
    if (filters.favoritesOnly && !a.isFavorite) return false;
    if (filters.hideFailed && (a.status == 'failed' || a.status == 'aborted')) {
      return false;
    }
    // Keep the original of each duplicate group (sequence 0), drop the copies.
    if (filters.hideDuplicates &&
        a.duplicateCount > 0 &&
        a.duplicateSequence > 0) {
      return false;
    }
    switch (filters.fileType) {
      case ArchiveFileType.gcode:
        if (!a.isSliced) return false;
      case ArchiveFileType.source:
        if (a.isSliced) return false;
      case ArchiveFileType.all:
        break;
    }
    return true;
  }).toList();

  int byDate(Archive a, Archive b) => (a.createdAt?.millisecondsSinceEpoch ?? 0)
      .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0);
  int byName(Archive a, Archive b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  int bySize(Archive a, Archive b) =>
      (a.fileSize ?? 0).compareTo(b.fileSize ?? 0);

  switch (filters.sort) {
    case ArchiveSort.dateDesc:
      result.sort((a, b) => byDate(b, a));
    case ArchiveSort.dateAsc:
      result.sort(byDate);
    case ArchiveSort.nameAsc:
      result.sort(byName);
    case ArchiveSort.nameDesc:
      result.sort((a, b) => byName(b, a));
    case ArchiveSort.sizeDesc:
      result.sort((a, b) => bySize(b, a));
    case ArchiveSort.sizeAsc:
      result.sort(bySize);
  }
  return result;
}

final archiveProvider =
    AutoDisposeAsyncNotifierProvider<ArchiveNotifier, List<Archive>>(
      ArchiveNotifier.new,
    );

/// One archive read fresh from the server — what the photo viewer opens on, so
/// a shot attached after the list was loaded still shows up.
final archiveDetailProvider = FutureProvider.autoDispose.family<Archive, int>(
  (ref, archiveId) => ref.watch(archiveRepositoryProvider).byId(archiveId),
);

/// Full archive list, loaded once and filtered client-side (M5, filters M7).
/// All filtering/sorting lives in [applyArchiveFilters] over this list.
class ArchiveNotifier extends AutoDisposeAsyncNotifier<List<Archive>> {
  @override
  Future<List<Archive>> build() async {
    ref.watch(serverProfileProvider);
    return ref
        .read(archiveRepositoryProvider)
        .list(limit: _fullListLimit, offset: 0);
  }

  /// Pull-to-refresh: reload the full list.
  Future<void> refresh() async {
    state = const AsyncValue<List<Archive>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref
          .read(archiveRepositoryProvider)
          .list(limit: _fullListLimit, offset: 0),
    );
  }

  /// Toggle an archive's favorite flag. Flips locally at once for instant
  /// feedback, then reconciles with the server's returned value; on error the
  /// previous list is restored and `false` is returned.
  Future<bool> toggleFavorite(int archiveId) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    state = AsyncValue.data([
      for (final a in current)
        a.id == archiveId ? a.withFavorite(!a.isFavorite) : a,
    ]);
    try {
      final updated = await ref
          .read(archiveRepositoryProvider)
          .toggleFavorite(archiveId);
      state = AsyncValue.data([
        for (final a in state.valueOrNull ?? current)
          a.id == archiveId ? updated : a,
      ]);
      return true;
    } on AppApiException {
      state = AsyncValue.data(current); // rollback
      return false;
    }
  }

  /// Optimistic delete (swipe / sheet). [purgeStats] also removes the print
  /// from aggregate statistics. Error → restore the item, returns false.
  Future<bool> delete(int archiveId, {required bool purgeStats}) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    state = AsyncValue.data(current.where((a) => a.id != archiveId).toList());
    try {
      await ref
          .read(archiveRepositoryProvider)
          .delete(archiveId, purgeStats: purgeStats);
      return true;
    } on AppApiException {
      state = AsyncValue.data(current); // rollback
      return false;
    }
  }

  /// Delete several prints (multi-select). No bulk-by-id endpoint exists, so
  /// each is deleted individually; successful ones are dropped from the list,
  /// failed ones are kept. Returns how many succeeded / failed.
  Future<({int ok, int failed})> deleteMany(
    Set<int> ids, {
    required bool purgeStats,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return (ok: 0, failed: ids.length);

    final repo = ref.read(archiveRepositoryProvider);
    final deleted = <int>{};
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.delete(id, purgeStats: purgeStats);
        deleted.add(id);
      } on AppApiException {
        failed++;
      }
    }
    state = AsyncValue.data(
      current.where((a) => !deleted.contains(a.id)).toList(),
    );
    return (ok: deleted.length, failed: failed);
  }
}

/// Lightweight printer list for picker (reprint / add to queue). Config only,
/// no statuses — cheaper than `fetchAll`.
final printersForPickerProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);
