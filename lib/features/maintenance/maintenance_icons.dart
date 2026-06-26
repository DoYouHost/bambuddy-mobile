import 'package:flutter/material.dart';

/// Maps maintenance type icon name (server provides Lucide-style names,
/// e.g. "Droplet", "Flame") to Material [IconData]. Unknown/`null` → [Icons.build].
/// Set covers default bambuddy types plus some probable ones.
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
