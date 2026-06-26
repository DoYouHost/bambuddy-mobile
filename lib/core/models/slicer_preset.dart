/// Slicer presets from `GET /slicer/presets` (`UnifiedPresetsResponse`) — the
/// options shown in the slice modal's printer/process/filament dropdowns.
///
/// Presets come in four tiers (priority order `local > orca_cloud > cloud >
/// standard`); a slice request references one per slot via `{source, id}`.
/// Note: in practice the cloud/standard tiers leave `filament_type` and
/// `compatible_printers` null, so "owned filament" filtering has to fall back
/// to name matching (see `SliceSheet`).
library;

/// One preset option for a single slot (printer / process / filament).
class SlicerPreset {
  const SlicerPreset({
    required this.source,
    required this.id,
    required this.name,
    this.filamentType,
    this.filamentColour,
    this.compatiblePrinters,
  });

  factory SlicerPreset.fromJson(Map<String, dynamic> json) => SlicerPreset(
        source: json['source'] as String? ?? 'standard',
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        filamentType: json['filament_type'] as String?,
        filamentColour: json['filament_colour'] as String?,
        compatiblePrinters: (json['compatible_printers'] as List?)
            ?.whereType<String>()
            .toList(),
      );

  /// One of `local`, `orca_cloud`, `cloud`, `standard`.
  final String source;

  /// Tier-specific id: local DB row id, cloud setting id, or standard name.
  final String id;
  final String name;
  final String? filamentType;
  final String? filamentColour;
  final List<String>? compatiblePrinters;

  bool get isLocal => source == 'local';

  /// Source-aware `PresetRef` body for the slice request.
  Map<String, String> toRef() => {'source': source, 'id': id};
}

/// All preset options grouped by slot, concatenated across tiers in priority
/// order (local first) so a single list can drive a dropdown.
class UnifiedPresets {
  const UnifiedPresets({
    required this.printers,
    required this.processes,
    required this.filaments,
    this.cloudStatus,
  });

  factory UnifiedPresets.fromJson(Map<String, dynamic> json) {
    List<SlicerPreset> slot(String slot) {
      final out = <SlicerPreset>[];
      // Priority order drives the visual order — local presets come first.
      for (final tier in const ['local', 'orca_cloud', 'cloud', 'standard']) {
        final tierMap = json[tier];
        if (tierMap is! Map<String, dynamic>) continue;
        final list = tierMap[slot];
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          out.add(SlicerPreset.fromJson(item));
        }
      }
      return out;
    }

    return UnifiedPresets(
      printers: slot('printer'),
      processes: slot('process'),
      filaments: slot('filament'),
      cloudStatus: json['cloud_status'] as String?,
    );
  }

  final List<SlicerPreset> printers;
  final List<SlicerPreset> processes;
  final List<SlicerPreset> filaments;

  /// `ok` / `not_authenticated` / `expired` / `unreachable` — lets the UI
  /// explain an empty cloud tier.
  final String? cloudStatus;
}
