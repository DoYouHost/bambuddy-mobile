// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'printer_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PrinterStatus _$PrinterStatusFromJson(Map<String, dynamic> json) =>
    PrinterStatus(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String?,
      connected: json['connected'] as bool?,
      state: json['state'] as String?,
      currentPrint: json['current_print'] as String?,
      gcodeFile: json['gcode_file'] as String?,
      progress: _toDoubleOrNull(json['progress']),
      remainingTime: _toIntOrNull(json['remaining_time']),
      layerNum: _toIntOrNull(json['layer_num']),
      totalLayers: _toIntOrNull(json['total_layers']),
      temperatures: _toTemperaturesOrNull(json['temperatures']),
      coverUrl: json['cover_url'] as String?,
      stgCurName: json['stg_cur_name'] as String?,
      coolingFanSpeed: _toIntOrNull(json['cooling_fan_speed']),
      bigFan1Speed: _toIntOrNull(json['big_fan1_speed']),
      bigFan2Speed: _toIntOrNull(json['big_fan2_speed']),
      leftAuxFanSpeed: _toIntOrNull(json['left_aux_fan_speed']),
      exhaustFanPresent: json['exhaust_fan_present'] as bool?,
      heatbreakFanSpeed: _toIntOrNull(json['heatbreak_fan_speed']),
      speedLevel: _toIntOrNull(json['speed_level']),
      chamberLight: json['chamber_light'] as bool?,
      airductMode: _toIntOrNull(json['airduct_mode']),
      ams: _toAmsListOrNull(json['ams']),
      vtTray: _toTrayListOrNull(json['vt_tray']),
      trayNow: _toIntOrNull(json['tray_now']),
      activeExtruder: _toIntOrNull(json['active_extruder']),
      amsExtruderMap: _toExtruderMapOrNull(json['ams_extruder_map']),
      model: json['model'] as String?,
      wifiSignal: _toIntOrNull(json['wifi_signal']),
      doorOpen: json['door_open'] as bool?,
      awaitingPlateClear: json['awaiting_plate_clear'] as bool?,
      hmsErrors: _toHmsListOrNull(json['hms_errors']),
      supportsDrying: json['supports_drying'] as bool?,
      nozzles: _toNozzleListOrNull(json['nozzles']),
    );

AmsUnit _$AmsUnitFromJson(Map<String, dynamic> json) => AmsUnit(
  id: _toIntOrNull(json['id']),
  humidity: _toIntOrNull(json['humidity']),
  temp: _toDoubleOrNull(json['temp']),
  trays: _toTrayListOrNull(json['tray']),
  isAmsHt: json['is_ams_ht'] as bool?,
  dryTime: _toIntOrNull(json['dry_time']),
  dryStatus: _toIntOrNull(json['dry_status']),
  moduleType: json['module_type'] as String?,
);

AmsTray _$AmsTrayFromJson(Map<String, dynamic> json) => AmsTray(
  id: _toIntOrNull(json['id']),
  trayColor: json['tray_color'] as String?,
  trayType: json['tray_type'] as String?,
  traySubBrands: json['tray_sub_brands'] as String?,
  remain: _toIntOrNull(json['remain']),
  trayInfoIdx: json['tray_info_idx'] as String?,
  caliIdx: _toIntOrNull(json['cali_idx']),
);

NozzleInfo _$NozzleInfoFromJson(Map<String, dynamic> json) => NozzleInfo(
  nozzleType: json['nozzle_type'] as String?,
  nozzleDiameter: json['nozzle_diameter'] as String?,
);

HmsError _$HmsErrorFromJson(Map<String, dynamic> json) => HmsError(
  code: _toCodeStringOrNull(json['code']),
  message: json['message'] as String?,
  severity: _toIntOrNull(json['severity']),
  attr: _toIntOrNull(json['attr']),
  module: _toIntOrNull(json['module']),
  actions: json['actions'] == null
      ? const []
      : _toStringListOrEmpty(json['actions']),
  jobId: _toNonBlankStringOrNull(json['job_id']),
  fullCode: _toNonBlankStringOrNull(json['full_code']),
);
