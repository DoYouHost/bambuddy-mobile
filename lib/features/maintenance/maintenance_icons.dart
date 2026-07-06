import 'package:flutter/material.dart';

/// Maps a maintenance type icon name to a Material [IconData].
///
/// The server stores Lucide icon names (bambuddy's `iconMap` in
/// `MaintenancePage.tsx`). We mirror that exact set — see [maintenanceIconNames]
/// for the picker order — mapping each to the closest Material glyph so a type
/// created on the web renders consistently here. Unknown/`null` → [Icons.build_outlined].
IconData maintenanceIcon(String? name) {
  switch (name) {
    case 'Droplet':
      return Icons.water_drop_outlined;
    case 'Flame':
      return Icons.local_fire_department_outlined;
    case 'Ruler':
      return Icons.straighten_outlined;
    case 'Sparkles':
      return Icons.auto_awesome_outlined;
    case 'Square':
      return Icons.crop_square_outlined;
    case 'Cable':
      return Icons.cable_outlined;
    case 'Wrench':
    case 'Tool':
      return Icons.build_outlined;
    case 'Calendar':
      return Icons.calendar_today_outlined;
    case 'Timer':
      return Icons.timer_outlined;
    case 'Cog':
      return Icons.settings_outlined;
    case 'Fan':
      return Icons.cyclone;
    case 'Zap':
      return Icons.bolt_outlined;
    case 'Wind':
      return Icons.air;
    case 'Thermometer':
      return Icons.thermostat_outlined;
    case 'Layers':
      return Icons.layers_outlined;
    case 'Box':
      return Icons.inventory_2_outlined;
    case 'Target':
      return Icons.gps_fixed;
    case 'RefreshCw':
      return Icons.refresh;
    case 'Settings':
      return Icons.settings_suggest_outlined;
    case 'Filter':
      return Icons.filter_alt_outlined;
    case 'CircleDot':
      return Icons.radio_button_checked;
    // Legacy names some older stored types may still use.
    case 'Brush':
    case 'Paintbrush':
      return Icons.cleaning_services_outlined;
    case 'Gauge':
      return Icons.speed_outlined;
    default:
      return Icons.build_outlined;
  }
}

/// Icon names offered in the custom-type icon picker, in the same order as
/// bambuddy's `iconMap` so the two clients present an identical palette.
const maintenanceIconNames = <String>[
  'Droplet',
  'Flame',
  'Ruler',
  'Sparkles',
  'Square',
  'Cable',
  'Wrench',
  'Calendar',
  'Timer',
  'Cog',
  'Fan',
  'Zap',
  'Wind',
  'Thermometer',
  'Layers',
  'Box',
  'Target',
  'RefreshCw',
  'Settings',
  'Filter',
  'CircleDot',
];
