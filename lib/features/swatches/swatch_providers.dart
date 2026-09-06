import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/swatch_code.dart';
import '../../providers.dart';
import '../inventory/inventory_providers.dart';

/// Swatch codes registry (local data). Loaded from SharedPreferences on first
/// access; each mutation persists entire list (small list, rare writes).
/// Alphabetically sorted by definition name.
final swatchCodesProvider =
    NotifierProvider<SwatchCodesNotifier, List<SwatchCode>>(
      SwatchCodesNotifier.new,
    );

class SwatchCodesNotifier extends Notifier<List<SwatchCode>> {
  @override
  List<SwatchCode> build() =>
      _sorted(ref.watch(settingsRepositoryProvider).loadSwatchCodes());

  static List<SwatchCode> _sorted(List<SwatchCode> codes) {
    final list = [...codes]
      ..sort(
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

  /// Whether given code (normalized) already exists. [exclude] skips entry with
  /// given code (editing own entry is not a collision).
  bool hasCode(String code, {String? exclude}) {
    final c = normalizeSwatchCode(code);
    final ex = exclude == null ? null : normalizeSwatchCode(exclude);
    return state.any((e) => e.code == c && (ex == null || e.code != ex));
  }

  /// Generate unused code in registry. After many collisions (unlikely with 887M
  /// combinations) still returns last — collision caught on save.
  String freshCode() {
    for (var i = 0; i < 50; i++) {
      final c = generateSwatchCode();
      if (!hasCode(c)) return c;
    }
    return generateSwatchCode();
  }

  /// Add definition with auto-generated code. Return created entry.
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

  /// Save entry (create or edit). [replacingCode] = old code on edit (if user
  /// changed code itself, remove old entry). Entry with same (new) code is overwritten.
  Future<void> save(SwatchCode entry, {String? replacingCode}) async {
    final replacing = replacingCode == null
        ? null
        : normalizeSwatchCode(replacingCode);
    final next = <SwatchCode>[
      for (final e in state)
        if (e.code != replacing && e.code != entry.code) e,
      entry,
    ];
    await _persist(next);
  }

  Future<void> remove(String code) async {
    final c = normalizeSwatchCode(code);
    await _persist([
      for (final e in state)
        if (e.code != c) e,
    ]);
  }

  /// Overwrite ENTIRE registry (file import). Dedup by code — first occurrence wins.
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

/// Filament definitions from inventory (active spools) without swatch code yet.
/// Dedup by identity (brand+material+variant+color). Shares inventory fetch with
/// Filaments tab; empty if inventory not loaded or failed.
final uncodedFilamentsProvider = Provider.autoDispose<List<FilamentIdentity>>((
  ref,
) {
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
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return out;
});

/// Search text on codes screen (by code or name). Client-side filtering.
final swatchQueryProvider = StateProvider.autoDispose<String>((_) => '');
