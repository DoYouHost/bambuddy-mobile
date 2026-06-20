import 'package:flutter/material.dart';

/// Mapuje nazwę ikony typu konserwacji (serwer podaje nazwy w stylu Lucide,
/// np. „Droplet", „Flame") na Material [IconData]. Nieznana/`null` → [Icons.build].
/// Zestaw obejmuje ikony domyślnych typów bambuddy plus kilka prawdopodobnych.
IconData maintenanceIcon(String? name) {
  switch (name) {
    case 'Droplet':
      return Icons.water_drop_outlined;
    case 'Sparkles':
      return Icons.auto_awesome_outlined;
    case 'Flame':
      return Icons.local_fire_department_outlined;
    case 'Ruler':
      return Icons.straighten_outlined;
    case 'Cable':
      return Icons.cable_outlined;
    case 'Square':
      return Icons.crop_square_outlined;
    case 'Wrench':
    case 'Tool':
      return Icons.build_outlined;
    case 'Settings':
    case 'Cog':
      return Icons.settings_outlined;
    case 'Fan':
    case 'Wind':
      return Icons.air_outlined;
    case 'Brush':
    case 'Paintbrush':
      return Icons.cleaning_services_outlined;
    case 'Gauge':
      return Icons.speed_outlined;
    case 'Zap':
      return Icons.bolt_outlined;
    default:
      return Icons.build_outlined;
  }
}
