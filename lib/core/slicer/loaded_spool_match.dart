/// Matching what the connected printers have loaded against the slice form's
/// preset lists (#3172) — `sliceLoadedSpools.ts` on the web, ported rule for
/// rule.
///
/// Two questions:
///
/// 1. Which printer models are online, and is a printer preset one of them? A
///    preset whose model cannot be read ("My farm printer") is never ruled out.
/// 2. Which filament preset does a loaded slot stand for, on the printer
///    preset picked in the form? Strongest evidence first: the preset bambuddy
///    saved for the slot, while it still describes the slot (#3216) and fits
///    the printer; the same preset under another printer's tag, by base name;
///    for a slot nobody configured, the spool's own brand text, or
///    "Generic `material`". A slot with no match is not guessed at.
library;

import '../ams/printer_model_match.dart';
import '../models/loaded_spools.dart';
import '../models/slicer_preset.dart';
import 'preset_compatibility.dart';

/// `source:id`, the identity a preset keeps across lists.
String presetKey(SlicerPreset preset) => '${preset.source}:${preset.id}';

/// The short model of a printer preset ("Bambu Lab X1 Carbon 0.4 nozzle" →
/// "X1C"), or null when the name is not a Bambu printer preset.
String? printerPresetModel(String? name, Map<String, String> registry) {
  if (name == null) return null;
  final m = RegExp(
    r'^Bambu Lab\s+(.+?)(?:\s+[\d.]+\s*nozzle)?$',
    caseSensitive: false,
  ).firstMatch(name.replaceFirst(RegExp(r'^#\s*'), '').trim());
  if (m == null) return null;
  final fragment = m.group(1)!.trim();
  final full = 'bambu lab $fragment'.toLowerCase();
  for (final MapEntry(:key, :value) in registry.entries) {
    if (key.toLowerCase() == full) return value;
  }
  return fragment;
}

bool sameModel(String? a, String? b) {
  if (a == null || b == null || a.trim().isEmpty || b.trim().isEmpty) {
    return false;
  }
  return matchesPrinterModel(a.trim(), b.trim());
}

/// The connected printers of [model]; all of them when it is unknown.
List<LoadedSpoolPrinter> printersOfModel(
  List<LoadedSpoolPrinter> printers,
  String? model,
) => model == null
    ? printers
    : [
        for (final p in printers)
          if (sameModel(p.model, model)) p,
      ];

/// Whether a printer preset is for a connected model, or cannot be told.
bool isConnectedModelPreset(
  SlicerPreset preset,
  List<String?> connectedModels,
  Map<String, String> registry,
) {
  final model = printerPresetModel(preset.name, registry);
  if (model == null) return true;
  return connectedModels.any((c) => sameModel(c, model));
}

/// A printer preset for a connected model, for the auto-pick while "only
/// online printers" is on. The 0.4 nozzle first, Bambu's default, since
/// nothing here says which nozzle is fitted. [printers] is in tier order.
SlicerPreset? pickConnectedPrinterPreset(
  List<SlicerPreset> printers,
  List<String?> connectedModels,
  Map<String, String> registry,
) {
  SlicerPreset? fallback;
  for (final preset in printers) {
    final model = printerPresetModel(preset.name, registry);
    if (model == null || !connectedModels.any((c) => sameModel(c, model))) {
      continue;
    }
    if (RegExp(
      r'\b0\.4\s*nozzle\b',
      caseSensitive: false,
    ).hasMatch(preset.name)) {
      return preset;
    }
    fallback ??= preset;
  }
  return fallback;
}

