import 'dart:convert';

import '../models/calibration_option.dart';

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
  ///
  /// The three calibrations start [CalibrationOption.on] rather than
  /// [CalibrationOption.auto]: `on` is what they meant when they were booleans,
  /// and a server old enough to still use booleans has nowhere to put `auto`.
  /// A user who wants the printer to decide picks it.
  static const initial = PrintOptions(
    bedLevelling: CalibrationOption.on,
    flowCali: CalibrationOption.on,
    vibrationCali: true,
    layerInspect: true,
    timelapse: false,
    nozzleOffsetCali: CalibrationOption.on,
  );

  final CalibrationOption bedLevelling;
  final CalibrationOption flowCali;
  final bool vibrationCali;
  final bool layerInspect;
  final bool timelapse;

  /// Dual-nozzle printers only. Remembered even while the form hides it, so it
  /// survives a job sliced for a single-nozzle model in between.
  final CalibrationOption nozzleOffsetCali;

  String encode() => jsonEncode({
        'bed_levelling': bedLevelling.name,
        'flow_cali': flowCali.name,
        'vibration_cali': vibrationCali,
        'layer_inspect': layerInspect,
        'timelapse': timelapse,
        'nozzle_offset_cali': nozzleOffsetCali.name,
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
    // Blobs written before the tri-state migration hold booleans on these three
    // keys; [calibrationOrNull] reads both spellings, so a user's remembered
    // toggles survive the upgrade instead of resetting to [initial].
    CalibrationOption readCali(String key, CalibrationOption fallback) =>
        calibrationOrNull(map[key]) ?? fallback;
    return PrintOptions(
      bedLevelling: readCali('bed_levelling', initial.bedLevelling),
      flowCali: readCali('flow_cali', initial.flowCali),
      vibrationCali: read('vibration_cali', initial.vibrationCali),
      layerInspect: read('layer_inspect', initial.layerInspect),
      timelapse: read('timelapse', initial.timelapse),
      nozzleOffsetCali:
          readCali('nozzle_offset_cali', initial.nozzleOffsetCali),
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
