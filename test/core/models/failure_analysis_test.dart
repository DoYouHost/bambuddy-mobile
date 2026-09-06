import 'package:bambuddy_mobile/core/models/failure_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FailureAnalysis.fromJson', () {
    test('parses /archives/analysis/failures response', () {
      final f = FailureAnalysis.fromJson(const {
        'period_days': 90,
        'total_prints': 90,
        'failed_prints': 3,
        'failure_rate': 3.3,
        'failures_by_reason': {'Unknown': 3},
        'failures_by_printer': {'1': 2, '2': 1},
      });
      expect(f.totalPrints, 90);
      expect(f.failedPrints, 3);
      expect(f.failureRate, 3.3);
      expect(f.failuresByReason, {'Unknown': 3});
      expect(f.failuresByFilament, isEmpty);
    });
  });

  group('FailureAnalysis round-trip', () {
    test('toJson → fromJson preserves fields', () {
      const f = FailureAnalysis(
        periodDays: 30,
        totalPrints: 50,
        failedPrints: 5,
        failureRate: 10,
        failuresByReason: {'A': 3, 'B': 2},
        failuresByPrinter: {'1': 5},
      );
      final back = FailureAnalysis.fromJson(f.toJson());
      expect(back.totalPrints, 50);
      expect(back.failedPrints, 5);
      expect(back.failureRate, 10);
      expect(back.failuresByReason, {'A': 3, 'B': 2});
      expect(back.failuresByPrinter, {'1': 5});
    });
  });

  group('FailureAnalysis.merge', () {
    test('sums counters and merges maps per key', () {
      const a = FailureAnalysis(
        totalPrints: 80,
        failedPrints: 4,
        failuresByReason: {'Unknown': 3, 'Adhesion': 1},
      );
      const b = FailureAnalysis(
        totalPrints: 10,
        failedPrints: 1,
        failuresByReason: {'Unknown': 1},
      );
      final m = a.merge(b);
      expect(m.totalPrints, 90);
      expect(m.failedPrints, 5);
      expect(m.failuresByReason, {'Unknown': 4, 'Adhesion': 1});
    });

    test('failureRate calculated from sums, not average of percentages', () {
      // 0% on 90 prints + 100% on 10 prints = 10/100, i.e. 10% (not 50%).
      const a = FailureAnalysis(
        totalPrints: 90,
        failedPrints: 0,
        failureRate: 0,
      );
      const b = FailureAnalysis(
        totalPrints: 10,
        failedPrints: 10,
        failureRate: 100,
      );
      expect(a.merge(b).failureRate, 10);
    });

    test('merging with empty aggregate is neutral', () {
      const base = FailureAnalysis();
      const day = FailureAnalysis(
        totalPrints: 3,
        failedPrints: 1,
        failureRate: 33.3,
        failuresByReason: {'Unknown': 1},
      );
      final m = base.merge(day);
      expect(m.totalPrints, 3);
      expect(m.failedPrints, 1);
      expect(m.failuresByReason, {'Unknown': 1});
    });
  });
}
