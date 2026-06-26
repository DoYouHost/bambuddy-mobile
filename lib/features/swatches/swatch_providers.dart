import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/swatch_code.dart';
import '../../providers.dart';
import '../inventory/inventory_providers.dart';

/// Rejestr kodów swatch (dane lokalne). Ładowany z SharedPreferences przy
/// pierwszym dostępie; każda mutacja zapisuje całość z powrotem (lista jest
/// mała, zapisy rzadkie). Posortowany alfabetycznie po nazwie definicji.
final swatchCodesProvider =
    NotifierProvider<SwatchCodesNotifier, List<SwatchCode>>(
  SwatchCodesNotifier.new,
);

class SwatchCodesNotifier extends Notifier<List<SwatchCode>> {
  @override
  List<SwatchCode> build() => _sorted(
        ref.watch(settingsRepositoryProvider).loadSwatchCodes(),
      );

  static List<SwatchCode> _sorted(List<SwatchCode> codes) {
    final list = [...codes]..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return list;
  }

  Future<void> _persist(List<SwatchCode> next) async {
    final sorted = _sorted(next);
    await ref.read(settingsRepositoryProvider).saveSwatchCodes(sorted);
    state = sorted;
  }

  /// Czy dany kod (znormalizowany) już istnieje. [exclude] pomija wpis o danym
  /// kodzie (edycja własnego wpisu nie jest kolizją).
  bool hasCode(String code, {String? exclude}) {
    final c = normalizeSwatchCode(code);
    final ex = exclude == null ? null : normalizeSwatchCode(exclude);
    return state.any((e) => e.code == c && (ex == null || e.code != ex));
  }

  /// Losuje kod nieużywany jeszcze w rejestrze. Po wielu kolizjach (mało
  /// prawdopodobne przy 887 mln kombinacji) i tak zwraca ostatni — kolizja
  /// zostałaby wychwycona przy zapisie.
  String freshCode() {
    for (var i = 0; i < 50; i++) {
      final c = generateSwatchCode();
      if (!hasCode(c)) return c;
    }
    return generateSwatchCode();
  }

  /// Dodaje definicję z auto-wygenerowanym kodem. Zwraca utworzony wpis.
  Future<SwatchCode> add({
    required String material,
    String? brand,
    String? variant,
    String? colorName,
    String? rgba,
  }) async {
    final entry = SwatchCode(
      code: freshCode(),
      material: material,
      brand: brand,
      variant: variant,
      colorName: colorName,
      rgba: rgba,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _persist([...state, entry]);
    return entry;
  }

  /// Zapisuje wpis (tworzenie lub edycja). [replacingCode] = stary kod przy
  /// edycji (gdy użytkownik zmienił sam kod, usuwamy stary wpis). Wpis o tym
  /// samym (nowym) kodzie zostaje nadpisany.
  Future<void> save(SwatchCode entry, {String? replacingCode}) async {
    final replacing =
        replacingCode == null ? null : normalizeSwatchCode(replacingCode);
    final next = <SwatchCode>[
      for (final e in state)
        if (e.code != replacing && e.code != entry.code) e,
      entry,
    ];
    await _persist(next);
  }

  Future<void> remove(String code) async {
    final c = normalizeSwatchCode(code);
    await _persist([for (final e in state) if (e.code != c) e]);
  }

  /// Nadpisuje CAŁY rejestr (import z pliku). Dedup po kodzie — wygrywa
  /// pierwsze wystąpienie.
  Future<void> replaceAll(List<SwatchCode> codes) async {
    final seen = <String>{};
    final deduped = <SwatchCode>[];
    for (final c in codes) {
      if (c.code.isEmpty) continue;
      if (seen.add(c.code)) deduped.add(c);
    }
    await _persist(deduped);
  }
}

/// Definicje filamentów z magazynu (aktywne szpule), które NIE mają jeszcze
/// kodu swatch. Deduplikacja po tożsamości (marka+materiał+wariant+kolor).
/// Współdzieli fetch magazynu z zakładką Filamentów; pusta, gdy magazyn się
/// jeszcze nie załadował lub padł.
final uncodedFilamentsProvider =
    Provider.autoDispose<List<FilamentIdentity>>((ref) {
  final spools = ref.watch(inventoryProvider).valueOrNull?.spools ?? const [];
  final coded = {for (final c in ref.watch(swatchCodesProvider)) c.identityKey};
  final seen = <String>{};
  final out = <FilamentIdentity>[];
  for (final s in spools) {
    if (s.isArchived) continue;
    final identity = FilamentIdentity(
      material: s.material,
      brand: s.brand,
      variant: s.subtype,
      colorName: s.colorName,
      rgba: s.rgba,
    );
    final key = identity.key;
    if (coded.contains(key)) continue;
    if (!seen.add(key)) continue;
    out.add(identity);
  }
  out.sort(
    (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return out;
});

/// Tekst wyszukiwania na ekranie kodów (po kodzie lub nazwie). Filtrowanie po
/// stronie klienta.
final swatchQueryProvider = StateProvider.autoDispose<String>((_) => '');
