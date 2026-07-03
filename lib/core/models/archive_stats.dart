import 'json_utils.dart';

/// Archive statistics from `GET /archives/stats` (aggregate of `PrintLogEntry` —
/// one row per print event, reprint adds new entry, #1378).
///
/// Manual and defensive parsing: API is young, so each field has sensible
/// defaults and unknown keys ignored. Numeric values accepted as both `int`
/// and `double` (server inconsistency).
class ArchiveStats {
  const ArchiveStats({
    this.totalPrints = 0,
    this.successfulPrints = 0,
    this.failedPrints = 0,
    this.totalPrintTimeHours = 0,
    this.totalFilamentGrams = 0,
    this.totalCost = 0,
    this.printsByFilamentType = const {},
    this.printsByPrinter = const {},
    this.averageTimeAccuracy = 0,
    this.timeAccuracyByPrinter = const {},
    this.totalEnergyKwh = 0,
    this.totalEnergyCost = 0,
    this.energyDataWarmingUp = false,
  });

  factory ArchiveStats.fromJson(Map<String, dynamic> json) => ArchiveStats(
        totalPrints: toInt(json['total_prints']),
        successfulPrints: toInt(json['successful_prints']),
        failedPrints: toInt(json['failed_prints']),
        totalPrintTimeHours: toDouble(json['total_print_time_hours']),
        totalFilamentGrams: toDouble(json['total_filament_grams']),
        totalCost: toDouble(json['total_cost']),
        printsByFilamentType: toIntMap(json['prints_by_filament_type']),
        printsByPrinter: toIntMap(json['prints_by_printer']),
        averageTimeAccuracy: toDouble(json['average_time_accuracy']),
        timeAccuracyByPrinter: toDoubleMap(json['time_accuracy_by_printer']),
        totalEnergyKwh: toDouble(json['total_energy_kwh']),
        totalEnergyCost: toDouble(json['total_energy_cost']),
        energyDataWarmingUp: json['energy_data_warming_up'] == true,
      );

  /// Total print count in the period.
  final int totalPrints;

  /// Successful prints.
  final int successfulPrints;

  /// Failed prints.
  final int failedPrints;

  /// Total print time in hours.
  final double totalPrintTimeHours;

  /// Total filament used in grams.
  final double totalFilamentGrams;

  /// Total filament cost (server currency).
  final double totalCost;

  /// Print count per filament type (e.g. `{PETG: 68, PLA: 32}`).
  final Map<String, int> printsByFilamentType;

  /// Print count per printer (key = `printer_id` as string).
  final Map<String, int> printsByPrinter;

  /// Average time estimate accuracy in percent (100% = perfect).
  final double averageTimeAccuracy;

  /// Time accuracy per printer (key = `printer_id` as string).
  final Map<String, double> timeAccuracyByPrinter;

  /// Total energy in kWh.
  final double totalEnergyKwh;

  /// Total energy cost.
  final double totalEnergyCost;

  /// Energy data still "warming up" (server still collecting measurements) —
  /// UI can mark energy as incomplete.
  final bool energyDataWarmingUp;

  /// Success rate percent (0–100). Based on successful vs failed;
  /// in-progress/cancelled don't count in denominator.
  double get successRate {
    final decided = successfulPrints + failedPrints;
    if (decided <= 0) return 0;
    return successfulPrints / decided * 100;
  }

  /// Whether there is anything to display (empty period → empty cards).
  bool get isEmpty => totalPrints == 0;
}

