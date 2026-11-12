import '../../core/models/inventory_reference.dart';

/// The catalogue entries a spool of [brand] [material] [subtype] is sold in,
/// branch for branch as the web's spool form narrows them
/// (`spool-form/ColorSection.tsx`, `matchedCatalogColors`). Empty when neither
/// brand nor material is set, or nothing matches.
///
/// The brand matches by word, so "mz - Bambu" finds "Bambu Lab". The material
/// tries the catalogue's own spelling first ("PLA Matte"), then the same
/// without a trailing `+`, then every material starting with the bare one.
List<ColorEntry> catalogueColoursFor(
  List<ColorEntry> catalogue, {
  String? brand,
  String? material,
  String? subtype,
}) {
  final b = brand?.trim() ?? '';
  final m = material?.trim().toLowerCase() ?? '';
  final s = subtype?.trim().toLowerCase() ?? '';
  if (b.isEmpty && m.isEmpty) return const [];

  final words = b
      .toLowerCase()
      .split(RegExp(r'[\s\-_]+'))
      .where((w) => w.length >= 2)
      .toList();
  bool byBrand(ColorEntry e) {
    if (words.isEmpty) return true;
    final maker = e.manufacturer.toLowerCase();
    return words.any(maker.contains);
  }

  List<ColorEntry> where(bool Function(ColorEntry) test) =>
      catalogue.where((e) => byBrand(e) && test(e)).toList();

  if (b.isNotEmpty && m.isEmpty) {
    final brandOnly = where((_) => true);
    if (brandOnly.isNotEmpty) return brandOnly;
  }

  if (m.isNotEmpty && s.isNotEmpty) {
    final full = '$m $s';
    final exact = where((e) => e.material?.toLowerCase() == full);
    if (exact.isNotEmpty) return exact;
    final plain = full.replaceFirst(RegExp(r'\+$'), '');
    if (plain != full) {
      final unplussed = where((e) => e.material?.toLowerCase() == plain);
      if (unplussed.isNotEmpty) return unplussed;
    }
  }

  if (m.isNotEmpty) {
    // The web keeps entries that name no material at all.
    return where((e) {
      final own = e.material?.toLowerCase();
      return own == null || own.isEmpty || own.startsWith(m);
    });
  }
  return const [];
}
