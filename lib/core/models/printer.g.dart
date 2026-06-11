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
);
