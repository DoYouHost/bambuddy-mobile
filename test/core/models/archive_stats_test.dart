import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchiveStats.fromJson', () {
    test('parsuje pełną odpowiedź /archives/stats', () {
      final stats = ArchiveStats.fromJson(const {
        'total_prints': 83,
        'successful_prints': 77,
        'failed_prints': 3,
        'cancelled_prints': 3,
        'total_print_time_hours': 175.6,
        'total_filament_grams': 6560.5,
        'total_cost': 194.73,
        'prints_by_filament_type': {'PETG': 68, 'PLA': 32, 'TPU': 4},
        'prints_by_printer': {'1': 83},
        'average_time_accuracy': 92.3,
        'time_accuracy_by_printer': {'1': 92.3},
        'total_energy_kwh': 133.47,
        'total_energy_cost': 133.47,
        'energy_data_warming_up': false,
      });

      expect(stats.totalPrints, 83);
      expect(stats.successfulPrints, 77);
      expect(stats.failedPrints, 3);
      expect(stats.cancelledPrints, 3);
      expect(stats.totalPrintTimeHours, 175.6);
      expect(stats.totalFilamentGrams, 6560.5);
      expect(stats.totalCost, 194.73);
      expect(stats.printsByFilamentType['PETG'], 68);
      expect(stats.printsByPrinter['1'], 83);
      expect(stats.averageTimeAccuracy, 92.3);
      expect(stats.timeAccuracyByPrinter['1'], 92.3);
      expect(stats.totalEnergyKwh, 133.47);
      expect(stats.energyDataWarmingUp, isFalse);
      expect(stats.isEmpty, isFalse);
    });

    test('successRate liczony z sukcesów względem rozstrzygniętych', () {
      final stats = ArchiveStats.fromJson(const {
        'successful_prints': 77,
        'failed_prints': 3,
      });
      // 77 / (77 + 3) = 96.25% — wydruki w toku nie wchodzą do mianownika.
      expect(stats.successRate, closeTo(96.25, 0.001));
    });

    test('anulowane wydruki nie wchodzą do mianownika successRate', () {
      final stats = ArchiveStats.fromJson(const {
        'successful_prints': 77,
        'failed_prints': 3,
        'cancelled_prints': 20,
      });
      expect(stats.cancelledPrints, 20);
      // Ten sam wynik co bez anulowanych — mianownik to tylko sukces+porażka.
      expect(stats.successRate, closeTo(96.25, 0.001));
    });

    test('puste / brakujące pola → bezpieczne defaulty', () {
      final stats = ArchiveStats.fromJson(const {});
      expect(stats.totalPrints, 0);
      expect(stats.cancelledPrints, 0);
      expect(stats.successRate, 0);
      expect(stats.isEmpty, isTrue);
      expect(stats.printsByFilamentType, isEmpty);
    });

    test('toleruje liczby jako string oraz int w miejsce double', () {
      final stats = ArchiveStats.fromJson(const {
        'total_prints': '12',
        'total_cost': 10,
        'average_time_accuracy': '88.5',
      });
      expect(stats.totalPrints, 12);
      expect(stats.totalCost, 10.0);
      expect(stats.averageTimeAccuracy, 88.5);
    });
  });
}
