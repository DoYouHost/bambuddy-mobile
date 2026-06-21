import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/inventory.dart';
import '../../providers.dart';

/// Migawka magazynu dla ekranu: wszystkie szpule (z zarchiwizowanymi) plus mapa
/// `spoolId → przypisanie do slotu AMS`. Filtrowanie (szukaj / pokaż
/// zarchiwizowane) robimy po stronie klienta na tej liście — dane zmieniają się
/// wolno, więc jeden fetch wystarcza, a przełączniki działają natychmiast.
class InventoryState {
  const InventoryState({
    this.spools = const [],
    this.assignmentBySpool = const {},
  });

  final List<Spool> spools;
  final Map<int, SpoolAssignment> assignmentBySpool;

  SpoolAssignment? assignmentFor(int spoolId) => assignmentBySpool[spoolId];
}

final inventoryProvider =
    AutoDisposeAsyncNotifierProvider<InventoryNotifier, InventoryState>(
  InventoryNotifier.new,
);

/// Pobiera szpule i przypisania jednym przebiegiem. Przypisania degradują się do
/// pustej mapy, gdy endpoint padnie/jest niedostępny — lista szpul ważniejsza
/// niż info, w którym slocie siedzą. Przebudowa przy zmianie profilu/backendu.
class InventoryNotifier extends AutoDisposeAsyncNotifier<InventoryState> {
  @override
  Future<InventoryState> build() async {
    ref.watch(serverProfileProvider);
    ref.watch(inventoryBackendProvider);
    return _load();
  }

  Future<InventoryState> _load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    final spools = await repo.fetchSpools(includeArchived: true);

    // Przypisania są dodatkiem — ich brak nie może wywrócić ekranu.
    var bySpool = <int, SpoolAssignment>{};
    try {
      final assignments = await repo.fetchAssignments();
      bySpool = {for (final a in assignments) a.spoolId: a};
    } on Object {
      bySpool = const {};
    }

    spools.sort((a, b) {
      // Kolejność: aktywne przed zarchiwizowanymi; wśród aktywnych — załadowane
      // (w AMS lub zewnętrznie) przed luźnymi; na końcu alfabetycznie po nazwie.
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final aLoaded = bySpool.containsKey(a.id);
      final bLoaded = bySpool.containsKey(b.id);
      if (aLoaded != bLoaded) return aLoaded ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return InventoryState(spools: spools, assignmentBySpool: bySpool);
  }

  /// Pull-to-refresh. Zachowuje poprzednie dane pod spodem (bez mrugania
  /// spinnerem), wzorzec jak konserwacja.
  Future<void> refresh() async {
    state = const AsyncValue<InventoryState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
  }
}

/// Tekst wyszukiwania (materiał/marka/kolor/lokalizacja). Filtrowanie po stronie
/// klienta w widoku.
final inventoryQueryProvider = StateProvider.autoDispose<String>((_) => '');

/// Zestaw filtrów magazynu (poza wyszukiwaniem) — dobierany w arkuszu filtrów.
/// Wszystko stosowane po stronie klienta na pełnej liście szpul. Domyślnie:
/// tylko aktywne, bez ograniczeń. Puste zbiory = „wszystkie".
class InventoryFilters {
  const InventoryFilters({
    this.showArchived = false,
    this.lowStockOnly = false,
    this.materials = const {},
    this.brands = const {},
    this.locations = const {},
  });

  /// false → tylko aktywne (domyślnie); true → tylko zarchiwizowane.
  final bool showArchived;
  final bool lowStockOnly;
  final Set<String> materials;
  final Set<String> brands;
  final Set<String> locations;

  /// Liczba niedomyślnych filtrów — na plakietkę przy przycisku filtrów.
  int get activeCount =>
      (showArchived ? 1 : 0) +
      (lowStockOnly ? 1 : 0) +
      (materials.isNotEmpty ? 1 : 0) +
      (brands.isNotEmpty ? 1 : 0) +
      (locations.isNotEmpty ? 1 : 0);

  InventoryFilters copyWith({
    bool? showArchived,
    bool? lowStockOnly,
    Set<String>? materials,
    Set<String>? brands,
    Set<String>? locations,
  }) =>
      InventoryFilters(
        showArchived: showArchived ?? this.showArchived,
        lowStockOnly: lowStockOnly ?? this.lowStockOnly,
        materials: materials ?? this.materials,
        brands: brands ?? this.brands,
        locations: locations ?? this.locations,
      );
}

final inventoryFiltersProvider =
    StateProvider.autoDispose<InventoryFilters>((_) => const InventoryFilters());

/// Historia zużycia szpuli — ładowana na żądanie w szczegółach (family po id).
final spoolUsageProvider = FutureProvider.autoDispose
    .family<List<SpoolUsageEntry>, int>(
  (ref, spoolId) => ref.watch(inventoryRepositoryProvider).fetchUsage(spoolId),
);
