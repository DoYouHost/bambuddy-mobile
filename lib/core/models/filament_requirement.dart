/// One filament slot a model needs, from `.../filament-requirements`
/// (`{filaments: [{slot_id, type, color, used_grams, used_meters,
/// used_in_plate}]}`). A multicolor 3MF yields several; the slice request maps
/// `filament_presets[i]` to slot `i+1` in order.
class FilamentRequirement {
  const FilamentRequirement({
    required this.slotId,
    this.type,
    this.color,
  });

  factory FilamentRequirement.fromJson(Map<String, dynamic> json) =>
      FilamentRequirement(
        slotId: (json['slot_id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String?,
        color: json['color'] as String?,
      );

  /// Parse the `filaments` list, skipping unused/unparseable slots.
  static List<FilamentRequirement> parseList(Map<String, dynamic> json) {
    final list = json['filaments'];
    if (list is! List) return const [];
    final out = <FilamentRequirement>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      out.add(FilamentRequirement.fromJson(item));
    }
    return out;
  }

  final int slotId;

  /// Material type (e.g. "PLA", "PETG"). Used to narrow the per-slot picker.
  final String? type;

  /// Required color `#RRGGBB` — shown as a swatch and used for auto-pick.
  final String? color;
}
