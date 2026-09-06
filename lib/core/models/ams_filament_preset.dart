/// Filament presets offered when configuring an AMS slot, and the record of
/// which one a slot was given.
///
/// Three sources answer with three different shapes and only one of them needs
/// a Bambu Cloud login, so they are normalised into one type here: the picker
/// shows a single list, and everything downstream branches on [source] instead
/// of on where the JSON came from.
library;

import 'dart:convert';

import 'json_utils.dart';

/// Where a preset came from. The order is the picker's own — a preset the user
/// imported outranks one Bambu happens to ship.
enum AmsPresetSource {
  /// Imported from a slicer bundle (`GET /local-presets/`). Carries real
  /// material and temperature fields, and no Bambu id of any kind.
  local,

  /// The user's Bambu Cloud account (`GET /cloud/settings`). Needs a cloud
  /// login; without one this tier is simply absent.
  cloud,

  /// Bambu's built-in table (`GET /cloud/builtin-filaments`). Always available,
  /// which makes it the floor the picker can never fall below.
  builtin,
}

/// One selectable filament preset.
class AmsFilamentPreset {
  const AmsFilamentPreset({
    required this.source,
    required this.id,
    required this.name,
    this.isUser = false,
    this.filamentType,
    this.nozzleTempMin,
    this.nozzleTempMax,
    this.compatiblePrinters,
  });

  /// From `SlicerSetting` in `/cloud/settings` → `filament`.
  factory AmsFilamentPreset.fromCloudJson(Map<String, dynamic> json) {
    final id = json['setting_id']?.toString() ?? '';
    return AmsFilamentPreset(
      source: AmsPresetSource.cloud,
      id: id,
      name: json['name'] as String? ?? '',
      // `is_custom` is what the server says; the id shape is what the web
      // trusts. They agree in practice, and the id is present even on a
      // response that predates the flag.
      isUser: !id.startsWith('GF') && !id.startsWith('P1'),
    );
  }

  /// From `LocalPresetResponse` in `/local-presets/` → `filament`.
  factory AmsFilamentPreset.fromLocalJson(Map<String, dynamic> json) =>
      AmsFilamentPreset(
        source: AmsPresetSource.local,
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        filamentType: json['filament_type'] as String?,
        nozzleTempMin: toIntOrNull(json['nozzle_temp_min']),
        nozzleTempMax: toIntOrNull(json['nozzle_temp_max']),
        compatiblePrinters: _decodePrinterList(
          json['compatible_printers'] as String?,
        ),
      );

  /// From `/cloud/builtin-filaments` — `{filament_id, name}`.
  factory AmsFilamentPreset.fromBuiltinJson(Map<String, dynamic> json) =>
      AmsFilamentPreset(
        source: AmsPresetSource.builtin,
        id: json['filament_id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
      );

  final AmsPresetSource source;

  /// Source-specific: the cloud `setting_id`, the local row id as a string, or
  /// the built-in `filament_id`. Use [pickerId] to tell them apart across
  /// sources.
  final String id;
  final String name;

  /// A preset the user authored rather than one Bambu ships. Sorted first
  /// within its tier; only meaningful for [AmsPresetSource.cloud].
  final bool isUser;

  /// Material as the slicer bundle recorded it. Local presets only — the other
  /// two tiers carry it in the name and nowhere else.
  final String? filamentType;

  /// Temperature range from the bundle, either end possibly missing.
  final int? nozzleTempMin;
  final int? nozzleTempMax;

  /// Printer presets this one declares itself compatible with, already decoded
  /// from the JSON-encoded string the server stores. Null means the preset
  /// says nothing, which is not the same as saying "nothing fits".
  final List<String>? compatiblePrinters;

  /// Identity across the whole picker, and the id saved as the slot's mapping.
  /// The tiers number themselves independently — a local row id of `5` and a
  /// built-in `GFA05` would otherwise be equally "5" — so local and built-in
  /// ids are prefixed, matching what the web writes.
  String get pickerId => switch (source) {
    AmsPresetSource.local => 'local_$id',
    AmsPresetSource.builtin => 'builtin_$id',
    AmsPresetSource.cloud => id,
  };

  /// The value `/slot-presets` takes as `preset_source`.
  String get sourceKey => source.name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmsFilamentPreset && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => 'AmsFilamentPreset($pickerId, $name)';
}

/// The preset a slot was last configured with, as the server remembers it
/// (`GET /printers/{id}/slot-presets/{ams}/{tray}`).
///
/// The printer keeps only a filament id, and a user cloud preset's id resolves
/// to no name anywhere — so without this mapping a configured slot can be shown
/// but not named.
class SlotPreset {
  const SlotPreset({
    required this.amsId,
    required this.trayId,
    required this.presetId,
    required this.presetName,
    this.presetSource,
  });

  factory SlotPreset.fromJson(Map<String, dynamic> json) => SlotPreset(
    amsId: toIntOrNull(json['ams_id']) ?? 0,
    trayId: toIntOrNull(json['tray_id']) ?? 0,
    presetId: json['preset_id']?.toString() ?? '',
    presetName: json['preset_name'] as String? ?? '',
    presetSource: json['preset_source'] as String?,
  );

  final int amsId;
  final int trayId;

  /// Matches [AmsFilamentPreset.pickerId] of whatever was chosen.
  final String presetId;
  final String presetName;

  /// `local` / `cloud` / `builtin`, absent on the read routes.
  final String? presetSource;
}

/// `compatible_printers` arrives as a JSON-encoded array inside a string field.
/// Anything that does not decode to a list of strings is treated as absent —
/// a preset we cannot read a printer list from must stay visible, not vanish.
List<String>? _decodePrinterList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final names = decoded.whereType<String>().toList();
    return names.isEmpty ? null : names;
  } on FormatException {
    return null;
  }
}
