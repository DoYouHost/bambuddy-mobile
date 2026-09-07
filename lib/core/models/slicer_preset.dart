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

/// Effective values of one process preset, `inherits:` chain already flattened
/// by the slicer sidecar (`GET /slicer/preset-values`, server 1.2.6+).
///
/// Without these the override panel can only show the option schema's
/// compiled-in defaults, so a preset that sets a 0.42 mm line width would
/// display the C++ default of 0 and every field would read as "modified".
///
/// [resolved] false is a normal answer, not an error: the endpoint reports
/// failure in-band so the panel stays usable with schema defaults. [reason] is
/// what makes that actionable — an install pulls its sidecar as
/// `SIDECAR_TAG:-latest` regardless of its own release channel, so a sidecar
/// older than the endpoint is the common cause and the fix is to pull a newer
/// image.
class PresetValues {
  const PresetValues({
    required this.resolved,
    this.values = const {},
    this.reason = '',
  });

  factory PresetValues.fromJson(Map<String, dynamic> json) => PresetValues(
    resolved: json['resolved'] == true,
    values: (json['values'] as Map?)?.cast<String, dynamic>() ?? const {},
    reason: json['reason'] as String? ?? '',
  );

  /// Nothing known — the panel falls back to the schema's own defaults.
  static const unresolved = PresetValues(resolved: false);

  final bool resolved;

  /// Raw `{option_key: value}` as the slicer stores them; values may be
  /// strings, numbers, booleans or lists depending on the option's type.
  final Map<String, dynamic> values;

  /// Verbatim; [cause] is the classified form.
  final String reason;

  /// Why the values are missing, as one of the four causes the server
  /// deliberately keeps apart (`services/slicer_api.py::ResolvedProfile`)
  /// so the panel can say something actionable instead of one generic failure.
  PresetValuesCause get cause => switch (reason) {
    'ok' => PresetValuesCause.ok,
    'sidecar_outdated' => PresetValuesCause.sidecarOutdated,
    'sidecar_unavailable' => PresetValuesCause.sidecarUnavailable,
    'not_configured' => PresetValuesCause.notConfigured,
    'preset_unresolved' => PresetValuesCause.presetUnresolved,
    _ => PresetValuesCause.unknown,
  };
}

/// Classified [PresetValues.reason]. Unknown values keep the panel working with
/// schema defaults and no explanation, rather than mapping to a wrong one.
enum PresetValuesCause {
  ok,

  /// The endpoint exists but the sidecar behind it predates it — the common
  /// case, because an install pulls `SIDECAR_TAG:-latest` independently of its
  /// own release channel. Fixed by pulling a newer sidecar image.
  sidecarOutdated,

  /// Sidecar unreachable right now.
  sidecarUnavailable,

  /// No slicer API URL configured server-side.
  notConfigured,

  /// The preset itself could not be resolved for this caller.
  presetUnresolved,
  unknown,
}
