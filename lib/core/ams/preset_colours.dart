/// The colours a filament is actually sold in, for the slot the user is
/// configuring.
///
/// bambuddy keeps a catalogue of manufacturer colours (`/inventory/colors`, the
/// same table the spool form picks from) with a name, a hex and the material it
/// belongs to. Nothing links it to a slicer preset, so the pairing is done on
/// the preset's own name — the web does the same in `ConfigureAmsSlotModal`.
library;

import '../models/inventory_reference.dart';
import 'filament_naming.dart';

/// Catalogue entries that plausibly belong to [presetName], deduplicated by
/// colour.
///
/// A miss here costs nothing — the wheel underneath still picks any colour at
/// all — so the matching leans generous: material either way round, and a brand
/// that merely overlaps.
List<ColorEntry> presetColours(
  List<ColorEntry> catalogue,
  String presetName,
) {
  final parsed = parsePresetName(presetName);
  // Material plus variant, which is how the catalogue spells its own material
  // field ("PLA Basic", "PLA Silk"), rather than the bare material.
  final wanted = '${parsed.material} ${parsed.variant}'.trim().toUpperCase();
  if (wanted.isEmpty) return const [];

  final brand = presetBrand(parsed);

  final byColour = <String, ColorEntry>{};
  for (final entry in catalogue) {
    final material = (entry.material ?? '').trim().toUpperCase();
    // An entry that names no material would otherwise match every filament:
    // "contains the empty string" is true of all of them.
    if (material.isEmpty) continue;
    if (!material.contains(wanted) && !wanted.contains(material)) continue;

    if (brand.isNotEmpty) {
      final maker = entry.manufacturer.trim().toUpperCase();
      if (!maker.contains(brand) && !brand.contains(maker)) continue;
    }

    // One swatch per colour: the same hex is listed once per material and
    // manufacturer that sells it, and a grid of visually identical squares
    // reads as a rendering fault. The catalogue arrives sorted, so the first
    // spelling wins.
    final hex = sixHexDigits(entry.hexColor);
    if (hex == null) continue;
    byColour.putIfAbsent(hex, () => entry);
  }
  return byColour.values.toList();
}

/// Six upper-case hex digits from any of the spellings a colour arrives in
/// (`#RRGGBB`, `RRGGBB`, `RRGGBBAA`), or null when it is not a colour at all.
///
/// The alpha is dropped rather than kept: the catalogue writes `#RRGGBB` and
/// the printer writes `RRGGBBAA`, and the two have to compare equal — while a
/// slot's `00` alpha means *empty*, which must never become a picked colour.
String? sixHexDigits(String? raw) {
  final hex = raw?.trim().replaceFirst('#', '');
  if (hex == null || hex.length < 6) return null;
  final rgb = hex.substring(0, 6).toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(rgb) ? rgb : null;
}
