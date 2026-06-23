/// Analiza niepowodzeń z `GET /archives/analysis/failures`.
///
/// Endpoint nie ma zadeklarowanego schematu w OpenAPI — kształt ustalony z
/// żywej odpowiedzi. Parsowanie defensywne; nieznane pola ignorowane.
class FailureAnalysis {
  const FailureAnalysis({
    this.periodDays = 0,
    this.totalPrints = 0,
    this.failedPrints = 0,
    this.failureRate = 0,
    this.failuresByReason = const {},
    this.failuresByFilament = const {},
    this.failuresByPrinter = const {},
    this.failuresByHour = const {},
  });

  factory FailureAnalysis.fromJson(Map<String, dynamic> json) => FailureAnalysis(
        periodDays: _int(json['period_days']),
        totalPrints: _int(json['total_prints']),
        failedPrints: _int(json['failed_prints']),
        failureRate: _double(json['failure_rate']),
        failuresByReason: _intMap(json['failures_by_reason']),
        failuresByFilament: _intMap(json['failures_by_filament']),
        failuresByPrinter: _intMap(json['failures_by_printer']),
        failuresByHour: _intMap(json['failures_by_hour']),
      );

  final int periodDays;
  final int totalPrints;
  final int failedPrints;

  /// Odsetek niepowodzeń w procentach (np. 4.5).
  final double failureRate;

  /// Liczba porażek per powód (np. `{Unknown: 3}`).
  final Map<String, int> failuresByReason;
  final Map<String, int> failuresByFilament;
  final Map<String, int> failuresByPrinter;

  /// Liczba porażek per godzina doby (klucz „0".."23").
  final Map<String, int> failuresByHour;

  bool get isEmpty => failedPrints == 0 && totalPrints == 0;

  /// Serializacja do cache — klucze zgodne z [fromJson], więc round-trip.
  Map<String, dynamic> toJson() => {
        'period_days': periodDays,
        'total_prints': totalPrints,
        'failed_prints': failedPrints,
        'failure_rate': failureRate,
        'failures_by_reason': failuresByReason,
        'failures_by_filament': failuresByFilament,
        'failures_by_printer': failuresByPrinter,
        'failures_by_hour': failuresByHour,
      };

  /// Scala dwa rozłączne (czasowo) agregaty w jeden. Liczniki są addytywne
  /// (archiwum jest append-only, okresy nie nachodzą na siebie); `failureRate`
  /// przeliczamy z sum, bo średnia z procentów byłaby błędna. Używane przy
  /// przyrostowym dociąganiu („cache + nowy okres") dla zakresu „cały okres".
  FailureAnalysis merge(FailureAnalysis other) {
    final total = totalPrints + other.totalPrints;
    final failed = failedPrints + other.failedPrints;
    return FailureAnalysis(
      // Nieużywane w UI; suma to najmniej mylące przybliżenie łącznego okresu.
      periodDays: periodDays + other.periodDays,
      totalPrints: total,
      failedPrints: failed,
      failureRate: total == 0 ? 0 : failed * 100 / total,
      failuresByReason: _mergeCounts(failuresByReason, other.failuresByReason),
      failuresByFilament:
          _mergeCounts(failuresByFilament, other.failuresByFilament),
      failuresByPrinter:
          _mergeCounts(failuresByPrinter, other.failuresByPrinter),
      failuresByHour: _mergeCounts(failuresByHour, other.failuresByHour),
    );
  }
}

Map<String, int> _mergeCounts(Map<String, int> a, Map<String, int> b) {
  final out = Map<String, int>.from(a);
  b.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
  return out;
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
