import '../../core/models/slicer_pipeline.dart';
import '../../core/models/slicer_preset.dart';

/// Which slot of the preset catalog a [PresetRef] belongs to.
enum PresetSlot { printer, process, filament }

/// Resolve a stored [PresetRef] back to a catalog entry.
///
/// A miss yields a **synthetic** [SlicerPreset] carrying the ref, not null: the
/// ref is still what the slicer needs, so the form can mark the row unresolved
/// ([isUnresolved]) and submit it unchanged rather than silently rewriting the
/// user's pipeline. Misses are ordinary — a cloud tier that failed to load
/// empties whole slots for the session.
SlicerPreset resolvePresetRef(
  UnifiedPresets catalog,
  PresetRef ref,
  PresetSlot slot,
) {
  final options = switch (slot) {
    PresetSlot.printer => catalog.printers,
    PresetSlot.process => catalog.processes,
    PresetSlot.filament => catalog.filaments,
  };
  for (final p in options) {
    if (p.source == ref.source && p.id == ref.id) return p;
  }
  return SlicerPreset(source: ref.source, id: ref.id, name: '');
}

/// Whether [resolvePresetRef] had to invent this one — the catalog does not
/// know it. The empty name is the marker, and it is safe as one: the server
/// never returns a nameless preset in a tier listing.
bool isUnresolved(SlicerPreset preset) => preset.name.isEmpty;

/// The ref a preset goes back to the server as.
PresetRef refOf(SlicerPreset preset) =>
    PresetRef(source: preset.source, id: preset.id);
