import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive_slim.dart';
import '../../core/models/archive_stats.dart';
import '../../core/models/failure_analysis.dart';
import '../../core/models/user_summary.dart';
import '../../data/failure_analysis_cache.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'stats_computed.dart';

/// Active time range label — shared by AppBar and widget captions.
String statsRangeLabel(AppLocalizations l10n, StatsRange range) =>
    switch (range) {
      StatsRange.allTime => l10n.statsRangeAllTime,
      StatsRange.last7Days => l10n.statsRangeLast7Days,
      StatsRange.last30Days => l10n.statsRangeLast30Days,
      StatsRange.last90Days => l10n.statsRangeLast90Days,
      StatsRange.thisYear => l10n.statsRangeThisYear,
      StatsRange.custom => l10n.statsRangeCustom,
    };

/// Predefined time ranges for stats (equivalent of web "All Time" dropdown).
/// [custom] uses explicit [StatsFilter.from]/[StatsFilter.to].
enum StatsRange { allTime, last7Days, last30Days, last90Days, thisYear, custom }

/// Stats filter: time range (+ optional explicit dates for [StatsRange.custom]).
@immutable
class StatsFilter {
  const StatsFilter({
    this.range = StatsRange.allTime,
    this.from,
    this.to,
    this.createdById,
  });

  final StatsRange range;
  final DateTime? from;
  final DateTime? to;

  /// Print creator filter — `null` = all users (no filter sent), `-1` = no
  /// assigned user (system/unauthenticated), positive = specific user id.
  final int? createdById;

  StatsFilter copyWith({StatsRange? range, DateTime? from, DateTime? to}) =>
      StatsFilter(
        range: range ?? this.range,
        from: from ?? this.from,
        to: to ?? this.to,
        createdById: createdById,
      );

  @override
  bool operator ==(Object other) =>
      other is StatsFilter &&
      other.range == range &&
      other.from == from &&
      other.to == to &&
      other.createdById == createdById;

  @override
  int get hashCode => Object.hash(range, from, to, createdById);
}

/// Active stats filter. Changing value reloads [statsProvider].
final statsFilterProvider =
    NotifierProvider<StatsFilterNotifier, StatsFilter>(StatsFilterNotifier.new);

class StatsFilterNotifier extends Notifier<StatsFilter> {
  @override
  StatsFilter build() => const StatsFilter();

  void setRange(StatsRange range) {
    if (range == StatsRange.custom) return; // custom uses setCustom
    state = StatsFilter(range: range, createdById: state.createdById);
  }

  void setCustom(DateTime from, DateTime to) {
    state = StatsFilter(
      range: StatsRange.custom,
      from: from,
      to: to,
      createdById: state.createdById,
    );
  }

  /// `null` = All Users, `-1` = No User (System), positive = specific user id.
  void setCreatedById(int? createdById) {
    state = StatsFilter(
      range: state.range,
      from: state.from,
      to: state.to,
      createdById: createdById,
    );
  }
}

/// Fetched statistics for active [statsFilterProvider]. We compute `from`/`to`
/// dates from chosen range and delegate to repository. Relative dates anchored to
/// [now] computed once per build (no clock in state).
final statsProvider =
    AutoDisposeAsyncNotifierProvider<StatsNotifier, ArchiveStats>(
  StatsNotifier.new,
);

class StatsNotifier extends AutoDisposeAsyncNotifier<ArchiveStats> {
  @override
  Future<ArchiveStats> build() async {
    ref.watch(serverProfileProvider);
    final filter = ref.watch(statsFilterProvider);
    final (from, to) = _resolveDates(filter);
    return ref
        .read(statsRepositoryProvider)
        .fetch(from: from, to: to, createdById: filter.createdById);
  }

  /// Pull-to-refresh: refetch for current filter.
  Future<void> refresh() async {
    state = const AsyncValue<ArchiveStats>.loading().copyWithPrevious(state);
    final filter = ref.read(statsFilterProvider);
    final (from, to) = _resolveDates(filter);
    state = await AsyncValue.guard(
      () => ref
          .read(statsRepositoryProvider)
          .fetch(from: from, to: to, createdById: filter.createdById),
    );
  }

  /// Convert [StatsRange] to concrete `from`/`to`. `allTime` → both `null`
  /// (server returns all). Relative ranges computed backward from today.
  static (DateTime?, DateTime?) _resolveDates(StatsFilter f) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (f.range) {
      StatsRange.allTime => (null, null),
      StatsRange.last7Days => (today.subtract(const Duration(days: 6)), today),
      StatsRange.last30Days => (today.subtract(const Duration(days: 29)), today),
      StatsRange.last90Days => (today.subtract(const Duration(days: 89)), today),
      StatsRange.thisYear => (DateTime(now.year), today),
      StatsRange.custom => (f.from, f.to),
    };
  }
}

/// Map `printer_id → name` to label "by printer" breakdown. Config only
/// (no statuses) — cheap. Missing entry → UI shows `#id`.
final printerNamesProvider = FutureProvider.autoDispose<Map<int, String>>(
  (ref) async {
    final printers = await ref.watch(printersRepositoryProvider).fetchPrinters();
    return {for (final p in printers) p.id: p.name};
  },
);

