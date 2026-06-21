import 'package:bambuddy_mobile/core/models/archive_slim.dart';
import 'package:bambuddy_mobile/features/stats/stats_computed.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveSlim _a({
  required String status,
  required String createdAt,
  int? seconds,
  double? grams,
  String? material,
  String? color,
  double? cost,
  int? printerId,
}) =>
    ArchiveSlim.fromJson({
      'status': status,
      'created_at': createdAt,
      'actual_time_seconds': seconds,
      'filament_used_grams': grams,
      'filament_type': material,
      'filament_color': color,
      'cost': cost,
      'printer_id': printerId,
    });

void main() {
  group('ArchiveSlim', () {
    test('primaryColor bierze pierwszy segment i normalizuje do #RRGGBB', () {
      expect(_a(status: 'completed', createdAt: '2026-06-01', color: '#0acc38,#91202b')
          .primaryColor, '#0ACC38');
      expect(_a(status: 'completed', createdAt: '2026-06-01', color: '#FFFFFF')
          .primaryColor, '#FFFFFF');
      expect(_a(status: 'completed', createdAt: '2026-06-01', color: null)
          .primaryColor, isNull);
    });

    test('isSuccess true tylko dla completed', () {
      expect(_a(status: 'completed', createdAt: '2026-06-01').isSuccess, isTrue);
      expect(_a(status: 'failed', createdAt: '2026-06-01').isSuccess, isFalse);
    });
  });

  group('StatsComputed.from', () {
    final items = [
      _a(status: 'completed', createdAt: '2026-06-01T10:00:00', seconds: 1000, grams: 50, material: 'PLA', color: '#FF0000', cost: 1.5, printerId: 1),
      _a(status: 'completed', createdAt: '2026-06-01T14:00:00', seconds: 5000, grams: 120, material: 'PETG', color: '#00FF00', cost: 4.0, printerId: 1),
      _a(status: 'failed', createdAt: '2026-06-02T21:00:00', seconds: 90000, grams: 300, material: 'PLA', color: '#FF0000', cost: 9.0, printerId: 2),
    ];
    final c = StatsComputed.from(items);

    test('zlicza wydruki per dzień i wskazuje najbusy dzień', () {
      expect(c.printsByDay[DateTime(2026, 6, 1)], 2);
      expect(c.printsByDay[DateTime(2026, 6, 2)], 1);
      expect(c.busiestDay, DateTime(2026, 6, 1));
      expect(c.busiestDayCount, 2);
    });

    test('rekordy: najdłuższy / najcięższy / najdroższy', () {
      expect(c.longest!.effectiveSeconds, 90000);
      expect(c.heaviest!.filamentUsedGrams, 300);
      expect(c.mostExpensive!.cost, 9.0);
    });

    test('seria sukcesów liczona chronologicznie', () {
      // 2 udane (1 czerwca) → seria 2, potem porażka zeruje.
      expect(c.bestSuccessStreak, 2);
    });

    test('histogram czasu trwania trafia w kubełki', () {
      // 1000s (<30m) → 0, 5000s (1–2h) → 2, 90000s (24h+) → 7.
      expect(c.durationBuckets[0], 1);
      expect(c.durationBuckets[2], 1);
      expect(c.durationBuckets[durationBucketCount - 1], 1);
    });

    test('rozbicie po materiale: wagi i skuteczność', () {
      expect(c.byMaterial['PLA']!.grams, 350);
      expect(c.byMaterial['PLA']!.prints, 2);
      expect(c.byMaterial['PLA']!.successRate, 50);
      expect(c.byMaterial['PETG']!.successRate, 100);
    });

    test('kolory i drukarki agregowane', () {
      expect(c.gramsByColor['#FF0000'], 350);
      expect(c.printsByColor['#FF0000'], 2);
      expect(c.byPrinter[1]!.prints, 2);
      expect(c.byPrinter[2]!.prints, 1);
    });

    test('godziny doby', () {
      expect(c.byHour[10], 1);
      expect(c.byHour[14], 1);
      expect(c.byHour[21], 1);
      expect(c.failedByHour[21], 1);
    });
  });
}
