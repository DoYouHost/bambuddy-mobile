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
    );