/// Slim list of all prints for active filter — source of rich stats (heatmap,
/// records, colors, usage over time, histograms).
final archiveSlimProvider =
    FutureProvider.autoDispose<List<ArchiveSlim>>((ref) async {
  ref.watch(serverProfileProvider);
  final filter = ref.watch(statsFilterProvider);
  final (from, to) = StatsNotifier._resolveDates(filter);
  return ref
      .read(statsRepositoryProvider)
      .fetchSlim(from: from, to: to, createdById: filter.createdById);
});

/// Users for the Stats "filter by user" picker. Empty (including on 403 —
/// no permission) hides the picker entirely; this mirrors server-side
/// gating without the app needing its own permission model.
///
/// Which identities get a non-empty answer is up to the server: the repository
/// asks `/users/slim` first and falls back to the full listing, so on 1.2.6+
/// the picker also appears for API-key sessions holding the Read Status scope,
/// where before it never could.
final statsUsersProvider =
    FutureProvider.autoDispose<List<UserSummary>>((ref) async {
  ref.watch(serverProfileProvider);
  try {
    return await ref.read(statsRepositoryProvider).fetchUsers();
  } on AppApiException catch (e) {
    // Only a refusal means "this identity may not list users". Absorbing
    // everything else told the same story about a dropped connection, so a
    // server that was merely unreachable read as one that said no.
    if (e.code != AppErrorCode.forbidden) rethrow;
    return const [];
  }
});

/// Computed aggregates from slim list (pure calculation, no I/O).
final statsComputedProvider =
    Provider.autoDispose<AsyncValue<StatsComputed>>((ref) {
  return ref
      .watch(archiveSlimProvider)
      .whenData((items) => StatsComputed.from(items));
});

/// Persistent failure analysis cache (on disk, SharedPreferences).
final failureAnalysisCacheProvider = Provider<FailureAnalysisCache>(
  (ref) => FailureAnalysisCache(ref.watch(sharedPreferencesProvider)),
);

/// Failure analysis for active filter — with cache and incremental fetch.
/// On screen entry, immediately show last cached result, then fetch missing
/// period in background and update state:
/// - "all time": bank complete days (archive is append-only) and separately
///   add today's incomplete day — server counts only narrow window instead of
///   whole archive on each entry;
/// - other ranges: full refetch (stale-while-revalidate) because window's lower
///   bound shifts over time and pure increment isn't correct.
///
/// For "all time" instead of no dates (server would guess 30 days), anchor `from`
/// in far past to cover entire archive.
final failureAnalysisProvider =
    AutoDisposeAsyncNotifierProvider<FailureAnalysisNotifier, FailureAnalysis>(
  FailureAnalysisNotifier.new,
);

class FailureAnalysisNotifier
    extends AutoDisposeAsyncNotifier<FailureAnalysis> {
  var _disposed = false;

  @override
  Future<FailureAnalysis> build() async {
    ref.watch(serverProfileProvider);
    final filter = ref.watch(statsFilterProvider);
    // `onDispose` fires on every recompute (filter change), not just teardown —
    // reset here so a later build's background refresh isn't discarded because
    // an earlier build's dispose already flipped this to true for good.
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final cached = ref.read(failureAnalysisCacheProvider).load(filter);
    if (cached != null) {
      // Show cache immediately; fetch fresh data in background and update.
      _refreshInBackground(filter, cached);
      return cached.analysis;
    }
    // No cache (e.g., first launch) — full fetch.
    return _fetch(filter, base: null);
  }

  void _refreshInBackground(StatsFilter filter, FailureCacheEntry base) {
    Future(() async {
      try {
        final fresh = await _fetch(filter, base: base);
        if (!_disposed) state = AsyncData(fresh);
      } on Object {
        // Silent — cache stays shown on screen.
      }
    });
  }

  /// Compute fresh result and update cache. For "all time" append only missing
  /// period to [base]; otherwise full fetch of entire range.
  Future<FailureAnalysis> _fetch(
    StatsFilter filter, {
    required FailureCacheEntry? base,
  }) async {
    final repo = ref.read(statsRepositoryProvider);
    final cache = ref.read(failureAnalysisCacheProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (filter.range != StatsRange.allTime) {
      var (from, to) = StatsNotifier._resolveDates(filter);
      from ??= DateTime(2000);
      to ??= today;
      final full = await repo.fetchFailures(
          from: from, to: to, createdById: filter.createdById);
      await cache.save(filter,
          FailureCacheEntry(analysis: full, coveredThrough: null, fetchedAt: now));
      return full;
    }

    // "All time" incrementally. Cache holds aggregate of COMPLETE days
    // [2000..coveredThrough] WITHOUT today's (incomplete) day — that's always
    // fetched fresh to avoid freezing partial data in cache.
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    var banked = base?.analysis ?? const FailureAnalysis();
    final coveredThrough = base?.coveredThrough;
    final bankStart = coveredThrough == null
        ? DateTime(2000)
        : DateTime(coveredThrough.year, coveredThrough.month,
            coveredThrough.day + 1);
    // Bank days that closed since last time (typically 0–1 day).
    if (!bankStart.isAfter(yesterday)) {
      final bank = await repo.fetchFailures(
          from: bankStart, to: yesterday, createdById: filter.createdById);
      banked = banked.merge(bank);
      await cache.save(
        filter,
        FailureCacheEntry(
            analysis: banked, coveredThrough: yesterday, fetchedAt: now),
      );
    }
    // Today's incomplete day — separate, outside cache.
    final todayPart = await repo.fetchFailures(
        from: today, to: today, createdById: filter.createdById);
    return banked.merge(todayPart);
  }
}
