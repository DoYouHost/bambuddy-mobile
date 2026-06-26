/// Reference data for spool form (Phase 2): core weight catalog, color database,
/// filament profiles. All from native `/inventory/*` and `/filament-catalog/*`.
/// Defensive parsing (tolerant types, unknown keys ignored), like other inventory models.
library;

/// Spool core weight catalog entry (`CatalogEntryResponse`) — "Empty Spool Weight"
/// field. Selection sets `core_weight` + `core_weight_catalog_id`.
class CoreWeightEntry {
  const CoreWeightEntry({
    required this.id,
    required this.name,
    required this.weight,
    this.isDefault = false,
  });

  factory CoreWeightEntry.fromJson(Map<String, dynamic> json) => CoreWeightEntry(
        id: _toInt(json['id']) ?? -1,
        name: _str(json['name']) ?? '?',
        weight: _toInt(json['weight']) ?? 0,
        isDefault: json['is_default'] == true,
      );

  final int id;
  final String name;
  final int weight;
  final bool isDefault;

  /// Dropdown label: "Bambu Lab – Plastic Low Temp · 250 g".
  String get label => '$name · $weight g';
}

/// Color database entry (`ColorEntryResponse`) — color picker. Selection sets
/// `rgba`/`color_name` (+ optionally `extra_colors`/`effect_type`).
class ColorEntry {
  const ColorEntry({
    required this.id,
    required this.manufacturer,
    required this.colorName,
    required this.hexColor,
    this.material,
    this.isDefault = false,
    this.extraColors,
    this.effectType,
  });

  factory ColorEntry.fromJson(Map<String, dynamic> json) => ColorEntry(
        id: _toInt(json['id']) ?? -1,
        manufacturer: _str(json['manufacturer']) ?? '',
        colorName: _str(json['color_name']) ?? '',
        hexColor: _str(json['hex_color']) ?? '',
        material: _str(json['material']),
        isDefault: json['is_default'] == true,
        extraColors: _str(json['extra_colors']),
        effectType: _str(json['effect_type']),
      );

  final int id;
  final String manufacturer;
  final String colorName;

  /// Color hex, usually `#RRGGBB` or `RRGGBBAA`.
  final String hexColor;
  final String? material;
  final bool isDefault;
  final String? extraColors;
  final String? effectType;
}

/// Filament profile from catalog (`FilamentResponse`) — source of material/brand
/// options and prefill (color, cost, temps) on preset selection.
class FilamentPreset {
  const FilamentPreset({
    required this.id,
    required this.name,
    required this.type,
    this.brand,
    this.colorHex,
    this.costPerKg,
    this.spoolWeightG,
    this.printTempMin,
    this.printTempMax,
  });

  factory FilamentPreset.fromJson(Map<String, dynamic> json) => FilamentPreset(
        id: _toInt(json['id']) ?? -1,
        name: _str(json['name']) ?? '',
        type: _str(json['type']) ?? '',
        brand: _str(json['brand']),
        colorHex: _str(json['color_hex']),
        costPerKg: _toDouble(json['cost_per_kg']),
        spoolWeightG: _toDouble(json['spool_weight_g']),
        printTempMin: _toInt(json['print_temp_min']),
        printTempMax: _toInt(json['print_temp_max']),
      );

  final int id;
  final String name;

  /// Material (PLA/PETG/…) — in API field `type`.
  final String type;
  final String? brand;
  final String? colorHex;
  final double? costPerKg;
  final double? spoolWeightG;
  final int? printTempMin;
  final int? printTempMax;
}

String? _str(dynamic v) {
  if (v is String) return v.isEmpty ? null : v;
  return null;
}

int? _toInt(dynamic v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

double? _toDouble(dynamic v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
