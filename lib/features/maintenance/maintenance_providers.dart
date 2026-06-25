import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/maintenance.dart';
import '../../providers.dart';

/// Wynik akcji konserwacji zwracany do widżetu — to on pokazuje SnackBar
/// (notifier nie ma [BuildContext]). Analogicznie do kolejki (M5).
enum MaintenanceActionResult { ok, forbidden, error }

final maintenanceOverviewProvider = AutoDisposeAsyncNotifierProvider<
    MaintenanceOverviewNotifier, List<PrinterMaintenanceOverview>>(
  MaintenanceOverviewNotifier.new,
);

/// Przegląd konserwacji wszystkich drukarek (M7). Lista grupowana po drukarce
/// pochodzi wprost z serwera; „oznacz wykonane" (perform) resetuje licznik po
/// stronie serwera, więc po sukcesie dociągamy świeży stan zamiast zgadywać.
class MaintenanceOverviewNotifier
    extends AutoDisposeAsyncNotifier<List<PrinterMaintenanceOverview>> {
  @override
  Future<List<PrinterMaintenanceOverview>> build() async {
    // Przebudowa przy zmianie profilu serwera (inny klucz/uprawnienia).
    ref.watch(serverProfileProvider);
    return ref.read(maintenanceRepositoryProvider).fetchOverview();
  }

  /// Pull-to-refresh / odświeżenie po mutacji. Zachowuje poprzednią listę pod
  /// spodem (AsyncLoading z previous), żeby UI nie mrugało spinnerem.
  Future<void> refresh() async {
    state = const AsyncValue<List<PrinterMaintenanceOverview>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(maintenanceRepositoryProvider).fetchOverview(),
    );
  }

  /// Oznacza czynność jako wykonaną (reset licznika). Po sukcesie odświeżenie
  /// listy (stan zmienia się po stronie serwera).
  Future<MaintenanceActionResult> perform(int itemId, {String? notes}) async {
    try {
      await ref.read(maintenanceRepositoryProvider).perform(itemId, notes: notes);
      await refresh();
      return MaintenanceActionResult.ok;
    } on AppApiException catch (e) {
      if (e is AuthException && e.code == AppErrorCode.forbidden) {
        return MaintenanceActionResult.forbidden;
      }
      return MaintenanceActionResult.error;
    }
  }
}

/// Łączny czas druku (godziny) danej drukarki z przeglądu konserwacji. Dane są
/// historyczne (serwer liczy je niezależnie od WS), więc dostępne także gdy
/// drukarka OFFLINE — dzięki temu karta dashboardu może je pokazać po zwinięciu.
/// Null = brak danych/jeszcze nieładowane (UI chowa wtedy wiersz).
final printerTotalPrintHoursProvider =
    Provider.autoDispose.family<double?, int>((ref, printerId) {
  final overview = ref.watch(maintenanceOverviewProvider).valueOrNull;
  if (overview == null) return null;
  for (final p in overview) {
    if (p.printerId == printerId) return p.totalPrintHours;
  }
  return null;
});

/// Historia wykonania czynności — ładowana na żądanie (bottom-sheet). Autodispose
/// + family po `itemId`, bo otwieramy ją punktowo dla wybranej pozycji.
final maintenanceHistoryProvider = FutureProvider.autoDispose
    .family<List<MaintenanceHistoryEntry>, int>(
  (ref, itemId) =>
      ref.watch(maintenanceRepositoryProvider).fetchHistory(itemId),
);
