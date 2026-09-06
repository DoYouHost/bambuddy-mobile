import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'smart_plug.g.dart';

/// Smart plug configuration from `GET /smart-plugs/` and
/// `GET /smart-plugs/by-printer/{id}` (SmartPlugResponse). Parse only what
/// dashboard UI uses — printer assignment, visibility, last known state; rest
/// (MQTT/REST/HA/schedules) stays on server. Defensive: all except `id` nullable,
/// unknown keys ignored.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlug {
  const SmartPlug({
    required this.id,
    this.name,
    this.plugType,
    this.printerId,
    this.enabled,
    this.lastState,
    this.showOnPrinterCard,
    this.showInSwitchbar,
    this.controlsPrinterPower,
    this.haEntityId,
    this.haPowerEntity,
    this.mqttTopic,
    this.mqttPowerTopic,
    this.restPowerPath,
  });

  factory SmartPlug.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugFromJson(json);

  final int id;

  final String? name;

  /// `tasmota` | `homeassistant` | `mqtt` | `rest` — raw, not enum-backed.
  final String? plugType;

  /// Printer this plug is assigned to (null = unassigned).
  @JsonKey(fromJson: toIntOrNull)
  final int? printerId;

  final bool? enabled;

  /// Last known state from server (e.g. “ON”/”OFF”) — quick fallback before
  /// fetching live [SmartPlugStatus].
  final String? lastState;

  /// Whether plug should show on printer card (server preference).
  final bool? showOnPrinterCard;

  final bool? showInSwitchbar;

  /// Whether this plug really feeds the printer, as opposed to an accessory
  /// (filter fan, lights) linked to it only to follow the print cycle. Servers
  /// older than the flag omit it; the server's own default is “yes”.
  final bool? controlsPrinterPower;

  /// Home Assistant entity (`switch.` / `light.` / `input_boolean.` / `script.`).
  final String? haEntityId;

  /// HA sensor the server reads watts from, when the switch entity has none.
  final String? haPowerEntity;

  /// Legacy MQTT power topic, kept by the server for backward compatibility.
  final String? mqttTopic;

  final String? mqttPowerTopic;

  final String? restPowerPath;

  /// Whether plug is fit to show on printer card: enabled and marked for display
  /// (both fields default to “yes” if server omits).
  bool get visibleOnCard => (enabled ?? true) && (showOnPrinterCard ?? true);

  /// A Home Assistant script: it can be run, not switched.
  bool get isHaScript =>
      plugType == 'homeassistant' &&
      (haEntityId?.startsWith('script.') ?? false);

  /// An MQTT plug: bambuddy subscribes to it and never publishes, so
  /// `POST /smart-plugs/{id}/control` rejects it with 400
  /// (`routes/smart_plugs.py::control_smart_plug`). Nothing here can switch it.
  bool get isMonitorOnly => plugType == 'mqtt';

  /// Whether the card's on/off button makes sense on this plug. A script is
  /// still *controllable* — `script.turn_on` runs it — but it is not a switch,
  /// so it only takes the power row when nothing better is assigned.
  bool get canBeSwitched => !isHaScript && !isMonitorOnly;

  /// Whether the plug is *configured* with somewhere to read watts from — read
  /// from the config, never measured, because this runs on every card build.
  /// Approximate in both directions, which is why it only breaks a tie between
  /// otherwise equal plugs (`routes/smart_plugs.py::_reports_power`).
  bool get reportsPower => switch (plugType) {
    'homeassistant' => (haPowerEntity ?? '').isNotEmpty,
    'mqtt' => (mqttPowerTopic ?? '').isNotEmpty || (mqttTopic ?? '').isNotEmpty,
    'rest' => (restPowerPath ?? '').isNotEmpty,
    // Tasmota, whose firmware reports power when the hardware has it — and
    // the server's own default for a plug with no type.
    _ => true,
  };

  /// Demerits as the printer's main power plug, most significant first — the
  /// port of the server's `routes/smart_plugs.py::_main_plug_rank`. The
  /// card's power button has to land on the plug that feeds the printer, not on
  /// an exhaust fan, so: switchable at all, then the printer-power flag, then
  /// not disabled, then not hidden, then reports watts. `true` means “worse”,
  /// like the server's tuple of `not …`.
  List<bool> get _mainPlugDemerits => [
    !canBeSwitched,
    !(controlsPrinterPower ?? true),
    !(enabled ?? true),
    !(showOnPrinterCard ?? true),
    !reportsPower,
  ];

  /// Comparator over [_mainPlugDemerits]: negative when [a] is the better main
  /// plug. Ties fall back to the lowest id, so the answer never depends on the
  /// order the server happened to list the plugs in.
  static int compareAsMainPlug(SmartPlug a, SmartPlug b) {
    final left = a._mainPlugDemerits;
    final right = b._mainPlugDemerits;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return left[i] ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  }

  /// State from config (fallback, before live status available).
  bool? get lastIsOn => _onOffOrNull(lastState);
}

/// Live plug status from `GET /smart-plugs/{id}/status` (SmartPlugStatus):
/// on/off state, reachability, energy measurement. Source of live power.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlugStatus {
  const SmartPlugStatus({
    this.state,
    this.reachable,
    this.deviceName,
    this.energy,
  });

  factory SmartPlugStatus.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugStatusFromJson(json);

  /// Raw state from server (e.g. "ON"/"OFF"); null if unknown/unreachable.
  final String? state;

  /// Whether plug responds (false = power/state stale).
  final bool? reachable;

  final String? deviceName;

  final SmartPlugEnergy? energy;

  bool get isReachable => reachable ?? true;

  bool? get isOn => _onOffOrNull(state);

  /// Current active power in watts — null if plug doesn't measure or unreachable.
  double? get powerW => isReachable ? energy?.power : null;
}

/// Energy measurement from plug (SmartPlugEnergy). All optional — not every
/// plug type reports every parameter.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlugEnergy {
  const SmartPlugEnergy({
    this.power,
    this.voltage,
    this.current,
    this.today,
    this.yesterday,
    this.total,
  });

  factory SmartPlugEnergy.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugEnergyFromJson(json);

  /// Active power [W].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? power;

  /// Voltage [V].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? voltage;

  /// Current [A].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? current;

  /// Energy today [kWh].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? today;

  /// Energy yesterday [kWh].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? yesterday;

  /// Total energy (meter) [kWh].
  @JsonKey(fromJson: toDoubleOrNull)
  final double? total;
}

/// The wire vocabulary for a plug's state, on both `last_state` (config) and
/// `state` (live status): each plug type words it its own way, so a Tasmota
/// `ON`, an MQTT `1` and a REST `true` all have to read as the same thing.
/// Anything else — including an unreachable plug's `null` — is “unknown”, which
/// the UI shows as off but never sends as a command.
bool? _onOffOrNull(String? value) => switch (value?.toUpperCase()) {
  'ON' || 'TRUE' || '1' => true,
  'OFF' || 'FALSE' || '0' => false,
  _ => null,
};
