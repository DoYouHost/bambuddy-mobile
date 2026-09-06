import '../../core/models/filament_requirement.dart';
import '../../core/models/slicer_preset.dart';
import '../common/hex_color.dart';
import 'slice_providers.dart';

/// The `filament_colours` array of a `SliceRequest`: one `#RRGGBB` per plate
/// slot, in the same order as `filament_presets`.
///
/// Neither Bambu Studio nor OrcaSlicer store a colour on a *filament preset* —
/// it is a per-project property — so the CLI the server drives falls back to
/// its compiled-in Bambu green for every slice unless the request names one.
/// That is what made a mobile-triggered slice come out green and then report a
/// Color mismatch against the AMS slot it was mapped to (server #2977).
///
/// The colour of a slot is the colour of the spool behind the preset picked for
/// it: the picker offers presets, and a preset name is what an inventory spool
/// carries, so the spool is where the only real colour lives. Several spools can
/// share one preset name in different colours, and there the one closest to what
/// the plate was designed with wins — the same rule that auto-picked the preset
/// in the first place.
///
/// An entry is left empty where nothing answers, which is how the server is told
/// "fall back for this one slot" without shortening the list and shifting every
/// slot after it. An all-empty result comes back as an empty list so the caller
/// can drop the key entirely and leave the request byte-identical to one from
/// before this existed.
List<String> sliceFilamentColours({
  required List<SlicerPreset?> picked,
  required List<OwnedFilament> owned,
  required List<FilamentRequirement> requirements,
}) {
  final colours = [
    for (var i = 0; i < picked.length; i++)
      sliceSlotColour(
        picked: picked[i],
        owned: owned,
        requirement: i < requirements.length ? requirements[i] : null,
      ),
  ];
  return colours.every((c) => c.isEmpty) ? const [] : colours;
}

/// One slot's entry for [sliceFilamentColours]; `''` when nothing names a colour.
String sliceSlotColour({
  required SlicerPreset? picked,
  required List<OwnedFilament> owned,
  required FilamentRequirement? requirement,
}) {
  final name = picked?.name;
  if (name == null) return '';
  final matches = [
    for (final o in owned)
      if (o.name == name && hexColour(o.color) != null) o,
  ];
  if (matches.isEmpty) return '';
  // A single match needs no tie-break, and `colorDistance` answers
  // `double.maxFinite` for both sides when the plate named no colour — which
  // would otherwise order the candidates by nothing at all.
  final chosen = matches.length == 1 || requirement?.color == null
      ? matches.first
      : (matches.toList()..sort(
              (a, b) => colorDistance(
                a.color,
                requirement!.color,
              ).compareTo(colorDistance(b.color, requirement.color)),
            ))
            .first;
  return hexColour(chosen.color)!;
}

/// `ff0000ff` / `#FF0000` → `#FF0000`, or null when [raw] names no colour.
///
/// Alpha is dropped rather than passed through: the inventory writes `RRGGBBAA`
/// and the slicer profile takes the value as the filament's own colour, where a
/// transparency the spool never had would be a claim about the material.
String? hexColour(String? raw) {
  final rgb = rgbFromHex(raw);
  if (rgb == null) return null;
  String hex(int c) => c.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${hex(rgb.$1)}${hex(rgb.$2)}${hex(rgb.$3)}';
}
