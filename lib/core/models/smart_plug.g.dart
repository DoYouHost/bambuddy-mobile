// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smart_plug.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SmartPlug _$SmartPlugFromJson(Map<String, dynamic> json) => SmartPlug(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String?,
  plugType: json['plug_type'] as String?,
  printerId: _toIntOrNull(json['printer_id']),
  enabled: json['enabled'] as bool?,
  lastState: json['last_state'] as String?,
  showOnPrinterCard: json['show_on_printer_card'] as bool?,
  showInSwitchbar: json['show_in_switchbar'] as bool?,
  controlsPrinterPower: json['controls_printer_power'] as bool?,
  haEntityId: json['ha_entity_id'] as String?,
  haPowerEntity: json['ha_power_entity'] as String?,
  mqttTopic: json['mqtt_topic'] as String?,
  mqttPowerTopic: json['mqtt_power_topic'] as String?,
  restPowerPath: json['rest_power_path'] as String?,
);

SmartPlugStatus _$SmartPlugStatusFromJson(Map<String, dynamic> json) =>
    SmartPlugStatus(
      state: json['state'] as String?,
      reachable: json['reachable'] as bool?,
      deviceName: json['device_name'] as String?,
      energy: json['energy'] == null
          ? null
          : SmartPlugEnergy.fromJson(json['energy'] as Map<String, dynamic>),
    );

SmartPlugEnergy _$SmartPlugEnergyFromJson(Map<String, dynamic> json) =>
    SmartPlugEnergy(
      power: _toDoubleOrNull(json['power']),
      voltage: _toDoubleOrNull(json['voltage']),
      current: _toDoubleOrNull(json['current']),
      today: _toDoubleOrNull(json['today']),
      yesterday: _toDoubleOrNull(json['yesterday']),
      total: _toDoubleOrNull(json['total']),
    );
