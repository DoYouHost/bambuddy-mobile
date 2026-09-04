import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/failure_analysis.dart';
import '../core/models/json_utils.dart';
import '../features/stats/stats_providers.dart';

/// Failure analysis cache entry: an aggregate plus the extent of coverage.
///
/// [coveredThrough] is the last complete day covered by [analysis] (for the
/// "all time" range — allows incremental appending). `null` for other ranges,
/// where cache stores the last full result (stale-while-revalidate strategy).
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

/// Persistent failure analysis cache (SharedPreferences), keyed by filter signature.
/// Allows instant data display on screen entry and fetches only missing periods in the
/// background. Small JSON per entry — aggregates, not raw records.
class FailureAnalysisCache {
  FailureAnalysisCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'failure_analysis_cache_';

  /// Filter signature → cache key. Relative ranges keyed by name (resolved dates
  /// change daily, but stale-while-revalidate fetches fresh anyway); custom range
  /// keyed by explicit dates. [StatsFilter.createdById] is included so switching
  /// the user filter doesn't merge one user's banked "all time" aggregate with
  /// another's — each (range, user) pair gets its own bucket.
  static String signature(StatsFilter f) {
    final range = switch (f.range) {
      StatsRange.custom => 'custom_${_ymd(f.from)}_${_ymd(f.to)}',
      _ => f.range.name,
    };
    return '${range}_u${f.createdById ?? 'all'}';
  }

  FailureCacheEntry? load(StatsFilter filter) {
    final raw = _prefs.getString('$_prefix${signature(filter)}');
    if (raw == null) return null;
    try {
      return FailureCacheEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<void> save(StatsFilter filter, FailureCacheEntry entry) =>
      _prefs.setString(
        '$_prefix${signature(filter)}',
        jsonEncode(entry.toJson()),
      );

  /// Drop every bucket, for when a run's classification changed underneath
  /// them (the print-log editor).
  ///
  /// Deliberately not narrowed to one filter: the edited run belongs to some
  /// range and some user, and this side cannot tell which. The "all time"
  /// bucket is the load-bearing case — it banks complete days and only ever
  /// appends, so it can never notice a value that changed behind it.
  Future<void> clear() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

String? _ymd(DateTime? d) => d == null ? null : calendarDateToJson(d);

DateTime? _parseDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}
