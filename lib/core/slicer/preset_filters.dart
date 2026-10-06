/// Narrowing a filament preset list to what the user is actually looking for.
///
/// A cloud account holds every preset for every printer and material the user
/// has ever had, in one flat list. Two facts are usually known where the picker
/// opens — the printer model and the spool's material — and each cuts the list
/// by an order of magnitude.
///
/// Both filters **fail open**, like [presetFitsPrinterModel]: a preset the
/// evidence does not cover stays in. Hiding one we merely failed to classify is
/// worse than showing one too many.
library;

import '../ams/printer_model_match.dart';
import '../models/slicer_preset.dart';

/// The presets to show, in the order they came.
///
/// [query] matches the visible name or the preset id. [printerModel] is the
/// short code on `Printer.model`, and [printerModels] the registry from
/// `GET /slicer/printer-models` — worth passing, but without it Bambu's own
/// `@BBL <code>` suffix still decides. [material] is spelled as the user does.
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
/// one: reading the name after a declared type disagreed would let a PETG preset
/// that merely mentions PLA pass as one. The name is the fallback because the
/// cloud and standard tiers leave the type null, which is most of the list.
/// Matched on a word boundary — a substring test makes every `PCTG` a `PC`.
bool presetFitsMaterial(SlicerPreset preset, String? material) {
  final wanted = material?.trim() ?? '';
  if (wanted.isEmpty) return true;
  final pattern = _wordPattern(wanted);
  final declared = preset.filamentType?.trim() ?? '';
  if (declared.isNotEmpty) return pattern.hasMatch(declared);
  return pattern.hasMatch(preset.name);
}

/// Whether [preset] is [brand]'s, read off its name — presets carry no vendor
/// field. A word match anywhere, so "eSUN PETG" and "PETG eSUN" both count.
bool presetFitsBrand(SlicerPreset preset, String? brand) {
  final wanted = brand?.trim() ?? '';
  return wanted.isEmpty || _wordPattern(wanted).hasMatch(preset.name);
}

/// The brand a filament preset's name leads with ("SUNLU TPU @…" → "SUNLU"),
/// or null for a name with nothing before its first space.
String? presetBrand(SlicerPreset preset) {
  final name = preset.name.replaceFirst(RegExp(r'^#\s*'), '').trim();
  final space = name.indexOf(' ');
  return space <= 0 ? null : name.substring(0, space);
}

/// Materials a filament preset can be filtered by when nothing narrows the
/// list to what the user owns: its declared type, else any of these found in
/// its name — the cloud and standard tiers leave the type empty.
const knownMaterials = [
  'PLA', 'PETG', 'PET', 'ABS', 'ASA', 'TPU', 'PA', 'PC', 'PVA', 'HIPS', //
  'PPS', 'PPA', 'PE', 'PP', 'BVOH',
];

/// The material [preset] is for, as far as anything on it says.
String? presetMaterial(SlicerPreset preset) {
  final declared = preset.filamentType?.trim() ?? '';
  if (declared.isNotEmpty) return declared.toUpperCase();
  for (final m in knownMaterials) {
    if (_wordPattern(m).hasMatch(preset.name)) return m;
  }
  return null;
}

/// A literal material as a word-boundary pattern, with whitespace loosened so
/// "PLA Basic" also matches a name that spells it with two spaces.
RegExp _wordPattern(String value) {
  final escaped = value
      .replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}')
      .replaceAll(RegExp(r'\s+'), r'\s+');
  return RegExp('(?<![\\w])$escaped(?![\\w])', caseSensitive: false);
}
