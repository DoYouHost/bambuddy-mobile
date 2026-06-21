/// Statystyki archiwum z `GET /archives/stats` (agregat po `PrintLogEntry` —
/// jeden wiersz na zdarzenie wydruku, reprint dokłada nowy wpis, #1378).
///
/// Parsowanie ręczne i defensywne: API bambuddy jest młode, więc każde pole ma
/// rozsądny default, a nieznane klucze są ignorowane. Wartości liczbowe
/// przyjmujemy zarówno jako `int`, jak i `double` (serwer bywa niespójny).
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
        totalPrints: _int(json['total_prints']),
        successfulPrints: _int(json['successful_prints']),
        failedPrints: _int(json['failed_prints']),
        totalPrintTimeHours: _double(json['total_print_time_hours']),
        totalFilamentGrams: _double(json['total_filament_grams']),
        totalCost: _double(json['total_cost']),
        printsByFilamentType: _intMap(json['prints_by_filament_type']),
        printsByPrinter: _intMap(json['prints_by_printer']),
        averageTimeAccuracy: _double(json['average_time_accuracy']),
        timeAccuracyByPrinter: _doubleMap(json['time_accuracy_by_printer']),
        totalEnergyKwh: _double(json['total_energy_kwh']),
        totalEnergyCost: _double(json['total_energy_cost']),
        energyDataWarmingUp: json['energy_data_warming_up'] == true,
      );

  /// Łączna liczba wydruków (zdarzeń) w okresie.
  final int totalPrints;

  /// Wydruki zakończone sukcesem.
  final int successfulPrints;

  /// Wydruki zakończone niepowodzeniem.
  final int failedPrints;

  /// Łączny czas druku w godzinach.
  final double totalPrintTimeHours;

  /// Łączne zużycie filamentu w gramach.
  final double totalFilamentGrams;

  /// Łączny koszt filamentu (w walucie serwera).
  final double totalCost;

  /// Liczba wydruków per typ filamentu (np. `{PETG: 68, PLA: 32}`).
  final Map<String, int> printsByFilamentType;

  /// Liczba wydruków per drukarka (klucz = `printer_id` jako string).
  final Map<String, int> printsByPrinter;

  /// Średnia dokładność szacowania czasu w procentach (100% = idealny estymat).
  final double averageTimeAccuracy;

  /// Dokładność czasu per drukarka (klucz = `printer_id` jako string).
  final Map<String, double> timeAccuracyByPrinter;

  /// Łączna energia w kWh.
  final double totalEnergyKwh;

  /// Łączny koszt energii.
  final double totalEnergyCost;

  /// Dane energii jeszcze się „rozgrzewają" (serwer dopiero zbiera pomiary) —
  /// UI może wtedy oznaczyć energię jako niepełną.
  final bool energyDataWarmingUp;

  /// Procent skuteczności (0–100). Bazujemy na sukcesach względem ich sumy
  /// z porażkami — wydruki w toku/anulowane nie liczą się do mianownika.
  double get successRate {
    final decided = successfulPrints + failedPrints;
    if (decided <= 0) return 0;
    return successfulPrints / decided * 100;
  }

  /// Czy w ogóle mamy co pokazać (pusty okres → puste karty).
  bool get isEmpty => totalPrints == 0;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

Map<String, int> _intMap(Object? v) {
  if (v is! Map) return const {};
  final out = <String, int>{};
  v.forEach((key, value) => out['$key'] = _int(value));
  return out;
}

Map<String, double> _doubleMap(Object? v) {
  if (v is! Map) return const {};
  final out = <String, double>{};
  v.forEach((key, value) => out['$key'] = _double(value));
  return out;
}
