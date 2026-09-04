/// Narrowing a filament preset list to what the user is actually looking for.
///
/// A cloud account holds every preset for every printer and every material the
/// user has ever had, and the picker shows all of them in one flat list. Two
/// facts are usually already known where it opens — which printer model the
/// preset is being chosen for, and what the spool is made of — and each of them
/// cuts the list by an order of magnitude.
///
/// Both filters **fail open**, the same rule
/// [presetFitsPrinterModel] is written to: a preset the evidence does not
/// cover stays in the list. Hiding one we merely failed to classify is worse
/// than showing one too many, and the user can switch either filter off.
library;

import '../ams/printer_model_match.dart';
import '../models/slicer_preset.dart';

/// The presets to show, in the order they came.
///
/// [query] matches the visible name or the preset id. [printerModel] is the
/// short code on `Printer.model`, and [printerModels] the registry from
/// `GET /slicer/printer-models` that [presetPrinterModel] reads the other two
/// name shapes through — worth passing, but not required: without it Bambu's
/// own `@BBL <code>` suffix still decides.
/// [material] is the spool's material as the user spells it.
List<SlicerPreset> filterFilamentPresets(
  List<SlicerPreset> presets, {
  String query = '',
  String? printerModel,
  Map<String, String> printerModels = const {},
  String? material,
}) {
  final needle = query.trim().toLowerCase();
  return [
    for (final preset in presets)
      if (needle.isEmpty ||
          preset.name.toLowerCase().contains(needle) ||
          preset.id.toLowerCase().contains(needle))
        if (presetFitsPrinterModel(preset.name, printerModel, printerModels))
          if (presetFitsMaterial(preset, material)) preset,
  ];
}

/// Whether [preset] is for [material], as far as anything on it says.
///
/// The declared `filament_type` settles it **either way** where the preset has
/// one — the same shape as the model filter, where evidence of a mismatch is
/// what hides a preset. Reading the name after a declared type had already
/// disagreed would let a PETG preset that merely mentions PLA pass as one.
///
/// The name is the fallback because the cloud and standard tiers leave the
/// type null, which is most of the list. Matched on a word boundary: a plain
/// substring test makes every `PCTG` preset a `PC` one.
bool presetFitsMaterial(SlicerPreset preset, String? material) {
  final wanted = material?.trim() ?? '';
  if (wanted.isEmpty) return true;
  final pattern = _wordPattern(wanted);
  final declared = preset.filamentType?.trim() ?? '';
  if (declared.isNotEmpty) return pattern.hasMatch(declared);
  return pattern.hasMatch(preset.name);
}

/// A literal material as a word-boundary pattern, with whitespace loosened so
/// "PLA Basic" also matches a name that spells it with two spaces.
RegExp _wordPattern(String value) {
  final escaped = value
      .replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}')
      .replaceAll(RegExp(r'\s+'), r'\s+');
  return RegExp('(?<![\\w])$escaped(?![\\w])', caseSensitive: false);
}
