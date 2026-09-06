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
    test('primaryColor bierze pierwszy segment i normalizuje do #RRGGBB', () {
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

    test('isSuccess true tylko dla completed', () {
      expect(
        _a(status: 'completed', createdAt: '2026-06-01').isSuccess,
        isTrue,
      );
      expect(_a(status: 'failed', createdAt: '2026-06-01').isSuccess, isFalse);
    });
  });

  group('StatsComputed.from', () {
    // Serwer stempluje UTC i część schematów nie dokleja `Z` (patrz
    // [dateTimeFromJson]), a statystyki kubełkują po czasie **lokalnym**: „o
    // której drukujesz" ma sens tylko w strefie użytkownika. Instanty trzymamy
    // więc jawnie w UTC, a oczekiwania wyliczamy z tych samych instantów —
    // inaczej test przechodziłby wyłącznie w strefie, w której go napisano.
    // (Poprzednia wersja podawała `2026-06-01T10:00:00` i oczekiwała godziny 10
    // jako lokalnej, czyli pinowała naprawiony właśnie błąd.)
    //
    // Dwa udane wydruki są blisko południa UTC celowo: przy każdym realnym
    // offsecie (−12…+14) lądują tego samego dnia lokalnego, więc asercja o
    // „najbusy dniu" nie rozpada się w skrajnej strefie.
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

    test('zlicza wydruki per dzień i wskazuje najbusy dzień', () {
      expect(c.printsByDay[localDay(noon)], 2);
      expect(c.printsByDay[localDay(failedAt)], 1);
      expect(c.busiestDay, localDay(noon));
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

    test('godziny doby liczone w czasie lokalnym, nie UTC', () {
      // To jest ta poprawka: wykres „o której drukujesz" ma pokazywać godzinę,
      // o której user stał przy drukarce. Wcześniej kubełkował po UTC, więc na
      // każdym urządzeniu z niezerowym offsetem był przesunięty.
      expect(c.byHour[noon.toLocal().hour], 1);
      expect(c.byHour[afterNoon.toLocal().hour], 1);
      expect(c.byHour[failedAt.toLocal().hour], 1);
      expect(c.failedByHour[failedAt.toLocal().hour], 1);
    });
  });

  group('Energia per wydruk (serwer >= 1.2.5.2)', () {
    test('bez pola energii sekcja się nie włącza', () {
      // Stary serwer nie wysyła energy_kwh — wykres ma zniknąć, a nie
      // narysować płaskie zero, które czyta się jak "nic nie zużyłeś".
      final c = StatsComputed.from([
        _a(status: 'completed', createdAt: '2026-06-01T10:00:00Z', grams: 20),
      ]);
      expect(c.hasEnergyData, isFalse);
      expect(c.energyOverTime, isEmpty);
      expect(c.hungriest, isNull);
    });

    test('sumuje kWh po dniach i wskazuje najbardziej prądożerny wydruk', () {
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

    test('wydruki bez odczytu nie zaniżają kubełków ani rekordu', () {
      // Energia bywa null także na nowym serwerze — dla przebiegów sprzed
      // włączenia śledzenia. Takie mają być pominięte, nie liczone jako 0.
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

    test('kubełek drukarki sumuje energię i jej koszt', () {
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
