import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive.dart';
import '../../core/models/printer.dart';
import '../../providers.dart';

/// Page size during archive scrolling.
const _pageSize = 50;

/// Minimum query length required by server (shorter → 422).
const _minQueryLength = 2;

/// Archive list state: items + whether there's next page + active query.
class ArchiveState {
  const ArchiveState({
    this.items = const [],
    this.hasMore = true,
    this.loadingMore = false,
    this.query = '',
    this.searchFailed = false,
  });

  final List<Archive> items;
  final bool hasMore;
  final bool loadingMore;
  final String query;

  /// Search returned an error (server is unstable on short, frequent queries —
  /// see `_fetchPage`). UI shows a gentle message instead of crashing the screen.
  final bool searchFailed;

  ArchiveState copyWith({
    List<Archive>? items,
    bool? hasMore,
    bool? loadingMore,
    String? query,
    bool? searchFailed,
  }) =>
      ArchiveState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        query: query ?? this.query,
        searchFailed: searchFailed ?? this.searchFailed,
      );
}

final archiveProvider =
    AutoDisposeAsyncNotifierProvider<ArchiveNotifier, ArchiveState>(
  ArchiveNotifier.new,
);

/// Archive list with pagination (infinite scroll) and search (M5).
/// Empty `query` → `GET /archives/` (paginated); non-empty → `/archives/search`.
class ArchiveNotifier extends AutoDisposeAsyncNotifier<ArchiveState> {
  @override
  Future<ArchiveState> build() async {
    ref.watch(serverProfileProvider);
    return _fetchPage(query: '', offset: 0);
  }

  Future<ArchiveState> _fetchPage({
    required String query,
    required int offset,
  }) async {
    final repo = ref.read(archiveRepositoryProvider);
    final page = query.isEmpty
        ? await repo.list(limit: _pageSize, offset: offset)
        : await repo.search(query, limit: _pageSize, offset: offset);
    return ArchiveState(
      items: page,
      hasMore: page.length == _pageSize,
      query: query,
    );
  }

  /// New search / clear — resets list to first page.
  /// Query shorter than [_minQueryLength] is treated as empty (full list):
  /// server rejects <2 chars anyway (422). Search error doesn't crash the screen —
  /// we set [ArchiveState.searchFailed] and show a gentle message.
  Future<void> search(String query) async {
    final q = query.length >= _minQueryLength ? query : '';
    state = const AsyncValue<ArchiveState>.loading().copyWithPrevious(state);
    try {
      state = AsyncValue.data(await _fetchPage(query: q, offset: 0));
    } on AppApiException {
      state = AsyncValue.data(
        ArchiveState(items: const [], query: q, searchFailed: true),
      );
    }
  }

  /// Pull-to-refresh: re-fetch the first page of the current query.
  Future<void> refresh() async {
    final query = state.valueOrNull?.query ?? '';
    state = const AsyncValue<ArchiveState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _fetchPage(query: query, offset: 0));
  }

  /// Loads the next page and appends to list. No throwing — fetch error cannot
  /// break already-shown items (halts pagination).
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final repo = ref.read(archiveRepositoryProvider);
      final next = current.query.isEmpty
          ? await repo.list(limit: _pageSize, offset: current.items.length)
          : await repo.search(
              current.query,
              limit: _pageSize,
              offset: current.items.length,
            );
      state = AsyncValue.data(current.copyWith(
        items: [...current.items, ...next],
        hasMore: next.length == _pageSize,
        loadingMore: false,
      ));
    } on AppApiException {
      // Halt pagination, preserve what we have.
      state = AsyncValue.data(current.copyWith(
        hasMore: false,
        loadingMore: false,
      ));
    }
  }

  /// Optimistic delete (swipe / sheet). [purgeStats] also removes the print
  /// from aggregate statistics. Error → restore the item, returns false.
  Future<bool> delete(int archiveId, {required bool purgeStats}) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    state = AsyncValue.data(current.copyWith(
      items: current.items.where((a) => a.id != archiveId).toList(),
    ));
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
    state = AsyncValue.data(current.copyWith(
      items: current.items.where((a) => !deleted.contains(a.id)).toList(),
    ));
    return (ok: deleted.length, failed: failed);
  }
}

/// Lightweight printer list for picker (reprint / add to queue). Config only,
/// no statuses — cheaper than `fetchAll`.
final printersForPickerProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);
