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
      // (w AMS lub zewnętrznie) przed luźnymi.
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final aLoaded = bySpool.containsKey(a.id);
      final bLoaded = bySpool.containsKey(b.id);
      if (aLoaded != bLoaded) return aLoaded ? -1 : 1;
      // Wśród przypisanych: najpierw szpule z najmniejszą pozostałą masą, by te
      // bliskie końca rzucały się w oczy. Luźne — alfabetycznie po nazwie.
      if (aLoaded && bLoaded) {
        final byRemaining = a.remainingWeight.compareTo(b.remainingWeight);
        if (byRemaining != 0) return byRemaining;
      }
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

  /// Przypisuje szpulę do slotu, pilnując że szpula siedzi w DOKŁADNIE jednym
  /// slocie: jeśli była już gdzie indziej, [from] wskazuje stary slot i najpierw
  /// ją stamtąd odpinamy (przeniesienie). [from] == ten sam slot → samo przypisanie.
  Future<void> assignSpool(SpoolAssignmentDraft draft,
          {SpoolAssignment? from}) =>
      _mutate((repo) async {
        if (from != null &&
            !(from.printerId == draft.printerId &&
                from.amsId == draft.amsId &&
                from.trayId == draft.trayId)) {
          await repo.unassignSpool(from.printerId, from.amsId, from.trayId);
        }
        await repo.assignSpool(draft);
        return null;
      });

  Future<void> unassignSpool(int printerId, int amsId, int trayId) => _mutate(
      (repo) async =>
          repo.unassignSpool(printerId, amsId, trayId).then((_) => null));
}

/// Rozwiązuje, która szpula z magazynu siedzi w danym slocie konkretnej
/// drukarki — do wzbogacenia czipów AMS na dashboardzie (dokładna pozostała
/// waga + nazwa). Budowane z [InventoryState]; matchowanie zależy od kształtu
/// przypisań (patrz [[inventory-filaments]]).
class AssignedSpools {
  const AssignedSpools(this.printerId, this._byKey, this._byExtruder);

  /// Pusty resolver (magazyn nieziaładowany / błąd) — nie wzbogaca niczego.
  static const empty = AssignedSpools(-1, {}, {});

  final int printerId;

  /// Klucz `amsId * 1000 + trayId` → szpula (sloty jednostek AMS).
  final Map<int, Spool> _byKey;

  /// Ekstruder (1=lewy, 0=prawy) → szpula zewnętrzna.
  final Map<int, Spool> _byExtruder;

  /// Szpula w slocie jednostki AMS (`amsId` = id jednostki, `trayId` = numer
  /// tacy w jednostce). Null, gdy nic nie przypisano.
  Spool? forAmsSlot(int amsId, int trayId) => _byKey[amsId * 1000 + trayId];

  /// Szpula zewnętrzna karmiąca dany ekstruder (1=lewy, 0=prawy).
  Spool? forExtruder(int? extruder) =>
      extruder == null ? null : _byExtruder[extruder];

  bool get isEmpty => _byKey.isEmpty && _byExtruder.isEmpty;
}

/// Resolver przypisań dla jednej drukarki (po `printerId`). Czyta `inventoryProvider`
/// (współdzieli ten sam fetch co zakładka Filamentów); degraduje się do pustego,
/// gdy magazyn jeszcze się nie załadował lub padł — dashboard działa bez niego.
final assignedSpoolsProvider =
    Provider.autoDispose.family<AssignedSpools, int>((ref, printerId) {
  final inv = ref.watch(inventoryProvider).valueOrNull;
  if (inv == null) return AssignedSpools.empty;
  final spoolById = {for (final s in inv.spools) s.id: s};
  final byKey = <int, Spool>{};
  final byExtruder = <int, Spool>{};
  for (final a in inv.assignmentBySpool.values) {
    if (a.printerId != printerId) continue;
    final spool = spoolById[a.spoolId];
    if (spool == null) continue;
    if (a.isExternalSpool) {
      final ext = a.extruder;
      if (ext != null) byExtruder[ext] = spool;
    } else {
      byKey[a.amsId * 1000 + a.trayId] = spool;
    }
  }
  return AssignedSpools(printerId, byKey, byExtruder);
});

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
