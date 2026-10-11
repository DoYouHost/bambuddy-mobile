import 'package:app_util/app_util.dart';

/// `GET /slicer/loaded-spools` (server #3172, `schemas/slicer_presets.py`):
/// the printers connected right now and what each has loaded, limited to the
/// caller's printers. An offline printer is left out entirely, since its last
/// known trays may be long gone.

/// The filament profile bambuddy recorded for a slot (`slot_preset_mappings`).
/// [trayInfoIdx] is the filament id the slot was configured with alongside it,
/// so a record that outlived a spool swap can be told apart (#3216).
class LoadedSpoolPreset {
  const LoadedSpoolPreset({
    required this.presetId,
    required this.presetName,
    required this.presetSource,
    this.trayInfoIdx,
  });

  factory LoadedSpoolPreset.fromJson(Map<String, dynamic> json) =>
      LoadedSpoolPreset(
        presetId: toStringOrNull(json['preset_id']) ?? '',
        presetName: toStringOrNull(json['preset_name']) ?? '',
        presetSource: toStringOrNull(json['preset_source']) ?? '',
        trayInfoIdx: toStringOrNull(json['tray_info_idx']),
      );

  /// `local_<row id>`, a cloud setting id, or `builtin_<filament id>`.
  final String presetId;
  final String presetName;

  /// `local`, `cloud`, `orca_cloud` or `builtin`.
  final String presetSource;
  final String? trayInfoIdx;
}

/// One AMS slot or external holder as the printer reports it. External
/// holders come as unit 255, tray 0 (left) / 1 (right).
class LoadedSpoolTray {
  const LoadedSpoolTray({
    required this.amsId,
    required this.trayId,
    this.trayType,
    this.traySubBrands,
    this.trayColor,
    this.trayInfoIdx,
    this.exists,
    this.state,
    this.savedPreset,
  });

  factory LoadedSpoolTray.fromJson(Map<String, dynamic> json) =>
      LoadedSpoolTray(
        amsId: toInt(json['ams_id']),
        trayId: toInt(json['tray_id']),
        trayType: toStringOrNull(json['tray_type']),
        traySubBrands: toStringOrNull(json['tray_sub_brands']),
        trayColor: toStringOrNull(json['tray_color']),
        trayInfoIdx: toStringOrNull(json['tray_info_idx']),
        exists: json['exists'] is bool ? json['exists'] as bool : null,
        state: json['state'] is int ? json['state'] as int : null,
        savedPreset: json['saved_preset'] is Map<String, dynamic>
            ? LoadedSpoolPreset.fromJson(json['saved_preset'])
            : null,
      );

  final int amsId;
  final int trayId;

  /// Null on an empty slot — and on a spool the firmware sees ([exists]) but
  /// cannot identify, which is "loaded, unconfigured".
  final String? trayType;
  final String? traySubBrands;

  /// `RRGGBBAA`, no `#`.
  final String? trayColor;
  final String? trayInfoIdx;

  /// The firmware's presence bit; null where the printer did not send it.
  final bool? exists;

  /// The firmware's tray state, read only when [exists] is missing.
  final int? state;
  final LoadedSpoolPreset? savedPreset;

  bool get isLoaded => trayType?.isNotEmpty ?? false;

  /// A spool is there but carries no material — a non-RFID spool nobody set
  /// up — rather than an empty slot. `amsHelpers.ts::getEmptySlotKind`: the
  /// presence bit decides, and states 9/10 (empty) only without it.
  bool get isUnidentified {
    if (isLoaded) return false;
    if (exists != null) return exists!;
    return state != 9 && state != 10;
  }
}

class LoadedSpoolUnit {
  const LoadedSpoolUnit({
    required this.id,
    required this.isAmsHt,
    this.trays = const [],
  });

  factory LoadedSpoolUnit.fromJson(Map<String, dynamic> json) =>
      LoadedSpoolUnit(
        id: toInt(json['id']),
        isAmsHt: json['is_ams_ht'] == true,
        trays: parseJsonList(json['trays'], LoadedSpoolTray.fromJson),
      );

  final int id;
  final bool isAmsHt;
  final List<LoadedSpoolTray> trays;
}

class LoadedSpoolPrinter {
  const LoadedSpoolPrinter({
    required this.id,
    required this.name,
    this.model,
    this.ams = const [],
    this.external = const [],
    this.externalHolders = 0,
  });

  factory LoadedSpoolPrinter.fromJson(Map<String, dynamic> json) =>
      LoadedSpoolPrinter(
        id: toInt(json['id']),
        name: toStringOrNull(json['name']) ?? '',
        model: toStringOrNull(json['model']),
        ams: parseJsonList(json['ams'], LoadedSpoolUnit.fromJson),
        external: parseJsonList(json['external'], LoadedSpoolTray.fromJson),
        externalHolders: toInt(json['external_holders']),
      );

  final int id;
  final String name;

  /// Short model code ("X1C"), the form the slicer's `@BBL` tags use.
  final String? model;
  final List<LoadedSpoolUnit> ams;

  /// Only the holders that have a spool in them.
  final List<LoadedSpoolTray> external;

  /// How many holders the printer has, loaded or not — two on a dual-nozzle
  /// printer, whose holders are then named left and right.
  final int externalHolders;
}
