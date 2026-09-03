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

  /// Whether plug is fit to show on printer card: enabled and marked for display
  /// (both fields default to “yes” if server omits).
  bool get visibleOnCard =>
      (enabled ?? true) && (showOnPrinterCard ?? true);

  /// State from config (fallback, before live status available).
  bool? get lastIsOn => switch (lastState?.toUpperCase()) {
        'ON' || 'TRUE' || '1' => true,
        'OFF' || 'FALSE' || '0' => false,
        _ => null,
      };
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

  bool? get isOn => switch (state?.toUpperCase()) {
        'ON' || 'TRUE' || '1' => true,
        'OFF' || 'FALSE' || '0' => false,
        _ => null,
      };

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

