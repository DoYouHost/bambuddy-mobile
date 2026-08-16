import 'package:bambuddy_mobile/features/dashboard/widgets/history_chart_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thinnedForChart', () {
    test('krótka seria wraca nietknięta (ta sama lista)', () {
      final points = [1, 2, 3];

      expect(thinnedForChart(points, budget: 3), same(points));
    });

    test('długa seria schodzi do budżetu i trzyma oba końce', () {
      final thinned =
          thinnedForChart([for (var i = 0; i < 1000; i++) i], budget: 100);

      expect(thinned.length, lessThanOrEqualTo(101));
      expect(thinned.first, 0);
      expect(thinned.last, 999);
    });

    test('ostatni punkt zostaje, nawet gdy krok go przeskakuje', () {
      // 11 punktów, budżet 5 → krok 3: 0, 3, 6, 9 i dopięty koniec.
      expect(
        thinnedForChart([for (var i = 0; i < 11; i++) i], budget: 5),
        [0, 3, 6, 9, 10],
      );
    });

    test('krok trafiający w koniec nie dubluje ostatniego punktu', () {
      // 10 punktów, budżet 4 → krok 3: ostatni indeks (9) wypada na kroku.
      expect(
        thinnedForChart([for (var i = 0; i < 10; i++) i], budget: 4),
        [0, 3, 6, 9],
      );
    });
  });
}