/// A preset name without its "# " clone prefix and "@printer" suffix.
String presetDisplayName(String name) {
  var s = name.replaceFirst(RegExp(r'^#\s*'), '');
  final at = s.lastIndexOf('@');
  if (at > 0) s = s.substring(0, at);
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [presetDisplayName], case-folded — the key one preset's copies for
/// different printers share.
String presetBaseName(String name) => presetDisplayName(name).toLowerCase();

/// Whether a slot's saved preset still describes the spool in it (#3216,
/// `amsHelpers.ts::slotPresetDescribesTray`): the filament id recorded with
/// it decides when there is one; otherwise a Bambu `GFS…` preset id has to
/// name the tray's `GF…` filament.
bool slotPresetDescribesTray(
  String presetId,
  String? trayInfoIdx,
  String? recordedTrayInfoIdx,
) {
  String head(String? s) => (s ?? '').split('_').first.toUpperCase();
  final preset = head(presetId);
  final tray = head(trayInfoIdx);
  final recorded = head(recordedTrayInfoIdx);
  if (recorded.isNotEmpty && tray.isNotEmpty) return recorded == tray;
  if (!preset.startsWith('GFS') ||
      !tray.startsWith('GF') ||
      tray.startsWith('GFS')) {
    return true;
  }
  return 'GF${preset.substring(3)}' == tray;
}

/// The saved preset, unless the slot was reconfigured since.
LoadedSpoolPreset? savedPresetFor(LoadedSpoolTray tray) {
  final saved = tray.savedPreset;
  if (saved == null) return null;
  return slotPresetDescribesTray(
        saved.presetId,
        tray.trayInfoIdx,
        saved.trayInfoIdx,
      )
      ? saved
      : null;
}

/// The saved preset as `(source, id)` in the presets listing. A bundled
/// (`builtin_<filament id>`) one is addressed by name there, so it is only
/// reached through [_nameCandidates].
(String, String)? _savedRef(LoadedSpoolPreset saved) {
  switch (saved.presetSource) {
    case 'local':
      final m = RegExp(r'^local_(\d+)$').firstMatch(saved.presetId);
      return m == null ? null : ('local', m.group(1)!);
    case 'cloud' || 'orca_cloud':
      return saved.presetId.isEmpty
          ? null
          : (saved.presetSource, saved.presetId);
  }
  return null;
}

List<String> _nameCandidates(LoadedSpoolTray tray, LoadedSpoolPreset? saved) {
  final out = <String>[
    if (saved != null && saved.presetName.isNotEmpty) saved.presetName,
  ];
  final sub = (tray.traySubBrands ?? '').trim();
  if (sub.isNotEmpty) {
    // Bambu's spools report "PLA Basic" for the "Bambu PLA Basic" profile —
    // only on Bambu filament ids, so a third-party "PLA Basic" is not renamed.
    if (RegExp(r'^GF', caseSensitive: false).hasMatch(tray.trayInfoIdx ?? '') &&
        !RegExp(r'^bambu\b', caseSensitive: false).hasMatch(sub)) {
      out.add('Bambu $sub');
    }
    out.add(sub);
  } else if (tray.trayType != null) {
    out.add('Generic ${tray.trayType}');
  }
  final seen = <String>{};
  return [
    for (final name in out)
      if (presetBaseName(name).isNotEmpty && seen.add(presetBaseName(name)))
        name,
  ];
}

/// Filament presets by [presetBaseName], each list in tier order.
typedef FilamentNameIndex = Map<String, List<SlicerPreset>>;

FilamentNameIndex buildFilamentNameIndex(List<SlicerPreset> filaments) {
  final index = <String, List<SlicerPreset>>{};
  for (final preset in filaments) {
    (index[presetBaseName(preset.name)] ??= []).add(preset);
  }
  return index;
}

/// `slicePresetPicker.ts::statesDifferentMaterial`: both sides name a
/// material and they differ. A preset that names none is never ruled out.
bool statesDifferentMaterial(SlicerPreset preset, String requiredType) {
  final required = requiredType.trim().toUpperCase();
  final stated = (preset.filamentType ?? '').trim().toUpperCase();
  return required.isNotEmpty && stated.isNotEmpty && required != stated;
}

/// The filament preset [tray] stands for on [selectedPrinterName], or null
/// when nothing fits. [filaments] is the whole listing, in tier order.
SlicerPreset? matchSlotPreset(
  LoadedSpoolTray tray, {
  required List<SlicerPreset> filaments,
  required FilamentNameIndex index,
  required String? selectedPrinterName,
  required Map<String, String> registry,
}) {
  if (!tray.isLoaded) return null;
  final saved = savedPresetFor(tray);
  PresetFit fit(SlicerPreset p) =>
      presetCompatibility(p, selectedPrinterName, registry);

  final ref = saved == null ? null : _savedRef(saved);
  if (ref != null) {
    final (source, id) = ref;
    final preset = filaments
        .where((p) => p.source == source && p.id == id)
        .firstOrNull;
    // The user chose this one for the slot: its material is not second-guessed,
    // only whether it is for the selected printer.
    if (preset != null && fit(preset) != PresetFit.mismatch) return preset;
  }

  for (final name in _nameCandidates(tray, saved)) {
    final entries = index[presetBaseName(name)] ?? const <SlicerPreset>[];
    // The saved preset's tier first, then the usual order.
    final ordered = ref == null
        ? entries
        : [
            ...entries.where((e) => e.source == ref.$1),
            ...entries.where((e) => e.source != ref.$1),
          ];
    SlicerPreset? unknown;
    for (final preset in ordered) {
      if (statesDifferentMaterial(preset, tray.trayType ?? '')) continue;
      switch (fit(preset)) {
        case PresetFit.match:
          return preset;
        case PresetFit.unknown:
          unknown ??= preset;
        case PresetFit.mismatch:
          break;
      }
    }
    if (unknown != null) return unknown;
  }
  return null;
}

/// Every loaded tray of [printers]: AMS units first, then external holders.
List<LoadedSpoolTray> loadedTrays(List<LoadedSpoolPrinter> printers) => [
  for (final printer in printers) ...[
    for (final unit in printer.ams)
      for (final tray in unit.trays)
        if (tray.isLoaded) tray,
    for (final tray in printer.external)
      if (tray.isLoaded) tray,
  ],
];

/// [presetKey]s of the presets at least one loaded tray matches.
Set<String> matchedFilamentKeys(
  List<LoadedSpoolPrinter> printers, {
  required List<SlicerPreset> filaments,
  required FilamentNameIndex index,
  required String? selectedPrinterName,
  required Map<String, String> registry,
}) => {
  for (final tray in loadedTrays(printers))
    if (matchSlotPreset(
          tray,
          filaments: filaments,
          index: index,
          selectedPrinterName: selectedPrinterName,
          registry: registry,
        )
        case final match?)
      presetKey(match),
};

/// "#RRGGBB" from the printer's `RRGGBBAA`, or null when it is not one.
String? trayColourHex(LoadedSpoolTray tray) {
  final raw = (tray.trayColor ?? '').replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}').hasMatch(raw)) return null;
  return '#${raw.substring(0, 6).toUpperCase()}';
}
