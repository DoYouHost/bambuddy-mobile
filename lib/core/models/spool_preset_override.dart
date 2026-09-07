import 'json_utils.dart';

/// One per-printer-model override of a spool's slicer preset
/// (`GET/PUT /inventory/spools/{id}/filament-presets`, server 1.2.6).
///
/// `Spool.slicerFilament` is a single, printer-agnostic answer, and a cloud or
/// Orca preset is bound to a model (`@BBL X1C`) — so the same spool assigned to
/// an H2C configures that slot with a preset the machine has no profile for.
/// This is the exception table the server consults first when it fills a slot;
/// a spool with no row here behaves exactly as it always did.
///
/// The server's cascade is `(model, diameter)` → `(model, "")` → the spool's
/// own preset, so [nozzleDiameter] is part of the key rather than a detail.
/// The app writes the `""` level, which the route documents as the form for a
/// client that wants one value to cover a whole model; a row with a concrete
/// diameter is one the web wrote, and is carried through untouched.
class SpoolPresetOverride {
  const SpoolPresetOverride({
    required this.printerModel,
    this.nozzleDiameter = '',
    this.slicerFilament,
    this.slicerFilamentName,
  });

  factory SpoolPresetOverride.fromJson(Map<String, dynamic> json) =>
      SpoolPresetOverride(
        printerModel: toStringOrNull(json['printer_model']) ?? '',
        nozzleDiameter: toStringOrNull(json['nozzle_diameter']) ?? '',
        slicerFilament: toStringOrNull(json['slicer_filament']),
        slicerFilamentName: toStringOrNull(json['slicer_filament_name']),
      );

  /// The printer's own model string (`X1C`, `H2D`), matched by the server for
  /// equality against what the printer reported — never a display name, and
  /// never case-folded on the way out.
  final String printerModel;

  /// The bare decimal the printer reports (`0.4`), or `''` for "any nozzle of
  /// this model". Empty rather than null because a UNIQUE constraint counts
  /// two NULLs as distinct, which would let the same row be stored twice.
  final String nozzleDiameter;

  /// Preset id and its human name, the same pair the spool itself carries.
  /// Both null is a deliberate "use no preset here", which the server honours
  /// instead of falling back to the spool's own value.
  final String? slicerFilament;
  final String? slicerFilamentName;

  /// The `(model, diameter)` pair the server keys a row on, as one string.
  String get key => '$printerModel|$nozzleDiameter';

  /// Write shape (`SpoolFilamentPresetBase`). `id`, `spool_id` and
  /// `created_at` are read-only and the route rejects neither — they are simply
  /// not part of what it accepts.
  Map<String, dynamic> toJson() => {
    'printer_model': printerModel,
    'nozzle_diameter': nozzleDiameter,
    'slicer_filament': slicerFilament,
    'slicer_filament_name': slicerFilamentName,
  };

  SpoolPresetOverride withPreset(String? filament, String? name) =>
      SpoolPresetOverride(
        printerModel: printerModel,
        nozzleDiameter: nozzleDiameter,
        slicerFilament: filament,
        slicerFilamentName: name,
      );
}
