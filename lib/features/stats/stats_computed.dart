import '../../core/models/archive_slim.dart';

/// Metric accumulator per key (material / printer / weekday).
class StatBucket {
  int prints = 0;
  double grams = 0;
  int seconds = 0;
  int successes = 0;

  void add(ArchiveSlim a) {
    prints += 1;
    grams += a.filamentUsedGrams ?? 0;
    seconds += a.effectiveSeconds ?? 0;
    if (a.isSuccess) successes += 1;
  }

  double get successRate => prints == 0 ? 0 : successes / prints * 100;
}

/// Duration histogram thresholds (upper bound in seconds; last = ∞).
const durationBucketBounds = <int>[
  1800, // <30 min
  3600, // 30 min–1 h
  7200, // 1–2 h
  14400, // 2–4 h
  28800, // 4–8 h
  43200, // 8–12 h
  86400, // 12–24 h
];

/// Duration bucket count (bounds + one "24h+").
const durationBucketCount = 8; // durationBucketBounds.length + 1

/// Rich statistics computed in one pass over slim print list (`/archives/slim`).
/// All aggregates not provided by `/archives/stats`.
class StatsComputed {
  StatsComputed._();

  /// Counts by calendar day (key = midnight local) — heatmap, busiest day,
  /// usage over time.
  final Map<DateTime, int> printsByDay = {};
  final Map<DateTime, double> gramsByDay = {};

  /// Duration histogram (length [durationBucketCount]).
  final List<int> durationBuckets = List.filled(durationBucketCount, 0);

  /// By weekday (index 0 = Mon … 6 = Sun).
  final List<StatBucket> byWeekday = List.generate(7, (_) => StatBucket());

  /// By hour of day (0–23): total count and failures.
  final List<int> byHour = List.filled(24, 0);
  final List<int> failedByHour = List.filled(24, 0);

  /// By material, printer, dominant color.
  final Map<String, StatBucket> byMaterial = {};
  final Map<int, StatBucket> byPrinter = {};
  final Map<String, double> gramsByColor = {};
  final Map<String, int> printsByColor = {};

  // Rekordy.
  ArchiveSlim? longest;
  ArchiveSlim? heaviest;
  ArchiveSlim? mostExpensive;
  DateTime? busiestDay;
  int busiestDayCount = 0;
  int bestSuccessStreak = 0;

  factory StatsComputed.from(List<ArchiveSlim> items) {
    final c = StatsComputed._();

    // Success streak counted in chronological order (oldest → newest) so "streak"
    // matches event order.
    final chronological = [...items]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var streak = 0;
    for (final a in chronological) {
      if (a.isSuccess) {
        streak += 1;
        if (streak > c.bestSuccessStreak) c.bestSuccessStreak = streak;
      } else {
        streak = 0;
      }
    }

    for (final a in items) {
      final day = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
      c.printsByDay[day] = (c.printsByDay[day] ?? 0) + 1;
      c.gramsByDay[day] = (c.gramsByDay[day] ?? 0) + (a.filamentUsedGrams ?? 0);

      final count = c.printsByDay[day]!;
      if (count > c.busiestDayCount) {
        c.busiestDayCount = count;
        c.busiestDay = day;
      }

      // Weekday: Dart `weekday` 1=Mon … 7=Sun → index 0..6.
      c.byWeekday[a.createdAt.weekday - 1].add(a);

      final hour = a.createdAt.hour;
      c.byHour[hour] += 1;
      if (!a.isSuccess) c.failedByHour[hour] += 1;

      final secs = a.effectiveSeconds;
      if (secs != null && secs > 0) {
        c.durationBuckets[_durationBucket(secs)] += 1;
      }

      final mat = a.filamentType;
      if (mat != null && mat.isNotEmpty) {
        (c.byMaterial[mat] ??= StatBucket()).add(a);
      }
      final pid = a.printerId;
      if (pid != null) {
        (c.byPrinter[pid] ??= StatBucket()).add(a);
      }
      final color = a.primaryColor;
      if (color != null) {
        c.gramsByColor[color] =
            (c.gramsByColor[color] ?? 0) + (a.filamentUsedGrams ?? 0);
        c.printsByColor[color] = (c.printsByColor[color] ?? 0) + 1;
      }

      // Records.
      if (secs != null &&
          (c.longest == null || secs > (c.longest!.effectiveSeconds ?? 0))) {
        c.longest = a;
      }
      final g = a.filamentUsedGrams;
      if (g != null &&
          (c.heaviest == null || g > (c.heaviest!.filamentUsedGrams ?? 0))) {
        c.heaviest = a;
      }
      final cost = a.cost;
      if (cost != null &&
          (c.mostExpensive == null ||
              cost > (c.mostExpensive!.cost ?? 0))) {
        c.mostExpensive = a;
      }
    }
    return c;
  }

  bool get isEmpty => printsByDay.isEmpty;

  /// Usage points in grams per day, sorted ascending by date — for
  /// "Usage Over Time" line chart.
  List<MapEntry<DateTime, double>> get usageOverTime {
    final list = gramsByDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return list;
  }
}

int _durationBucket(int seconds) {
  for (var i = 0; i < durationBucketBounds.length; i++) {
    if (seconds < durationBucketBounds[i]) return i;
  }
  return durationBucketBounds.length; // 24h+
}
