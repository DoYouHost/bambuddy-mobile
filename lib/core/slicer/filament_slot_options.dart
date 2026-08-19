import '../models/process_option.dart';

/// The options whose integer value names a filament slot: 0 = "no specific
/// filament, use whatever the region already prints with", 1..N = a project
/// slot.
///
/// The server panel's own set, copied rather than widened
/// (`frontend/src/components/SlicerSettingsPanel.tsx::FILAMENT_SLOT_OPTIONS`).
/// `wipe_tower_filament` holds the same kind of integer and is deliberately not
/// among them: its 0 means "whichever is available, preferring non-soluble", so
/// offering it as "Default" would name a behaviour the slicer does not have.
const filamentSlotOptionKeys = <String>{
  'support_filament',
  'support_interface_filament',
  'outer_wall_filament_id',
  'inner_wall_filament_id',
  'top_surface_filament_id',
  'bottom_surface_filament_id',
  'internal_solid_filament_id',
  'sparse_infill_filament_id',
};

/// One project slot as the slice form has it, for labelling the pickers above.
class FilamentSlotChoice {
  const FilamentSlotChoice({
    required this.slot,
    required this.label,
    this.unused = false,
  });

  /// 1-based, matching the integer the slicer stores.
  final int slot;

  /// The picked preset's name, or whatever names the slot until one is picked.
  final String label;

  /// The plate's G-code does not consume this slot. Only ever true when the
  /// server really told used from unused — see `anyUnused`.
  final bool unused;
}

/// Whether [option] should offer the slice form's slots instead of a number
/// field. The type is checked too: should a re-vendor turn one of these into
/// something other than a plain int, the generic control for whatever it became
/// beats a slot dropdown over a value that is no longer a slot.
bool namesFilamentSlot(ProcessOption option) =>
    option.type == OptionType.coInt &&
    filamentSlotOptionKeys.contains(option.key);
