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
  double? energyKwh,
  double? energyCost,
}) => ArchiveSlim.fromJson({
  'status': status,
  'created_at': createdAt,
  'actual_time_seconds': seconds,
  'filament_used_grams': grams,
  'filament_type': material,
  'filament_color': color,
  'cost': cost,
  'printer_id': printerId,
  'energy_kwh': energyKwh,
  'energy_cost': energyCost,
});

void main() {
  group('ArchiveSlim', () {
    test('primaryColor takes the first segment and normalizes to #RRGGBB', () {
      expect(
        _a(
          status: 'completed',
          createdAt: '2026-06-01',
          color: '#0acc38,#91202b',
        ).primaryColor,
        '#0ACC38',
      );
      expect(
        _a(
          status: 'completed',
          createdAt: '2026-06-01',
          color: '#FFFFFF',
        ).primaryColor,
        '#FFFFFF',
      );
      expect(
        _a(
          status: 'completed',
          createdAt: '2026-06-01',
          color: null,
        ).primaryColor,
        isNull,
      );
    });

    test('isSuccess true only for completed', () {
      expect(
        _a(status: 'completed', createdAt: '2026-06-01').isSuccess,
        isTrue,
      );
      expect(_a(status: 'failed', createdAt: '2026-06-01').isSuccess, isFalse);
    });
  });

  group('StatsComputed.from', () {
    // The server stamps UTC and some schemas don't append `Z` (see
    // [dateTimeFromJson]), and stats bucket by **local** time: "what time you
    // print at" only makes sense in the user's timezone. So instants are kept
    // explicitly in UTC, and expectations are computed from those same
    // instants — otherwise the test would only pass in the timezone it was
    // written in. (The previous version gave `2026-06-01T10:00:00` and
    // expected hour 10 as local, i.e. it pinned the bug just fixed.)
    //
    // The two successful prints are deliberately near UTC noon: at every real
    // offset (−12…+14) they land on the same local day, so the "busiest day"
    // assertion doesn't fall apart at an extreme timezone.
    final noon = DateTime.utc(2026, 6, 1, 12);
    final afterNoon = DateTime.utc(2026, 6, 1, 13);
    final failedAt = DateTime.utc(2026, 6, 2, 21);

    DateTime localDay(DateTime utc) {
      final l = utc.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    final items = [
      _a(
        status: 'completed',
        createdAt: noon.toIso8601String(),
        seconds: 1000,
        grams: 50,
        material: 'PLA',
        color: '#FF0000',
        cost: 1.5,
        printerId: 1,
      ),
      _a(
        status: 'completed',
        createdAt: afterNoon.toIso8601String(),
        seconds: 5000,
        grams: 120,
        material: 'PETG',
        color: '#00FF00',
        cost: 4.0,
        printerId: 1,
      ),
      _a(
        status: 'failed',
        createdAt: failedAt.toIso8601String(),
        seconds: 90000,
        grams: 300,
        material: 'PLA',
        color: '#FF0000',
        cost: 9.0,
        printerId: 2,
      ),
    ];
    final c = StatsComputed.from(items);

    test('counts prints per day and points at the busiest day', () {
      expect(c.printsByDay[localDay(noon)], 2);
      expect(c.printsByDay[localDay(failedAt)], 1);
      expect(c.busiestDay, localDay(noon));
      expect(c.busiestDayCount, 2);
    });

    test('records: longest / heaviest / most expensive', () {
      expect(c.longest!.effectiveSeconds, 90000);
      expect(c.heaviest!.filamentUsedGrams, 300);
      expect(c.mostExpensive!.cost, 9.0);
    });

    test('success streak counted chronologically', () {
      // 2 successes (June 1) → streak 2, then a failure resets it.
      expect(c.bestSuccessStreak, 2);
    });

    test('duration histogram lands in the right buckets', () {
      // 1000s (<30m) → 0, 5000s (1-2h) → 2, 90000s (24h+) → 7.
      expect(c.durationBuckets[0], 1);
      expect(c.durationBuckets[2], 1);
      expect(c.durationBuckets[durationBucketCount - 1], 1);
    });

    test('breakdown by material: weights and success rate', () {
      expect(c.byMaterial['PLA']!.grams, 350);
      expect(c.byMaterial['PLA']!.prints, 2);
      expect(c.byMaterial['PLA']!.successRate, 50);
      expect(c.byMaterial['PETG']!.successRate, 100);
    });

    test('colors and printers aggregated', () {
      expect(c.gramsByColor['#FF0000'], 350);
      expect(c.printsByColor['#FF0000'], 2);
      expect(c.byPrinter[1]!.prints, 2);
      expect(c.byPrinter[2]!.prints, 1);
    });

    test('hours of day counted in local time, not UTC', () {
      // This is the fix: the "what time do you print" chart should show the
      // hour the user stood at the printer. It used to bucket by UTC, so on
      // any device with a nonzero offset it was shifted.
      expect(c.byHour[noon.toLocal().hour], 1);
      expect(c.byHour[afterNoon.toLocal().hour], 1);
      expect(c.byHour[failedAt.toLocal().hour], 1);
      expect(c.failedByHour[failedAt.toLocal().hour], 1);
    });
  });

  group('Energy per print (server >= 1.2.5.2)', () {
    test('without an energy field the section does not turn on', () {
      // An old server doesn't send energy_kwh — the chart must disappear, not
      // draw a flat zero, which reads like "you used nothing".
      final c = StatsComputed.from([
        _a(status: 'completed', createdAt: '2026-06-01T10:00:00Z', grams: 20),
      ]);
      expect(c.hasEnergyData, isFalse);
      expect(c.energyOverTime, isEmpty);
      expect(c.hungriest, isNull);
    });

    test('sums kWh by day and points at the most power-hungry print', () {
      final c = StatsComputed.from([
        _a(
          status: 'completed',
          createdAt: '2026-06-01T10:00:00Z',
          energyKwh: 0.4,
        ),
        _a(
          status: 'completed',
          createdAt: '2026-06-01T20:00:00Z',
          energyKwh: 1.1,
        ),
        _a(status: 'failed', createdAt: '2026-06-02T09:00:00Z', energyKwh: 0.3),
      ]);
      expect(c.hasEnergyData, isTrue);
      expect(c.energyOverTime, hasLength(2));
      expect(c.energyOverTime.first.value, closeTo(1.5, 1e-9));
      expect(c.hungriest!.energyKwh, 1.1);
    });

    test('prints with no reading do not deflate buckets or the record', () {
      // Energy can be null even on a new server — for runs from before
      // tracking was turned on. Those must be skipped, not counted as 0.
      final c = StatsComputed.from([
        _a(
          status: 'completed',
          createdAt: '2026-06-01T10:00:00Z',
          energyKwh: 0.8,
        ),
        _a(status: 'completed', createdAt: '2026-06-03T10:00:00Z'),
      ]);
      expect(c.energyOverTime, hasLength(1));
      expect(c.hungriest!.energyKwh, 0.8);
    });

    test('a printer bucket sums energy and its cost', () {
      final c = StatsComputed.from([
        _a(
          status: 'completed',
          createdAt: '2026-06-01T10:00:00Z',
          printerId: 1,
          energyKwh: 0.5,
          energyCost: 0.25,
        ),
        _a(
          status: 'completed',
          createdAt: '2026-06-02T10:00:00Z',
          printerId: 1,
          energyKwh: 0.5,
          energyCost: 0.25,
        ),
      ]);
      expect(c.byPrinter[1]!.energyKwh, closeTo(1.0, 1e-9));
      expect(c.byPrinter[1]!.energyCost, closeTo(0.5, 1e-9));
    });
  });
}
