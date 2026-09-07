import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/print_log_entry.dart';
import '../../data/print_log_repository.dart';
import '../../providers.dart';
import '../stats/stats_providers.dart';

/// How many rows one page asks for. Well under the server's cap of 500
/// ([PrintLogRepository.maxPageSize]) — the list pages on the wire, unlike the
/// archive screen, which loads everything once and filters locally.
const printLogPageSize = 50;

/// What the print log is filtered by. Every field here is a server-side
/// filter — the endpoint pages, so filtering the rows already loaded would
/// answer "the failures on this page" rather than "the failures".
@immutable
class PrintLogFilters {
  const PrintLogFilters({
    this.query = '',
    this.printerId,
    this.status,
    this.username,
    this.from,
    this.to,
    this.sort = PrintLogSort.date,
    this.descending = true,
  });

  /// Matched against the print name (`ilike`), nothing else.
  final String query;

  final int? printerId;
  final String? status;
  final String? username;

  /// Inclusive range over the run's `created_at`, as local instants.
  final DateTime? from;
  final DateTime? to;

  final PrintLogSort sort;
  final bool descending;

  /// Drives the badge on the filter button. Search and sort are surfaced
  /// separately, so they don't count — same rule as `ArchiveFilters`.
  int get activeCount =>
      (printerId != null ? 1 : 0) +
      (status != null ? 1 : 0) +
      (username != null ? 1 : 0) +
      (from != null || to != null ? 1 : 0);

  /// Nullable fields can't be cleared through the usual `?? this` idiom, so
  /// each takes an explicit "clear" flag.
  PrintLogFilters copyWith({
    String? query,
    int? printerId,
    bool clearPrinter = false,
    String? status,
    bool clearStatus = false,
    String? username,
    bool clearUsername = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    PrintLogSort? sort,
    bool? descending,
  }) => PrintLogFilters(
    query: query ?? this.query,
    printerId: clearPrinter ? null : (printerId ?? this.printerId),
    status: clearStatus ? null : (status ?? this.status),
    username: clearUsername ? null : (username ?? this.username),
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
  );

  @override
  bool operator ==(Object other) =>
      other is PrintLogFilters &&
      other.query == query &&
      other.printerId == printerId &&
      other.status == status &&
      other.username == username &&
      other.from == from &&
      other.to == to &&
      other.sort == sort &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(
    query,
    printerId,
    status,
    username,
    from,
    to,
    sort,
    descending,
  );
}

/// Active filters. Kept apart from the list itself so changing one re-runs the
/// query without the screen having to hold both.
final printLogFiltersProvider =
    NotifierProvider.autoDispose<PrintLogFiltersNotifier, PrintLogFilters>(
      PrintLogFiltersNotifier.new,
    );

class PrintLogFiltersNotifier extends AutoDisposeNotifier<PrintLogFilters> {
  @override
  PrintLogFilters build() => const PrintLogFilters();

  void set(PrintLogFilters filters) => state = filters;

  void setQuery(String query) => state = state.copyWith(query: query);

  /// Clears the structured filters — not the search, which [activeCount]
  /// deliberately leaves out and which has its own box on screen. That box owns
  /// its text, so dropping `query` here left the two disagreeing: the field kept
  /// showing what the user typed while the list had stopped filtering by it.
  void clear() => state = PrintLogFilters(
    query: state.query,
    sort: state.sort,
    descending: state.descending,
  );
}

/// What the screen renders: the rows loaded so far, how many the filter matches
/// in total, and whether another page is on its way.
@immutable
class PrintLogState {
  const PrintLogState({
    required this.items,
    required this.total,
    this.loadingMore = false,
  });

  final List<PrintLogEntry> items;

  /// Rows matching the current filter server-side — not `items.length`. It is
  /// what says whether there is more to load, and what the clear-log
  /// confirmation would be counting if it counted the filter (it does not: the
  /// route ignores filters).
  final int total;

  final bool loadingMore;

  bool get hasMore => items.length < total;

