/// The payload of `POST /printers/{id}/slots/{ams}/{tray}/configure`.
///
/// The route is a pass-through to two MQTT commands and derives nothing, so
/// every field below has to be right before it leaves: the printer accepts a
/// wrong material or a wrong temperature range as readily as a right one, and
/// then prints with it.
library;

import '../models/filament_preset.dart';
import 'filament_naming.dart';

/// One slot's filament configuration, ready to send.
class SlotConfiguration {
  const SlotConfiguration({
    required this.trayInfoIdx,
    required this.trayType,
    required this.traySubBrands,
    required this.trayColour,
    required this.nozzleTempMin,
    required this.nozzleTempMax,
    required this.nozzleDiameter,
    this.settingId = '',
    this.caliIdx = -1,
    this.kProfileFilamentId = '',
    this.kProfileSettingId = '',
    this.kValue = 0,
  });

  /// Derive the configuration for [preset].
  ///
  /// [colourHex] is six hex digits without `#`; the alpha the printer wants is
  /// appended here, since a value that already carries one would be rejected
  /// with 422 further down. [cloudFilamentId] is the `filament_id` read from a
  /// cloud preset's detail — pass it when known, because a custom preset's list
  /// id is not the id the printer resolves.
  factory SlotConfiguration.forPreset({
    required FilamentPreset preset,
    required String colourHex,
    required String nozzleDiameter,
    String? cloudFilamentId,
  }) {
    final parsed = parsePresetName(preset.name);
    final material = _materialOf(preset, parsed);
    final defaults = nozzleTemperaturesFor(material);

    return SlotConfiguration(
      trayInfoIdx: switch (preset.source) {
        // A built-in entry *is* the filament id.
        FilamentPresetSource.builtin => preset.id,
        // Imported presets have no Bambu id at all, so the closest generic is
        // what lets the printer classify the material.
        FilamentPresetSource.local => genericFilamentId(material),
        FilamentPresetSource.cloud =>
          cloudFilamentId ?? filamentIdFromSettingId(preset.id),
      },
      trayType: material,
      traySubBrands: presetNameWithoutPrinter(preset.name),
      trayColour: '$colourHex$_opaque',
      // An imported preset's own range wins where it has one; either end it
      // leaves out falls back to the material's, not to a fixed PLA range.
      nozzleTempMin: _temperature(preset.nozzleTempMin) ?? defaults.min,
      nozzleTempMax: _temperature(preset.nozzleTempMax) ?? defaults.max,
      nozzleDiameter: nozzleDiameter,
      // Only a cloud preset has a setting id the slicer can look up. Sending a
      // local row id or a bare filament id here would name a preset that does
      // not exist on the printer's side.
      settingId:
          preset.source == FilamentPresetSource.cloud ? preset.id : '',
    );
  }

  /// Filament id the printer stores for the slot (`GFL05`, or a user preset's
  /// own id).
  final String trayInfoIdx;

  /// Material, e.g. `PLA`.
  final String trayType;

  /// The preset's display name without its `@…` printer suffix — what the
  /// printer and the slicer show for the slot.
  final String traySubBrands;

  /// `RRGGBBAA`, no leading `#`.
  final String trayColour;

  final int nozzleTempMin;
  final int nozzleTempMax;

  /// e.g. `0.4`. Also the key the printer's calibration table is indexed by.
  final String nozzleDiameter;

  /// Cloud `setting_id` with its version suffix, empty for the other tiers.
  final String settingId;

  /// Calibration profile to select, `-1` for the printer's default K = 0.020.
  /// Always `-1` until the K-profile picker lands.
  final int caliIdx;

  final String kProfileFilamentId;
  final String kProfileSettingId;
  final double kValue;

  Map<String, dynamic> toQuery() => <String, dynamic>{
        'tray_info_idx': trayInfoIdx,
        'tray_type': trayType,
        'tray_sub_brands': traySubBrands,
        'tray_color': trayColour,
        'nozzle_temp_min': nozzleTempMin,
        'nozzle_temp_max': nozzleTempMax,
        'cali_idx': caliIdx,
        'nozzle_diameter': nozzleDiameter,
        'setting_id': settingId,
        'kprofile_filament_id': kProfileFilamentId,
        'kprofile_setting_id': kProfileSettingId,
        'k_value': kValue,
      };
}

/// The printer wants an alpha channel and every slot we configure is opaque —
/// transparency in `tray_color` is how an *empty* slot is reported.
const _opaque = 'FF';

/// A bundle that records 0 °C is recording "not set", not a cold nozzle.
int? _temperature(int? value) => (value == null || value <= 0) ? null : value;

/// The material to send. The name is the better source even for an imported
/// preset that records one: "PLA Support for PETG" is stored as PLA by older
/// importers, and the parse handles that shape correctly.
String _materialOf(FilamentPreset preset, ParsedPresetName parsed) {
  final fromName = parsed.material.toUpperCase();
  if (filamentMaterials.contains(fromName)) return fromName;
  final declared = preset.filamentType?.trim();
  if (declared != null && declared.isNotEmpty) return declared.toUpperCase();
  return fromName.isEmpty ? 'PLA' : fromName;
}
