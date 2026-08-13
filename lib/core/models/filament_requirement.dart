/// One filament slot a model needs, from `.../filament-requirements`
/// (`{filaments: [{slot_id, type, color, used_grams, used_meters,
/// used_in_plate}]}`). A multicolor 3MF yields several; the slice request maps
/// `filament_presets[i]` to slot `i+1` in order.
class FilamentRequirement {
  const FilamentRequirement({
    required this.slotId,
    this.type,
    this.color,
    this.usedInPlate = true,
  });

  factory FilamentRequirement.fromJson(Map<String, dynamic> json) =>
      FilamentRequirement(
        slotId: (json['slot_id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String?,
        color: json['color'] as String?,
        // Absent means we cannot tell, and "used" is the safe reading: it leaves
        // the slot offered rather than implying the plate ignores it.
        usedInPlate: json['used_in_plate'] as bool? ?? true,
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

  /// Whether the plate's G-code actually consumes this slot.
  ///
  /// Only meaningful across the whole list: when the server's preview slice
  /// yields nothing it flags **every** slot as used (`fallback_all_used`,
  /// `routes/library.py`), so all-true means either "all really used" or "could
  /// not tell". Use [anyUnused] before telling the user anything.
  final bool usedInPlate;
}

/// Whether the server actually discriminated between used and unused slots.
///
/// False when every slot is flagged used, which is also what its own fallback
/// produces — so marking anything then would claim knowledge nobody has.
bool anyUnused(List<FilamentRequirement> requirements) =>
    requirements.any((r) => !r.usedInPlate);
