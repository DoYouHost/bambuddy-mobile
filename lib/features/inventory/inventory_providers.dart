import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/inventory.dart';
import '../../core/models/inventory_reference.dart';
import '../../data/inventory_repository.dart';
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

  /// Wykonuje mutację, po czym przeładowuje listę (źródło prawdy = serwer —
  /// bez optymistycznych podmian, bo zapisy są rzadkie, a dane wyliczane).
  /// Wyjątek propagujemy do wywołującego (UI pokazuje snackbar), ale i tak
  /// odświeżamy stan. Zwraca utworzoną/zmienioną szpulę (lub null).
  Future<Spool?> _mutate(Future<Spool?> Function(InventoryRepository) action) async {
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      return await action(repo);
    } finally {
      state = await AsyncValue.guard(_load);
    }
  }

  Future<Spool?> createSpool(SpoolDraft draft) =>
      _mutate((repo) => repo.createSpool(draft));

  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) =>
      _mutate((repo) => repo.updateSpool(spoolId, draft));

  Future<void> deleteSpool(int spoolId) =>
      _mutate((repo) async => repo.deleteSpool(spoolId).then((_) => null));

  Future<void> archiveSpool(int spoolId) =>
      _mutate((repo) async => repo.archiveSpool(spoolId).then((_) => null));

  Future<void> restoreSpool(int spoolId) =>
      _mutate((repo) async => repo.restoreSpool(spoolId).then((_) => null));

  Future<void> resetUsage(int spoolId) =>
      _mutate((repo) async => repo.resetUsage(spoolId).then((_) => null));
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

/// Dane referencyjne formularza szpuli (Faza 2). Ładowane przy otwarciu
/// formularza; degradują się do pustej listy (formularz dopuszcza wpis ręczny),
/// więc błąd nie blokuje dodania szpuli. Trzymane chwilę po zamknięciu
/// (`keepAlive`), by ponowne otwarcie nie pobierało od nowa.
final coreWeightsProvider =
    FutureProvider.autoDispose<List<CoreWeightEntry>>((ref) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchCoreWeights();
  } on Object {
    return const [];
  }
});

final colorCatalogProvider =
    FutureProvider.autoDispose<List<ColorEntry>>((ref) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchColors();
  } on Object {
    return const [];
  }
});

final filamentPresetsProvider =
    FutureProvider.autoDispose<List<FilamentPreset>>((ref) async {
  ref.keepAlive();
  try {
    return await ref.watch(inventoryRepositoryProvider).fetchFilamentPresets();
  } on Object {
    return const [];
  }
});

/// Opcje dropdownu materiału: stałe popularne + materiały z profili katalogu i
/// istniejących szpul (zachowane wartości użytkownika). Posortowane, unikalne.
const _commonMaterials = [
  'PLA', 'PETG', 'ABS', 'ASA', 'TPU', 'PA', 'PC', 'PVA', 'HIPS', 'PET', 'PP',
];

/// Popularne podtypy/warianty filamentu (pole „Subtype" w bambuddy).
const _commonSubtypes = [
  'Basic', 'Matte', 'Silk', 'Tough', 'Translucent', 'Glow', 'Marble',
  'Metal', 'Wood', 'CF', 'GF', 'Sparkle', 'Gradient',
];

final materialOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final presets = ref.watch(filamentPresetsProvider).valueOrNull ?? const [];
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    ..._commonMaterials,
    for (final p in presets)
      if (p.type.trim().isNotEmpty) p.type.trim(),
    for (final s in spools) s.material,
  };
  final list = set.toList()..sort();
  return list;
});

final brandOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final presets = ref.watch(filamentPresetsProvider).valueOrNull ?? const [];
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    for (final p in presets)
      if (p.brand != null && p.brand!.trim().isNotEmpty) p.brand!.trim(),
    for (final s in spools)
      if (s.brand != null && s.brand!.trim().isNotEmpty) s.brand!.trim(),
  };
  final list = set.toList()..sort();
  return list;
});

final subtypeOptionsProvider = Provider.autoDispose<List<String>>((ref) {
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final set = <String>{
    ..._commonSubtypes,
    for (final s in spools)
      if (s.subtype != null && s.subtype!.trim().isNotEmpty) s.subtype!.trim(),
  };
  final list = set.toList()..sort();
  return list;
});
