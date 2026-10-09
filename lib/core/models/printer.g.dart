// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'printer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Printer _$PrinterFromJson(Map<String, dynamic> json) => Printer(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  model: json['model'] as String?,
  ipAddress: json['ip_address'] as String?,
  location: json['location'] as String?,
  isActive: json['is_active'] as bool?,
  serialNumber: json['serial_number'] as String?,
  nozzleCount: (json['nozzle_count'] as num?)?.toInt(),
  autoArchive: json['auto_archive'] as bool?,
  wearCostPerHour: (json['wear_cost_per_hour'] as num?)?.toDouble(),
  servesWearCost: _hasWearCostKey(json, 'serves_wear_cost') as bool? ?? false,
);
