import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../providers.dart';

/// Wynik akcji kolejki zwracany do widżetu — to on pokazuje SnackBar
/// (notifier nie ma [BuildContext]). Analogicznie do sterowania w M4.
enum QueueActionResult { ok, forbidden, error }

final queueProvider =
    AutoDisposeAsyncNotifierProvider<QueueNotifier, List<QueueItem>>(
  QueueNotifier.new,
);

/// Kolejka wydruku (M5). Pokazujemy tylko elementy AKTYWNE (oczekujące,
/// zaplanowane, drukujące, wstrzymane) posortowane po `position` — historia
/// (completed/cancelled) żyje w archiwum, nie w kolejce.
///
/// Reorder i usuwanie są optymistyczne z rollbackiem (wzorzec
/// `ControlsNotifier` z M4): UI reaguje natychmiast, błąd cofa zmianę.
/// Start/anuluj zmieniają stan po stronie serwera (start uruchamia fizyczny
/// wydruk!), więc po sukcesie dociągamy świeżą listę zamiast zgadywać.
class QueueNotifier extends AutoDisposeAsyncNotifier<List<QueueItem>> {
  @override
  Future<List<QueueItem>> build() async {
    // Przebudowa przy zmianie profilu serwera (inny klucz/uprawnienia).
    ref.watch(serverProfileProvider);
    final all = await ref.read(queueRepositoryProvider).fetch();
    return _activeSorted(all);
  }

  List<QueueItem> _activeSorted(List<QueueItem> items) {
    // Drukujące zawsze na górze (przypięte, nieprzesuwalne w UI), potem reszta
    // po `position` z `id` jako tiebreakerem: serwer domyślnie trzyma
    // `position == 1` dla wszystkich, dopóki kolejka nie zostanie ułożona, więc
    // bez stabilnego tiebreakera kolejność byłaby nieokreślona.
    int printingFirst(QueueItem i) =>
        i.statusKind == QueueItemStatusKind.printing ? 0 : 1;
    return items.where((i) => i.isActive).toList()
      ..sort((a, b) {
        final byPrinting = printingFirst(a).compareTo(printingFirst(b));
        if (byPrinting != 0) return byPrinting;
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
  }

  /// Pull-to-refresh / odświeżenie po mutacji. Zachowuje poprzednią listę
  /// pod spodem (AsyncLoading z previous), żeby UI nie mrugało spinnerem.
  Future<void> refresh() async {
    state = const AsyncValue<List<QueueItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () async => _activeSorted(await ref.read(queueRepositoryProvider).fetch()),
    );
  }

  /// Optymistyczna zmiana kolejności (drag&drop). Indeksy w konwencji
  /// `onReorderItem` z `ReorderableListView` — `newIndex` jest JUŻ skorygowany
  /// o usunięcie elementu spod `oldIndex`, więc wstawiamy bez dodatkowej korekty.
  /// Na serwer wysyłamy SEKWENCYJNE pozycje 1..N w nowej kolejności — endpoint
  /// „bulk update positions" oczekuje wartości docelowych, a domyślnie wszystkie
  /// elementy mają `position == 1` (zweryfikowane na żywo, patrz reorder w
  /// kontrakcie). Błąd → rollback do stanu sprzed przeciągnięcia.
  Future<QueueActionResult> reorder(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    if (current == null) return QueueActionResult.error;
    if (oldIndex == newIndex) return QueueActionResult.ok;

    final list = [...current];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    state = AsyncValue.data(list); // optymistycznie

    final payload = [
      for (var i = 0; i < list.length; i++) (id: list[i].id, position: i + 1),
    ];
    try {
      await ref.read(queueRepositoryProvider).reorder(payload);
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      state = AsyncValue.data(current); // rollback
      return _mapError(e);
    }
  }

  /// Optymistyczne usunięcie (swipe-to-delete). Błąd → przywrócenie elementu.
  Future<QueueActionResult> delete(int itemId) async {
    final current = state.valueOrNull;
    if (current == null) return QueueActionResult.error;

    state = AsyncValue.data(
      current.where((i) => i.id != itemId).toList(),
    );
    try {
      await ref.read(queueRepositoryProvider).delete(itemId);
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      state = AsyncValue.data(current); // rollback
      return _mapError(e);
    }
  }

  /// Ręczne wystartowanie elementu — uruchamia fizyczny wydruk. Po sukcesie
  /// dociągamy świeżą listę (status zmienia się po stronie serwera).
  Future<QueueActionResult> start(int itemId) =>
      _serverAction(() => ref.read(queueRepositoryProvider).start(itemId));

  /// Anulowanie elementu kolejki. Po sukcesie odświeżenie listy.
  Future<QueueActionResult> cancel(int itemId) =>
      _serverAction(() => ref.read(queueRepositoryProvider).cancel(itemId));

  /// Przypisanie wskazanej (wolnej) drukarki i wystartowanie elementu —
  /// uruchamia fizyczny wydruk. `start` nie przyjmuje drukarki, więc najpierw
  /// PATCH `printer_id`, potem POST `start`. Po sukcesie odświeżenie listy.
  Future<QueueActionResult> startOnPrinter(int itemId, int printerId) =>
      _serverAction(() async {
        final repo = ref.read(queueRepositoryProvider);
        await repo.assignPrinter(itemId, printerId);
        await repo.start(itemId);
      });

  Future<QueueActionResult> _serverAction(Future<void> Function() send) async {
    try {
      await send();
      await refresh();
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      return _mapError(e);
    }
  }

  QueueActionResult _mapError(AppApiException e) {
    if (e is AuthException && e.code == AppErrorCode.forbidden) {
      return QueueActionResult.forbidden;
    }
    return QueueActionResult.error;
  }
}

/// Wolne drukarki do startu z kolejki: podłączone i nie zajęte wydrukiem
/// (ani drukowaniem, ani pauzą). Pobiera drukarki + statusy świeżo przy każdym
/// wywołaniu (autoDispose), bo „wolność" zmienia się w czasie.
final freePrintersProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) async {
    final all = await ref.watch(printersRepositoryProvider).fetchAll();
    return [
      for (final p in all)
        if ((p.status?.connected ?? false) &&
            !(p.status?.isPrinting ?? false) &&
            !(p.status?.isPaused ?? false))
          p.printer,
    ];
  },
);
