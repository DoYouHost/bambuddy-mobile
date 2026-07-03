// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Archive _$ArchiveFromJson(Map<String, dynamic> json) => Archive(
  id: (json['id'] as num).toInt(),
  filename: json['filename'] as String,
  status: json['status'] as String,
  printerId: (json['printer_id'] as num?)?.toInt(),
  printName: json['print_name'] as String?,
  thumbnailPath: json['thumbnail_path'] as String?,
  printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt(),
  filamentUsedGrams: (json['filament_used_grams'] as num?)?.toDouble(),
  filamentType: json['filament_type'] as String?,
  filamentColor: json['filament_color'] as String?,
  cost: (json['cost'] as num?)?.toDouble(),
  isFavorite: json['is_favorite'] as bool? ?? false,
  createdAt: dateTimeFromJson(json['created_at']),
  designer: json['designer'] as String?,
  makerworldUrl: json['makerworld_url'] as String?,
  totalLayers: (json['total_layers'] as num?)?.toInt(),
  layerHeight: (json['layer_height'] as num?)?.toDouble(),
  nozzleDiameter: (json['nozzle_diameter'] as num?)?.toDouble(),
  slicedForModel: json['sliced_for_model'] as String?,
  quantity: (json['quantity'] as num?)?.toInt(),
);
