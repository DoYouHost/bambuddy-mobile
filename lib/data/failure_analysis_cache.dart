import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/failure_analysis.dart';
import '../features/stats/stats_providers.dart';

/// Wpis cache analizy niepowodzeń: zbankowany agregat plus dokąd sięga.
///
/// [coveredThrough] to ostatni PEŁNY dzień objęty [analysis] (dla zakresu
/// „cały okres" — przyrostowe doklejanie). `null` dla pozostałych zakresów,
/// gdzie cache trzyma po prostu ostatni pełny wynik (stale-while-revalidate).
class FailureCacheEntry {
  const FailureCacheEntry({
    required this.analysis,
    required this.coveredThrough,
    required this.fetchedAt,
  });

  final FailureAnalysis analysis;
  final DateTime? coveredThrough;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'analysis': analysis.toJson(),
        'covered_through': coveredThrough == null
            ? null
            : _ymd(coveredThrough!),
        'fetched_at': fetchedAt.toIso8601String(),
      };

  static FailureCacheEntry? fromJson(Map<String, dynamic> json) {
    final a = json['analysis'];
    if (a is! Map<String, dynamic>) return null;
    return FailureCacheEntry(
      analysis: FailureAnalysis.fromJson(a),
      coveredThrough: _parseDate(json['covered_through']),
      fetchedAt: DateTime.tryParse('${json['fetched_at']}') ?? DateTime(2000),
    );
  }
}

/// Trwały cache analizy niepowodzeń (SharedPreferences), kluczowany sygnaturą
/// filtra. Pozwala pokazać dane natychmiast po wejściu na ekran i dociągnąć
/// tylko brakujący okres w tle. Mały JSON na wpis — agregaty, nie surowe wpisy.
class FailureAnalysisCache {
  FailureAnalysisCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'failure_analysis_cache_';

  /// Sygnatura filtra → klucz cache. Zakresy względne kluczujemy po nazwie
  /// (resolved daty zmieniają się co dzień, ale stale-while-revalidate i tak
  /// dociąga świeże); „własny" — po jawnych datach.
  static String signature(StatsFilter f) => switch (f.range) {
        StatsRange.custom => 'custom_${_ymd(f.from)}_${_ymd(f.to)}',
        _ => f.range.name,
      };

  FailureCacheEntry? load(StatsFilter filter) {
    final raw = _prefs.getString('$_prefix${signature(filter)}');
    if (raw == null) return null;
    try {
      return FailureCacheEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null; // uszkodzony wpis → traktuj jak brak
    }
  }

  Future<void> save(StatsFilter filter, FailureCacheEntry entry) =>
      _prefs.setString(
        '$_prefix${signature(filter)}',
        jsonEncode(entry.toJson()),
      );
}

String? _ymd(DateTime? d) {
  if (d == null) return null;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

DateTime? _parseDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}
