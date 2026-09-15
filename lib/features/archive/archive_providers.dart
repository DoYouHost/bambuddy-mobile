import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/filament_colour.dart';
import '../../core/models/archive.dart';
import '../../core/models/no_3mf_warning.dart';
import '../../core/models/print_run.dart';
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
    if (filters.material != null &&
        !filamentTypeTokens(a.filamentType).contains(filters.material)) {
      return false;
    }
    if (filters.colors.isNotEmpty) {
      final archiveColors = a.filamentColors;
      final matches = filters.colorMode == ColorFilterMode.or
          ? archiveColors.any(filters.colors.contains)
          : filters.colors.every(archiveColors.contains);
      if (!matches) return false;
    }
    if (filters.favoritesOnly && !a.isFavorite) return false;
    if (filters.hideFailed && printRunIsFailure(a.status)) return false;
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

  /// Archives whose favorite toggle is still waiting for the server.
  final _favoriteInFlight = <int>{};

  /// Toggle an archive's favorite flag. Flips locally at once for instant
  /// feedback, then reconciles with the server's returned value; on error the
  /// flag goes back and `false` is returned.
  ///
  /// A second tap on the same star before the first answers is ignored. The
  /// route toggles rather than sets, and two overlapping requests that both
  /// fail roll back in whichever order they land — the star could end up
  /// showing the opposite of what the server holds.
  Future<bool> toggleFavorite(int archiveId) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (!_favoriteInFlight.add(archiveId)) return true;
    final before = current.firstWhereOrNull((a) => a.id == archiveId);

    _patchRow(archiveId, (a) => a.withFavorite(!a.isFavorite));
    try {
      final updated = await ref
          .read(archiveRepositoryProvider)
          .toggleFavorite(archiveId);
      replace(updated);
      return true;
    } catch (e) {
      // Just this row's flag: the list may have changed while the request was
      // out, and a whole-list snapshot would undo that too. Rolled back on any
      // failure, so an unexpected one does not leave a star the server never
      // set; only a refusal is an answer, the rest goes on up.
      if (before != null) {
        _patchRow(archiveId, (a) => a.withFavorite(before.isFavorite));
      }
      if (e is! AppApiException) rethrow;
      return false;
    } finally {
      _favoriteInFlight.remove(archiveId);
    }
  }

  /// One row of the loaded list, rebuilt by [update]. Does nothing when the
  /// list has not loaded, or does not hold [archiveId].
  void _patchRow(int archiveId, Archive Function(Archive) update) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final a in current) a.id == archiveId ? update(a) : a,
    ]);
  }

  /// Put a re-read archive back in the list, in place.
  ///
  /// For an edit whose answer *is* the stored row: the loaded list is the
  /// screen's only copy of a print, and the alternative to writing one row into
  /// it is refetching all of them to see one number change.
  void replace(Archive updated) => _patchRow(updated.id, (_) => updated);

  /// Optimistic delete (swipe / sheet). [purgeStats] also removes the print
  /// from aggregate statistics. Error → restore the item, returns false.
  Future<bool> delete(int archiveId, {required bool purgeStats}) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final index = current.indexWhere((a) => a.id == archiveId);

    if (index >= 0) state = AsyncValue.data([...current]..removeAt(index));
    try {
      await ref
          .read(archiveRepositoryProvider)
          .delete(archiveId, purgeStats: purgeStats);
      return true;
    } catch (e) {
      // Any failure puts the row back; only a refusal is an answer.
      if (index >= 0) _putBack(current[index], index);
      if (e is! AppApiException) rethrow;
      return false;
    }
  }

  /// Rollback of one optimistic removal into the list as it is *now*. Restoring
  /// the snapshot taken before the request brought back rows deleted in the
  /// meantime — swipe A, swipe B, A fails, and B is on screen again.
  void _putBack(Archive row, int index) {
    final list = state.valueOrNull;
    // A refresh that landed meanwhile already holds the row the server kept.
    if (list == null || list.any((a) => a.id == row.id)) return;
    state = AsyncValue.data([...list]..insert(min(index, list.length), row));
  }

  void _removeRow(int archiveId) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data([
      for (final a in list)
        if (a.id != archiveId) a,
    ]);
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
    var deleted = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.delete(id, purgeStats: purgeStats);
        deleted++;
        // Row by row, from the list as it is now: the deletes run one at a
        // time, so the screen follows them instead of jumping at the end, and
        // whatever changed in between survives.
        _removeRow(id);
      } on AppApiException {
        failed++;
      }
    }
    return (ok: deleted, failed: failed);
  }
}

/// Lightweight printer list for picker (reprint / add to queue). Config only,
/// no statuses — cheaper than `fetchAll`.
final printersForPickerProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);

/// Whether to nudge the user about prints that archived without their 3MF, and
/// why — `GET /archives/no-3mf-warning`, read once per app run.
///
/// Skipped entirely once dismissed: the answer would change nothing, and the
/// route walks 30 days of archives to produce it. Not `autoDispose`, so leaving
/// the archive screen and coming back does not ask again.
final no3mfWarningProvider = FutureProvider<No3mfWarning>((ref) async {
  if (ref.watch(no3mfDismissedProvider)) return No3mfWarning.none;
  return ref.watch(archiveRepositoryProvider).no3mfWarning();
});

/// Whether the no-3MF nudge has been waved off. One-way: there is no un-dismiss,
/// on the web either.
final no3mfDismissedProvider = NotifierProvider<No3mfDismissedNotifier, bool>(
  No3mfDismissedNotifier.new,
);

class No3mfDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadNo3mfDismissed();

  Future<void> dismiss() async {
    await ref.read(settingsRepositoryProvider).saveNo3mfDismissed();
    state = true;
  }
}
