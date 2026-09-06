import 'json_utils.dart';

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
    this.groupId,
    this.group,
  });

  factory FilamentRequirement.fromJson(
    Map<String, dynamic> json,
  ) => FilamentRequirement(
    slotId: toIntOrNull(json['slot_id']) ?? 0,
    type: json['type'] as String?,
    color: json['color'] as String?,
    // Absent means we cannot tell, and "used" is the safe reading: it leaves
    // the slot offered rather than implying the plate ignores it.
    usedInPlate: json['used_in_plate'] as bool? ?? true,
    groupId: toIntOrNull(json['group_id']),
    group: parseJsonObjectOrNull(json['group'], RackGroup.fromJson),
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

  /// The slicer's logical nozzle this slot belongs to, on a plate sliced for a
  /// nozzle-rack printer (`group_id`). Null everywhere else, and on every
  /// server that does not annotate the field yet.
  ///
  /// Groups, not slots, are the unit of a rack pick: two slots in one group
  /// share a hotend and cannot be pointed at different positions.
  final int? groupId;

  /// What [groupId]'s hotend has to be, or null when the file describes no
  /// rack. Repeated on every slot of the group, identically — the server sends
  /// the group table per filament rather than as a table of its own.
  final RackGroup? group;

  /// Whether the plate's G-code actually consumes this slot.
  ///
  /// Only meaningful across the whole list: when the server's preview slice
  /// yields nothing it flags **every** slot as used (`fallback_all_used`,
  /// `routes/library.py`), so all-true means either "all really used" or "could
  /// not tell". Use [anyUnused] before telling the user anything.
  final bool usedInPlate;
}

/// One filament group's hotend requirement on a nozzle-rack plate, from a
/// filament's `group` object (server `RackGroup.group_dicts`).
class RackGroup {
  const RackGroup({
    this.onRack = false,
    this.nozzleDiameter = '',
    this.volumeType = '',
    this.filamentColor = '',
  });

  factory RackGroup.fromJson(Map<String, dynamic> json) => RackGroup(
    onRack: json['on_rack'] == true,
    nozzleDiameter: (json['nozzle_diameter'] as String?)?.trim() ?? '',
    volumeType: (json['volume_type'] as String?)?.trim() ?? '',
    filamentColor: (json['filament_color'] as String?)?.trim() ?? '',
  );

  /// Whether this group prints from the rack. A group on the fixed hotend needs
  /// no position and must not be offered one.
  final bool onRack;

  /// Nozzle diameter the slice was prepared for, as the slicer spells it
  /// (`0.40`). Empty when the file does not say, which no position can match.
  final String nozzleDiameter;

  /// Flow type as a name — `Standard` / `High Flow`. The printer answers the
  /// same property as a code (`HS…` / `HH…`).
  final String volumeType;

  /// Colour the group prints in, `#RRGGBB`. Only a hint: the server prefers a
  /// position already loaded with it when it assigns positions itself.
  final String filamentColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RackGroup &&
          other.onRack == onRack &&
          other.nozzleDiameter == nozzleDiameter &&
          other.volumeType == volumeType &&
          other.filamentColor == filamentColor;

  @override
  int get hashCode =>
      Object.hash(onRack, nozzleDiameter, volumeType, filamentColor);
}

/// Whether the server actually discriminated between used and unused slots.
///
/// False when every slot is flagged used, which is also what its own fallback
/// produces — so marking anything then would claim knowledge nobody has.
bool anyUnused(List<FilamentRequirement> requirements) =>
    requirements.any((r) => !r.usedInPlate);
