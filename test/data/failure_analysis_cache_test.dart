import 'package:bambuddy_mobile/data/failure_analysis_cache.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FailureAnalysisCache.signature', () {
    test('różni się dla różnych createdById — brak kolizji między userami', () {
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
      expect(sigs, hasLength(4)); // wszystkie unikalne — żadnej kolizji.
    });

    test('ten sam zakres i createdById → ten sam podpis', () {
      const a = StatsFilter(range: StatsRange.last30Days, createdById: 5);
      const b = StatsFilter(range: StatsRange.last30Days, createdById: 5);
      expect(
        FailureAnalysisCache.signature(a),
        FailureAnalysisCache.signature(b),
      );
    });
  });
}
