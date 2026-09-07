import 'json_utils.dart';

/// One pressure-advance calibration stored **on the printer**.
///
/// The printer keeps a small table of these (~20 slots) indexed by [slotId],
/// which is the `cali_idx` the configure call selects. Everything here is read
/// back over MQTT by the server; the app never writes one.
class KProfile {
  const KProfile({
    required this.slotId,
    required this.name,
    required this.kValue,
    this.extruderId = 0,
    this.nozzleDiameter = '',
    this.filamentId = '',
    this.settingId,
  });

  factory KProfile.fromJson(Map<String, dynamic> json) => KProfile(
    slotId: toIntOrNull(json['slot_id']) ?? 0,
    name: toStringOrNull(json['name']) ?? '',
    // A string on the wire ("0.020000"), and kept as one: it is half of the
    // key the printer's duplicate rows are folded on, and re-formatting a
    // number would make two spellings of the same value look different.
    kValue: toStringOrNull(json['k_value']) ?? '0',
    extruderId: toIntOrNull(json['extruder_id']) ?? 0,
    nozzleDiameter: toStringOrNull(json['nozzle_diameter']) ?? '',
    filamentId: toStringOrNull(json['filament_id']) ?? '',
    settingId: toStringOrNull(json['setting_id']),
  );

  /// Storage slot on the printer — the `cali_idx` that selects this profile.
  /// Zero means "the default profile", which is not one the user picked.
  final int slotId;

  /// 0 or 1 on a dual-nozzle printer.
  final int extruderId;

  final String nozzleDiameter;

  /// Bambu filament id the profile was calibrated under.
  final String filamentId;

  /// Whatever the user called it in the slicer.
  final String name;

  /// Pressure advance as the printer spells it, e.g. `0.020000`.
  final String kValue;

  final String? settingId;

  double get k => double.tryParse(kValue) ?? 0;

  /// Identity for the picker and for folding duplicates.
  ///
  /// A multi-nozzle printer reports the same calibration once per nozzle, and
  /// the two rows differ only in [slotId] and [extruderId] — so neither of
  /// those can be the key. The filament id is in it where the web's key is not:
  /// two calibrations for *different* filaments that happen to share a name and
  /// a value are two profiles, and folding them makes the second unselectable.
  /// The duplicate rows this is meant to fold agree on the id, so they still do.
  String get optionId => '$name|$kValue|$filamentId';
}
