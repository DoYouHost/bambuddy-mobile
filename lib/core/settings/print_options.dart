import 'dart:convert';

/// The per-print toggles of the print form (bed levelling, calibrations,
/// inspection, timelapse), remembered between jobs.
///
/// Two different notions of "default" meet here, and they are deliberately not
/// the same thing:
///
/// * [QueueItem]'s field defaults mirror the SERVER's response model, so an item
///   that arrives missing a field still edits sanely. They must not move.
/// * [PrintOptions.initial] is what a NEW job starts from before the user has
///   ever configured one — everything the printer can do to get the print right,
///   minus the timelapse, which costs a recording nobody asked for.
///
/// After the first print the form starts from [SettingsRepository.loadPrintOptions]
/// instead: what the user chose last time is a better guess than any constant.
class PrintOptions {
  const PrintOptions({
    required this.bedLevelling,
    required this.flowCali,
    required this.vibrationCali,
    required this.layerInspect,
    required this.timelapse,
    required this.nozzleOffsetCali,
  });

  /// Starting point for a user who has never configured a print.
  static const initial = PrintOptions(
    bedLevelling: true,
    flowCali: true,
    vibrationCali: true,
    layerInspect: true,
    timelapse: false,
    nozzleOffsetCali: true,
  );

  final bool bedLevelling;
  final bool flowCali;
  final bool vibrationCali;
  final bool layerInspect;
  final bool timelapse;

  /// Dual-nozzle printers only. Remembered even while the form hides it, so it
  /// survives a job sliced for a single-nozzle model in between.
  final bool nozzleOffsetCali;

  String encode() => jsonEncode({
        'bed_levelling': bedLevelling,
        'flow_cali': flowCali,
        'vibration_cali': vibrationCali,
        'layer_inspect': layerInspect,
        'timelapse': timelapse,
        'nozzle_offset_cali': nozzleOffsetCali,
      });

  /// Lenient: a missing or unreadable entry falls back to [initial] field by
  /// field, so a stored blob written by an older build (or a half-written one)
  /// costs the user their remembered toggles, not a crash on the print screen.
  static PrintOptions decode(String? raw) {
    if (raw == null || raw.isEmpty) return initial;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return initial;
    }
    bool read(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    return PrintOptions(
      bedLevelling: read('bed_levelling', initial.bedLevelling),
      flowCali: read('flow_cali', initial.flowCali),
      vibrationCali: read('vibration_cali', initial.vibrationCali),
      layerInspect: read('layer_inspect', initial.layerInspect),
      timelapse: read('timelapse', initial.timelapse),
      nozzleOffsetCali: read('nozzle_offset_cali', initial.nozzleOffsetCali),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrintOptions &&
      other.bedLevelling == bedLevelling &&
      other.flowCali == flowCali &&
      other.vibrationCali == vibrationCali &&
      other.layerInspect == layerInspect &&
      other.timelapse == timelapse &&
      other.nozzleOffsetCali == nozzleOffsetCali;

  @override
  int get hashCode => Object.hash(bedLevelling, flowCali, vibrationCali,
      layerInspect, timelapse, nozzleOffsetCali);
}
