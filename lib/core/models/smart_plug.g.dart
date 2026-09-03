// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smart_plug.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SmartPlug _$SmartPlugFromJson(Map<String, dynamic> json) => SmartPlug(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String?,
  plugType: json['plug_type'] as String?,
  printerId: toIntOrNull(json['printer_id']),
  enabled: json['enabled'] as bool?,
  lastState: json['last_state'] as String?,
  showOnPrinterCard: json['show_on_printer_card'] as bool?,
  showInSwitchbar: json['show_in_switchbar'] as bool?,
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
      power: toDoubleOrNull(json['power']),
      voltage: toDoubleOrNull(json['voltage']),
      current: toDoubleOrNull(json['current']),
      today: toDoubleOrNull(json['today']),
      yesterday: toDoubleOrNull(json['yesterday']),
      total: toDoubleOrNull(json['total']),
    );
