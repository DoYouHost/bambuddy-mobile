import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive.dart';
import '../../core/models/printer.dart';
import '../../providers.dart';

/// Rozmiar strony przy przewijaniu archiwum.
const _pageSize = 50;

/// Minimalna długość zapytania wymagana przez serwer (krótsze → 422).
const _minQueryLength = 2;

/// Stan listy archiwum: pozycje + czy jest kolejna strona + aktywne zapytanie.
class ArchiveState {
  const ArchiveState({
    this.items = const [],
    this.hasMore = true,
    this.loadingMore = false,
    this.query = '',
    this.searchFailed = false,
  });

  final List<Archive> items;
  final bool hasMore;
  final bool loadingMore;
  final String query;

  /// Wyszukiwanie zwróciło błąd (serwer bywa niestabilny na krótkich, częstych
  /// zapytaniach — patrz `_fetchPage`). UI pokazuje łagodny komunikat zamiast
  /// wywalać cały ekran błędem.
  final bool searchFailed;

  ArchiveState copyWith({
    List<Archive>? items,
    bool? hasMore,
    bool? loadingMore,
    String? query,
    bool? searchFailed,
  }) =>
      ArchiveState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        query: query ?? this.query,
        searchFailed: searchFailed ?? this.searchFailed,
      );
}

final archiveProvider =
    AutoDisposeAsyncNotifierProvider<ArchiveNotifier, ArchiveState>(
  ArchiveNotifier.new,
);

/// Lista archiwum z paginacją (infinite scroll) i wyszukiwaniem (M5).
/// Pusty `query` → `GET /archives/` (paginowane); niepusty → `/archives/search`.
class ArchiveNotifier extends AutoDisposeAsyncNotifier<ArchiveState> {
  @override
  Future<ArchiveState> build() async {
    ref.watch(serverProfileProvider);
    return _fetchPage(query: '', offset: 0);
  }

  Future<ArchiveState> _fetchPage({
    required String query,
    required int offset,
  }) async {
    final repo = ref.read(archiveRepositoryProvider);
    final page = query.isEmpty
        ? await repo.list(limit: _pageSize, offset: offset)
        : await repo.search(query, limit: _pageSize, offset: offset);
    return ArchiveState(
      items: page,
      hasMore: page.length == _pageSize,
      query: query,
    );
  }

  /// Nowe wyszukiwanie / wyczyszczenie — resetuje listę do pierwszej strony.
  /// Zapytanie krótsze niż [_minQueryLength] traktujemy jak puste (pełna lista):
  /// serwer i tak odrzuca <2 znaki (422). Błąd searcha nie wywala ekranu —
  /// ustawiamy [ArchiveState.searchFailed] i pokazujemy łagodny komunikat.
  Future<void> search(String query) async {
    final q = query.length >= _minQueryLength ? query : '';
    state = const AsyncValue<ArchiveState>.loading().copyWithPrevious(state);
    try {
      state = AsyncValue.data(await _fetchPage(query: q, offset: 0));
    } on AppApiException {
      state = AsyncValue.data(
        ArchiveState(items: const [], query: q, searchFailed: true),
      );
    }
  }

  /// Pull-to-refresh: ponowne pobranie pierwszej strony bieżącego zapytania.
  Future<void> refresh() async {
    final query = state.valueOrNull?.query ?? '';
    state = const AsyncValue<ArchiveState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _fetchPage(query: query, offset: 0));
  }

  /// Dociąga kolejną stronę i dokleja do listy. Bez rzucania — błąd
  /// dociągania nie może wywrócić już pokazanych pozycji (zatrzymuje paginację).
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final repo = ref.read(archiveRepositoryProvider);
      final next = current.query.isEmpty
          ? await repo.list(limit: _pageSize, offset: current.items.length)
          : await repo.search(
              current.query,
              limit: _pageSize,
              offset: current.items.length,
            );
      state = AsyncValue.data(current.copyWith(
        items: [...current.items, ...next],
        hasMore: next.length == _pageSize,
        loadingMore: false,
      ));
    } on AppApiException {
      // Zatrzymaj paginację, zachowaj to, co już mamy.
      state = AsyncValue.data(current.copyWith(
        hasMore: false,
        loadingMore: false,
      ));
    }
  }
}

/// Lekka lista drukarek do pickera (reprint / dodanie do kolejki). Tylko
/// konfiguracja, bez statusów — tańsze niż `fetchAll`.
final printersForPickerProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);
