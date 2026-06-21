import '../../core/models/archive_slim.dart';

/// Akumulator metryk per klucz (materiał / drukarka / dzień tygodnia).
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

/// Próg histogramu czasu trwania (górna granica w sekundach; ostatni = ∞).
const durationBucketBounds = <int>[
  1800, // <30 min
  3600, // 30 min–1 h
  7200, // 1–2 h
  14400, // 2–4 h
  28800, // 4–8 h
  43200, // 8–12 h
  86400, // 12–24 h
];

/// Liczba kubełków czasu trwania (granice + jeden „24h+").
const durationBucketCount = 8; // durationBucketBounds.length + 1

/// Bogate statystyki policzone jednym przejściem po lekkiej liście wydruków
/// (`/archives/slim`). Wszystkie agregaty, których nie daje `/archives/stats`.
class StatsComputed {
  StatsComputed._();

  /// Zliczenia wg dnia kalendarzowego (klucz = północ lokalna) — heatmapa,
  /// najbusy dzień, zużycie w czasie.
  final Map<DateTime, int> printsByDay = {};
  final Map<DateTime, double> gramsByDay = {};

  /// Histogram czasu trwania (długość [durationBucketCount]).
  final List<int> durationBuckets = List.filled(durationBucketCount, 0);

  /// Wg dnia tygodnia (indeks 0 = poniedziałek … 6 = niedziela).
  final List<StatBucket> byWeekday = List.generate(7, (_) => StatBucket());

  /// Wg godziny doby (0–23): łączna liczba i porażki.
  final List<int> byHour = List.filled(24, 0);
  final List<int> failedByHour = List.filled(24, 0);

  /// Wg materiału, drukarki, koloru (dominującego).
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

    // Strumień sukcesów liczymy w porządku chronologicznym (najstarsze →
    // najnowsze), żeby „seria" odpowiadała kolejności zdarzeń.
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

      // Dzień tygodnia: Dart `weekday` 1=pon … 7=niedz → indeks 0..6.
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

      // Rekordy.
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

  /// Punkty zużycia w gramach per dzień, posortowane rosnąco po dacie — do
  /// wykresu liniowego „Usage Over Time".
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
