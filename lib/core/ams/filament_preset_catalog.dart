/// Merging the three preset sources into the one list the slot picker shows.
///
/// Rules, all of them the web's:
///
/// - **Tier order.** Local first (the user went to the trouble of importing
///   them), then cloud, then the built-in table as a floor.
/// - **Deduplication runs the other way.** A built-in entry is dropped when the
///   cloud already *shows* the same filament, because the cloud copy is the one
///   with a real preset behind it. A cloud preset the filters hid covers
///   nothing — otherwise hiding it would hide the material.
/// - **Filter by printer, but only on evidence.** A preset whose name names a
///   different printer is hidden; one that names no printer at all stays.
/// - **Never hide what the slot is already set to.** The current pick has to
///   remain selectable even when the filters would drop it, or reopening the
///   sheet would silently offer to change a slot the user only wanted to look
///   at.
library;

import '../models/ams_filament_preset.dart';
import 'filament_naming.dart';
import 'printer_model_match.dart';

/// Build the picker's list.
///
/// [query] filters on the visible name, and applies to every tier including the
/// current pick — a search that kept showing one unmatched entry would look
/// broken. [printerModel] is the short code from `Printer.model`;
/// [printerModels] the registry from `GET /slicer/printer-models`.
/// [fullPrinterName] is [fullPrinterPresetName] for this printer, used for the
/// imported presets' own compatibility list. [savedPresetId] is
/// [AmsFilamentPreset.pickerId] of the slot's saved mapping and [currentFilamentId]
/// the `tray_info_idx` the printer reports — either identifies the current pick.
List<AmsFilamentPreset> filamentPresetCatalog({
  List<AmsFilamentPreset> cloud = const [],
  List<AmsFilamentPreset> local = const [],
  List<AmsFilamentPreset> builtin = const [],
  String query = '',
  String? printerModel,
  Map<String, String> printerModels = const {},
  String? fullPrinterName,
  String? savedPresetId,
  String? currentFilamentId,
}) {
  final needle = query.trim().toLowerCase();
  bool matchesQuery(String name) =>
      needle.isEmpty || name.toLowerCase().contains(needle);

  final items = <AmsFilamentPreset>[];
  final covered = <String>{};

  for (final preset in cloud) {
    if (!matchesQuery(preset.name)) continue;
    if (!_isCurrent(preset, savedPresetId, currentFilamentId) &&
        !_fitsPrinter(preset.name, printerModel, printerModels)) {
      continue;
    }
    // Only a preset that survived both filters covers its built-in twin.
    // Marking it earlier would let a cloud PETG hidden as "belongs to another
    // printer" take generic PETG down with it, and the material would vanish
    // from the picker entirely.
    covered.add(preset.id);
    items.add(preset);
  }

  for (final preset in local) {
    if (!matchesQuery(preset.name)) continue;
    if (!_isCurrent(preset, savedPresetId, currentFilamentId) &&
        !_fitsCompatibilityList(preset, fullPrinterName)) {
      continue;
    }
    items.add(preset);
  }

  for (final preset in builtin) {
    // A built-in id is a filament id (`GFA00`); the cloud lists setting ids
    // (`GFSA00`). Check both spellings or the same filament shows up twice.
    final asSettingId = preset.id.startsWith('GF')
        ? 'GFS${preset.id.substring(2)}'
        : preset.id;
    if (covered.contains(preset.id) || covered.contains(asSettingId)) continue;
    if (!matchesQuery(preset.name)) continue;
    items.add(preset);
  }

  items.sort((a, b) {
    if (a.source != b.source) {
      return _tierOrder(a.source).compareTo(_tierOrder(b.source));
    }
    if (a.isUser != b.isUser) return a.isUser ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return items;
}

int _tierOrder(AmsPresetSource source) => switch (source) {
      AmsPresetSource.local => 0,
      AmsPresetSource.cloud => 1,
      AmsPresetSource.builtin => 2,
    };

bool _isCurrent(
  AmsFilamentPreset preset,
  String? savedPresetId,
  String? currentFilamentId,
) {
  if (savedPresetId != null && savedPresetId == preset.pickerId) return true;
  if (currentFilamentId == null || currentFilamentId.isEmpty) return false;
  if (preset.source != AmsPresetSource.cloud) return false;
  return preset.id == currentFilamentId ||
      filamentIdFromSettingId(preset.id) == currentFilamentId;
}

/// True unless the name names a *different* printer. A name that resolves to no
/// model, or a card with no known model of its own, keeps the preset.
bool _fitsPrinter(
  String name,
  String? printerModel,
  Map<String, String> printerModels,
) {
  if (printerModel == null || printerModel.isEmpty) return true;
  final presetModel = presetPrinterModel(name, printerModels);
  if (presetModel == null) return true;
  return matchesPrinterModel(presetModel, printerModel);
}

/// Imported presets carry the slicer's own `compatible_printers` list, which is
/// better evidence than the name — but only when both sides are known. A preset
/// without a list stays visible: hand-edited and lossily-imported bundles have
/// none, and those were usable before the filter existed.
bool _fitsCompatibilityList(AmsFilamentPreset preset, String? fullPrinterName) {
  final compatible = preset.compatiblePrinters;
  if (compatible == null || compatible.isEmpty) return true;
  if (fullPrinterName == null || fullPrinterName.isEmpty) return true;
  final wanted = normalisePrinterPresetName(fullPrinterName);
  return compatible.any((name) => normalisePrinterPresetName(name) == wanted);
}
