import 'package:bambuddy_mobile/core/models/failure_analysis.dart';
import 'package:bambuddy_mobile/data/failure_analysis_cache.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FailureAnalysisCache.signature', () {
    test('differs for different createdById — no collision between users', () {
      const allUsers = StatsFilter();
      const noUser = StatsFilter(createdById: -1);
      const user5 = StatsFilter(createdById: 5);
      const user9 = StatsFilter(createdById: 9);

      final sigs = {
        FailureAnalysisCache.signature(allUsers),
        FailureAnalysisCache.signature(noUser),
        FailureAnalysisCache.signature(user5),
        FailureAnalysisCache.signature(user9),
      };
      expect(sigs, hasLength(4)); // all unique — no collision.
    });

    test('same range and createdById → same signature', () {
      const a = StatsFilter(range: StatsRange.last30Days, createdById: 5);
      const b = StatsFilter(range: StatsRange.last30Days, createdById: 5);
      expect(
        FailureAnalysisCache.signature(a),
        FailureAnalysisCache.signature(b),
      );
    });
  });

  group('FailureCacheEntry survives the trip through preferences', () {
    const analysis = FailureAnalysis(
      periodDays: 30,
      totalPrints: 41,
      failedPrints: 3,
      failureRate: 7.3,
    );

    FailureCacheEntry? roundTrip(FailureCacheEntry entry) =>
        FailureCacheEntry.fromJson(entry.toJson());

    test('a banked day comes back as the same calendar day', () {
      // `coveredThrough` decides which days the "all time" bucket may append
      // without re-fetching, so a day that moves across a zone boundary either
      // re-counts a day or silently drops one.
      final entry = FailureCacheEntry(
        analysis: analysis,
        coveredThrough: DateTime(2026, 9, 14),
        fetchedAt: DateTime(2026, 9, 15, 11, 42, 9),
      );

      final back = roundTrip(entry)!;
      expect(back.coveredThrough, DateTime(2026, 9, 14));
      expect(back.analysis.totalPrints, 41);
      expect(back.analysis.failedPrints, 3);
    });

    test('the fetch instant comes back as the same local instant', () {
      // Written with `toIso8601String`, which leaves a local value zoneless.
      // Reading it as UTC would shift it by the device's offset — the trap the
      // server-side readers exist for, and the reason this one is not them.
      final fetched = DateTime(2026, 9, 15, 11, 42, 9);
      final entry = FailureCacheEntry(
        analysis: analysis,
        coveredThrough: null,
        fetchedAt: fetched,
      );

      expect(roundTrip(entry)!.fetchedAt, fetched);
    });

    test('no banked day stays no banked day', () {
      final entry = FailureCacheEntry(
        analysis: analysis,
        coveredThrough: null,
        fetchedAt: DateTime(2026, 9, 15),
      );

      expect(roundTrip(entry)!.coveredThrough, isNull);
    });

    test('an entry without an analysis is not an entry', () {
      // The blob comes back off disk, where a half-written or older-shaped
      // record is possible; the cache treats that as a miss rather than as an
      // aggregate of zeroes, which would read as "41 prints, none failed".
      expect(FailureCacheEntry.fromJson(const {'fetched_at': 'x'}), isNull);
    });
  });
}
