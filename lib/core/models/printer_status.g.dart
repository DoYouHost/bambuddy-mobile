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
      progress: toDoubleOrNull(json['progress']),
      remainingTime: toIntOrNull(json['remaining_time']),
      layerNum: toIntOrNull(json['layer_num']),
      totalLayers: toIntOrNull(json['total_layers']),
      temperatures: _toTemperaturesOrNull(json['temperatures']),
      coverUrl: json['cover_url'] as String?,
      stgCur: toIntOrNull(json['stg_cur']),
      stgCurName: json['stg_cur_name'] as String?,
      coolingFanSpeed: toIntOrNull(json['cooling_fan_speed']),
      bigFan1Speed: toIntOrNull(json['big_fan1_speed']),
      bigFan2Speed: toIntOrNull(json['big_fan2_speed']),
      leftAuxFanSpeed: toIntOrNull(json['left_aux_fan_speed']),
      exhaustFanPresent: json['exhaust_fan_present'] as bool?,
      heatbreakFanSpeed: toIntOrNull(json['heatbreak_fan_speed']),
      speedLevel: toIntOrNull(json['speed_level']),
      chamberLight: json['chamber_light'] as bool?,
      airductMode: toIntOrNull(json['airduct_mode']),
      ams: _toAmsListOrNull(json['ams']),
      vtTray: _toTrayListOrNull(json['vt_tray']),
      trayNow: toIntOrNull(json['tray_now']),
      activeExtruder: toIntOrNull(json['active_extruder']),
      amsExtruderMap: _toExtruderMapOrNull(json['ams_extruder_map']),
      amsSwitchInlet: _toInletMapOrNull(json['ams_switch_inlet']),
      model: json['model'] as String?,
      wifiSignal: toIntOrNull(json['wifi_signal']),
      doorOpen: json['door_open'] as bool?,
      awaitingPlateClear: json['awaiting_plate_clear'] as bool?,
      hmsErrors: _toHmsListOrNull(json['hms_errors']),
      supportsDrying: json['supports_drying'] as bool?,
      nozzles: _toNozzleListOrNull(json['nozzles']),
      filaSwitch: _toFilaSwitchOrNull(json['fila_switch']),
      extruderSlots: _toExtruderSlotMapOrNull(json['extruder_slots']),
    );

AmsUnit _$AmsUnitFromJson(Map<String, dynamic> json) => AmsUnit(
  id: toIntOrNull(json['id']),
  humidity: toIntOrNull(json['humidity']),
  temp: toDoubleOrNull(json['temp']),
  trays: _toTrayListOrNull(json['tray']),
  isAmsHt: json['is_ams_ht'] as bool?,
  dryTime: toIntOrNull(json['dry_time']),
  dryStatus: toIntOrNull(json['dry_status']),
  moduleType: json['module_type'] as String?,
);

AmsTray _$AmsTrayFromJson(Map<String, dynamic> json) => AmsTray(
  id: toIntOrNull(json['id']),
  trayColor: json['tray_color'] as String?,
  trayType: json['tray_type'] as String?,
  traySubBrands: json['tray_sub_brands'] as String?,
  remain: toIntOrNull(json['remain']),
  trayInfoIdx: json['tray_info_idx'] as String?,
  caliIdx: toIntOrNull(json['cali_idx']),
  tagUid: json['tag_uid'] as String?,
  trayUuid: json['tray_uuid'] as String?,
);

NozzleInfo _$NozzleInfoFromJson(Map<String, dynamic> json) => NozzleInfo(
  nozzleType: json['nozzle_type'] as String?,
  nozzleDiameter: json['nozzle_diameter'] as String?,
);

FilaSwitch _$FilaSwitchFromJson(Map<String, dynamic> json) => FilaSwitch(
  installed: json['installed'] == null
      ? false
      : toBoolOrFalse(json['installed']),
  ready: json['ready'] == null ? false : toBoolOrFalse(json['ready']),
);

ExtruderSlot _$ExtruderSlotFromJson(Map<String, dynamic> json) => ExtruderSlot(
  amsId: toIntOrNull(json['ams_id']),
  slotId: toIntOrNull(json['slot_id']),
  hasFilament: json['has_filament'] == null
      ? false
      : toBoolOrFalse(json['has_filament']),
);

HmsError _$HmsErrorFromJson(Map<String, dynamic> json) => HmsError(
  code: _toCodeStringOrNull(json['code']),
  message: json['message'] as String?,
  severity: toIntOrNull(json['severity']),
  attr: toIntOrNull(json['attr']),
  module: toIntOrNull(json['module']),
  actions: json['actions'] == null
      ? const []
      : _toStringListOrEmpty(json['actions']),
  jobId: toStringOrNull(json['job_id']),
  fullCode: toStringOrNull(json['full_code']),
  description: toStringOrNull(json['description']),
);
