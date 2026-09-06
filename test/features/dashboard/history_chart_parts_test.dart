import 'package:bambuddy_mobile/features/dashboard/widgets/history_chart_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thinnedForChart', () {
    test('a short series comes back untouched (the same list)', () {
      final points = [1, 2, 3];

      expect(thinnedForChart(points, budget: 3), same(points));
    });

    test('a long series comes down to budget and keeps both ends', () {
      final thinned = thinnedForChart([
        for (var i = 0; i < 1000; i++) i,
      ], budget: 100);

      expect(thinned.length, lessThanOrEqualTo(101));
      expect(thinned.first, 0);
      expect(thinned.last, 999);
    });

    test('the last point stays, even when the step skips over it', () {
      // 11 points, budget 5 → step 3: 0, 3, 6, 9 and the end pinned on.
      expect(thinnedForChart([for (var i = 0; i < 11; i++) i], budget: 5), [
        0,
        3,
        6,
        9,
        10,
      ]);
    });

    test('a step that lands on the end does not duplicate the last point', () {
      // 10 points, budget 4 → step 3: the last index (9) falls right on the step.
      expect(thinnedForChart([for (var i = 0; i < 10; i++) i], budget: 4), [
        0,
        3,
        6,
        9,
      ]);
    });
  });
}
