import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive_slim.dart';
import '../../core/models/archive_stats.dart';
import '../../core/models/failure_analysis.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'stats_computed.dart';

/// Etykieta aktywnego zakresu czasu — wspólna dla AppBaru i podpisów widżetów.
String statsRangeLabel(AppLocalizations l10n, StatsRange range) =>
    switch (range) {
      StatsRange.allTime => l10n.statsRangeAllTime,
      StatsRange.last7Days => l10n.statsRangeLast7Days,
      StatsRange.last30Days => l10n.statsRangeLast30Days,
      StatsRange.last90Days => l10n.statsRangeLast90Days,
      StatsRange.thisYear => l10n.statsRangeThisYear,
      StatsRange.custom => l10n.statsRangeCustom,
    };

/// Predefiniowane zakresy czasu dla statystyk (odpowiednik dropdownu „All Time"
/// w wersji web). [custom] używa jawnych [StatsFilter.from]/[StatsFilter.to].
enum StatsRange { allTime, last7Days, last30Days, last90Days, thisYear, custom }

/// Filtr statystyk: zakres czasu (+ ewentualne jawne daty dla [StatsRange.custom]).
@immutable
class StatsFilter {
  const StatsFilter({this.range = StatsRange.allTime, this.from, this.to});

  final StatsRange range;
  final DateTime? from;
  final DateTime? to;

  StatsFilter copyWith({StatsRange? range, DateTime? from, DateTime? to}) =>
      StatsFilter(
        range: range ?? this.range,
        from: from ?? this.from,
        to: to ?? this.to,
      );

  @override
  bool operator ==(Object other) =>
      other is StatsFilter &&
      other.range == range &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(range, from, to);
}

/// Aktywny filtr statystyk. Zmiana wartości przeładowuje [statsProvider].
final statsFilterProvider =
    NotifierProvider<StatsFilterNotifier, StatsFilter>(StatsFilterNotifier.new);

class StatsFilterNotifier extends Notifier<StatsFilter> {
  @override
  StatsFilter build() => const StatsFilter();

  void setRange(StatsRange range) {
    if (range == StatsRange.custom) return; // custom ustawia setCustom
    state = StatsFilter(range: range);
  }

  void setCustom(DateTime from, DateTime to) {
    state = StatsFilter(range: StatsRange.custom, from: from, to: to);
  }
}

/// Pobrane statystyki dla aktywnego [statsFilterProvider]. Liczymy daty
/// `from`/`to` z wybranego zakresu i delegujemy do repozytorium. Daty względne
/// kotwiczymy do [now] obliczanego raz na build (nie trzymamy zegara w stanie).
final statsProvider =
    AutoDisposeAsyncNotifierProvider<StatsNotifier, ArchiveStats>(
  StatsNotifier.new,
);

class StatsNotifier extends AutoDisposeAsyncNotifier<ArchiveStats> {
  @override
  Future<ArchiveStats> build() async {
    ref.watch(serverProfileProvider);
    final filter = ref.watch(statsFilterProvider);
    final (from, to) = _resolveDates(filter);
    return ref.read(statsRepositoryProvider).fetch(from: from, to: to);
  }

  /// Pull-to-refresh: ponów pobranie dla bieżącego filtra.
  Future<void> refresh() async {
    state = const AsyncValue<ArchiveStats>.loading().copyWithPrevious(state);
    final filter = ref.read(statsFilterProvider);
    final (from, to) = _resolveDates(filter);
    state = await AsyncValue.guard(
      () => ref.read(statsRepositoryProvider).fetch(from: from, to: to),
    );
  }

  /// Zamienia [StatsRange] na konkretne `from`/`to`. `allTime` → oba `null`
  /// (serwer zwraca całość). Zakresy względne liczymy wstecz od dziś.
  static (DateTime?, DateTime?) _resolveDates(StatsFilter f) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (f.range) {
      StatsRange.allTime => (null, null),
      StatsRange.last7Days => (today.subtract(const Duration(days: 6)), today),
      StatsRange.last30Days => (today.subtract(const Duration(days: 29)), today),
      StatsRange.last90Days => (today.subtract(const Duration(days: 89)), today),
      StatsRange.thisYear => (DateTime(now.year), today),
      StatsRange.custom => (f.from, f.to),
    };
  }
}

/// Mapa `printer_id → nazwa` do podpisania rozbicia „po drukarce". Tylko
/// konfiguracja (bez statusów) — tania. Brak wpisu → UI pokaże `#id`.
final printerNamesProvider = FutureProvider.autoDispose<Map<int, String>>(
  (ref) async {
    final printers = await ref.watch(printersRepositoryProvider).fetchPrinters();
    return {for (final p in printers) p.id: p.name};
  },
);

/// Lekka lista wszystkich wydruków dla aktywnego filtra — źródło bogatych
/// statystyk (heatmapa, rekordy, kolory, zużycie w czasie, histogramy).
final archiveSlimProvider =
    FutureProvider.autoDispose<List<ArchiveSlim>>((ref) async {
  ref.watch(serverProfileProvider);
  final filter = ref.watch(statsFilterProvider);
  final (from, to) = StatsNotifier._resolveDates(filter);
  return ref.read(statsRepositoryProvider).fetchSlim(from: from, to: to);
});

/// Policzone agregaty z lekkiej listy (czyste przeliczenie, bez I/O).
final statsComputedProvider =
    Provider.autoDispose<AsyncValue<StatsComputed>>((ref) {
  return ref
      .watch(archiveSlimProvider)
      .whenData((items) => StatsComputed.from(items));
});

/// Analiza niepowodzeń dla aktywnego filtra. Dla „całego okresu" zamiast braku
/// dat (serwer domyśla się wtedy 30 dni) wysyłamy datę od dawnej przeszłości,
/// żeby objąć całe archiwum — inaczej widżet pokazywałby tylko ostatni miesiąc.
final failureAnalysisProvider =
    FutureProvider.autoDispose<FailureAnalysis>((ref) async {
  ref.watch(serverProfileProvider);
  final filter = ref.watch(statsFilterProvider);
  var (from, to) = StatsNotifier._resolveDates(filter);
  from ??= DateTime(2000);
  to ??= DateTime.now();
  return ref.read(statsRepositoryProvider).fetchFailures(from: from, to: to);
});