  PrintLogState copyWith({
    List<PrintLogEntry>? items,
    int? total,
    bool? loadingMore,
  }) => PrintLogState(
    items: items ?? this.items,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

final printLogProvider =
    AutoDisposeAsyncNotifierProvider<PrintLogNotifier, PrintLogState>(
      PrintLogNotifier.new,
    );

/// The print log, one page at a time.
///
/// Mutations here change what the Stats screen's Failure Analysis groups by, so
/// each one drops that cache — see [_invalidateFailureViews].
class PrintLogNotifier extends AutoDisposeAsyncNotifier<PrintLogState> {
  /// Bumped by every rebuild and by teardown. An async write compares the value
  /// it started from against the current one, and drops its result when they
  /// differ — the answer it is holding belongs to a state that is gone.
  ///
  /// A plain `disposed` flag cannot do this. `onDispose` fires on every
  /// rebuild, not only on teardown, so the flag has to be cleared in [build] —
  /// and a page still in flight when the filters changed slips straight through
  /// the cleared flag and writes the previous filter's rows over the new
  /// filter's. Counting instead of flagging tells the two cases apart, and
  /// covers teardown as the case with no next build.
  var _epoch = 0;

  @override
  Future<PrintLogState> build() async {
    ref.watch(serverProfileProvider);
    final filters = ref.watch(printLogFiltersProvider);
    _epoch++;
    ref.onDispose(() => _epoch++);
    return _page(filters, offset: 0);
  }

  Future<PrintLogState> _page(
    PrintLogFilters filters, {
    required int offset,
    List<PrintLogEntry> before = const [],
  }) async {
    final page = await ref
        .read(printLogRepositoryProvider)
        .list(
          search: filters.query.trim(),
          printerId: filters.printerId,
          status: filters.status,
          createdByUsername: filters.username,
          dateFrom: filters.from,
          dateTo: filters.to,
          limit: printLogPageSize,
          offset: offset,
          sort: filters.sort,
          descending: filters.descending,
        );
    return PrintLogState(items: [...before, ...page.items], total: page.total);
  }

  /// Pull-to-refresh: back to the first page, keeping the filters.
  Future<void> refresh() async {
    final filters = ref.read(printLogFiltersProvider);
    final epoch = _epoch;
    state = const AsyncValue<PrintLogState>.loading().copyWithPrevious(state);
    final next = await AsyncValue.guard(() => _page(filters, offset: 0));
    if (epoch != _epoch) return;
    state = next;
  }

  /// Append the next page. A failure leaves what is already on screen alone —
  /// the list is still usable, and the user can ask again by scrolling.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;

    final epoch = _epoch;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final next = await _page(
        ref.read(printLogFiltersProvider),
        offset: current.items.length,
        before: current.items,
      );
      if (epoch != _epoch) return;
      state = AsyncValue.data(next);
    } on AppApiException {
      if (epoch != _epoch) return;
      state = AsyncValue.data(current.copyWith(loadingMore: false));
    }
  }

  /// Re-classify one run. Returns the exception to show, or null on success.
  ///
  /// The row is merged rather than replaced by the response: a server older
  /// than 1.2.6 leaves cost and energy out of the PATCH answer exactly as it
  /// leaves them out of the list, so taking the answer wholesale would blank
  /// whatever those columns held (see [PrintLogEntry.copyWith]).
  Future<AppApiException?> reclassify(
    int entryId, {
    String? failureReason,
    bool clearFailureReason = false,
    String? status,
  }) async {
    final epoch = _epoch;
    try {
      final updated = await ref
          .read(printLogRepositoryProvider)
          .updateEntry(
            entryId,
            failureReason: failureReason,
            clearFailureReason: clearFailureReason,
            status: status,
          );
      // The edit landed either way; only the local merge is skipped when the
      // rows it would touch are no longer on screen.
      if (epoch != _epoch) return null;
      _replace(
        entryId,
        // A null cause nullifies the field rather than meaning "unchanged" —
        // see [PrintLogEntry], whose generated copy draws that line for us.
        (row) => row.copyWith(
          failureReason: updated.failureReason,
          status: updated.status,
        ),
      );
      await _invalidateFailureViews();
      return null;
    } on AppApiException catch (e) {
      return e;
    }
  }

  /// Delete one run. Returns the exception to show, or null on success.
  Future<AppApiException?> deleteEntry(int entryId) async {
    final epoch = _epoch;
    try {
      // The request goes first and unconditionally. Reading the list before it
      // and giving up on an empty one reported success for a delete that never
      // happened — reachable whenever the list is in its error state, which is
      // exactly when a stale row is most likely to be the one being deleted.
      await ref.read(printLogRepositoryProvider).deleteEntry(entryId);
      final current = state.valueOrNull;
      if (epoch == _epoch && current != null) {
        state = AsyncValue.data(
          current.copyWith(
            items: [
              for (final row in current.items)
                if (row.id != entryId) row,
            ],
            // The row left the server's count too, so the "load more" arithmetic
            // stays right without a refetch.
            total: current.total > 0 ? current.total - 1 : 0,
          ),
        );
      }
      await _invalidateFailureViews();
      return null;
    } on AppApiException catch (e) {
      return e;
    }
  }

  /// Clear the whole log — every user's rows, every filter ignored. Answers how
  /// many went, or the exception to show.
  Future<(int?, AppApiException?)> clearAll() async {
    final epoch = _epoch;
    try {
      final deleted = await ref.read(printLogRepositoryProvider).clearAll();
      if (epoch != _epoch) return (deleted, null);
      state = const AsyncValue.data(PrintLogState(items: [], total: 0));
      await _invalidateFailureViews();
      return (deleted, null);
    } on AppApiException catch (e) {
      return (null, e);
    }
  }

  void _replace(int entryId, PrintLogEntry Function(PrintLogEntry) update) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: [
          for (final row in current.items)
            if (row.id == entryId) update(row) else row,
        ],
      ),
    );
  }

  /// Everything downstream that reads what was just changed.
  ///
  /// The disk cache has to go first and by hand: Failure Analysis serves it
  /// immediately on screen entry, and its "all time" bucket only ever appends
  /// complete days — so an invalidated provider would rebuild straight back
  /// into the pre-edit grouping.
  Future<void> _invalidateFailureViews() async {
    await ref.read(failureAnalysisCacheProvider).clear();
    ref.invalidate(failureAnalysisProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(archiveSlimProvider);
  }
}
