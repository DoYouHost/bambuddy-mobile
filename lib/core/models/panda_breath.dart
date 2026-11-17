import 'package:app_util/app_util.dart';

import 'json_utils.dart';
import 'value_equality.dart';

/// The server's ceiling for a Panda Breath target (`PandaBreathCommand`,
/// `le=60`), the same number the web's `PANDA_BREATH_MAX_TARGET_C` holds.
const pandaBreathMaxTargetC = 60;

/// The modes a Panda Breath takes, under the strings the server sends and
/// accepts (`PandaBreathCommand.mode`, `MODES` in `services/panda_breath.py`).
enum PandaBreathMode {
  auto('auto mode'),
  alwaysOn('power on'),
  drying('filament drying');

  const PandaBreathMode(this.wire);
  final String wire;
}

/// A BIQU Panda Breath chamber heater bound to a printer (`panda_breath`,
/// server #1466). Every reading is optional: the heater reports over MQTT a
/// piece at a time, and a field it has not sent yet is null on the server too.
///
/// [online] false is a heater the server knows but cannot reach (its broker
/// is down or it said "offline"); null is one that has not said either way,
/// which the web treats as usable, and so does [usable].
class PandaBreathState with ValueEquality {
  const PandaBreathState({
    required this.deviceId,
    this.online,
    this.chamberTemp,
    this.targetTemp,
    this.workOn,
    this.mode,
    this.dryingRunning,
    this.dryingRemainingMin,
  });

  final String deviceId;
  final bool? online;
  final double? chamberTemp;
  final double? targetTemp;
  final bool? workOn;

  /// The raw mode string: a firmware that adds a mode still shows it.
  final String? mode;
  final bool? dryingRunning;
  final double? dryingRemainingMin;

  PandaBreathMode? get knownMode =>
      enumByWire(PandaBreathMode.values, mode, (m) => m.wire);

  bool get usable => online != false;

  @override
  List<Object?> get props => [
    deviceId,
    online,
    chamberTemp,
    targetTemp,
    workOn,
    mode,
    dryingRunning,
    dryingRemainingMin,
  ];
}

/// `panda_breath` out of a status frame: null for the key's absence (a server
/// before #1466), for the JSON null the server sends when no heater is bound,
/// and for an object without a device id, which no command could reach.
PandaBreathState? pandaBreathFromJson(Object? value) {
  if (value is! Map) return null;
  final deviceId = toStringOrNull(value['device_id']);
  if (deviceId == null) return null;
  return PandaBreathState(
    deviceId: deviceId,
    online: _boolOrNull(value['online']),
    chamberTemp: toDoubleOrNull(value['chamber_temp']),
    targetTemp: toDoubleOrNull(value['target_temp']),
    workOn: _boolOrNull(value['work_on']),
    mode: toStringOrNull(value['mode']),
    dryingRunning: _boolOrNull(value['drying_running']),
    dryingRemainingMin: toDoubleOrNull(value['drying_remaining_min']),
  );
}

// Null stays null: an unreported `online` must not read as offline.
bool? _boolOrNull(Object? value) => value is bool ? value : null;
