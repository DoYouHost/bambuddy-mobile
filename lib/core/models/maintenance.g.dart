// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'maintenance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PrinterMaintenanceOverview _$PrinterMaintenanceOverviewFromJson(
  Map<String, dynamic> json,
) => PrinterMaintenanceOverview(
  printerId: (json['printer_id'] as num).toInt(),
  printerName: json['printer_name'] as String,
  printerModel: json['printer_model'] as String?,
  totalPrintHours: json['total_print_hours'] == null
      ? 0
      : _toDouble(json['total_print_hours']),
  maintenanceItems: json['maintenance_items'] == null
      ? const []
      : _maintenanceItemsFromJson(json['maintenance_items']),
  dueCount: json['due_count'] == null ? 0 : _toInt(json['due_count']),
  warningCount: json['warning_count'] == null
      ? 0
      : _toInt(json['warning_count']),
);

MaintenanceStatus _$MaintenanceStatusFromJson(Map<String, dynamic> json) =>
    MaintenanceStatus(
      id: (json['id'] as num).toInt(),
      printerId: (json['printer_id'] as num).toInt(),
      printerName: json['printer_name'] as String?,
      printerModel: json['printer_model'] as String?,
      maintenanceTypeId: (json['maintenance_type_id'] as num).toInt(),
      maintenanceTypeName: json['maintenance_type_name'] as String,
      maintenanceTypeIcon: json['maintenance_type_icon'] as String?,
      maintenanceTypeWikiUrl: json['maintenance_type_wiki_url'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      intervalHours: json['interval_hours'] == null
          ? 0
          : _toDouble(json['interval_hours']),
      intervalType: json['interval_type'] as String? ?? 'hours',
      currentHours: json['current_hours'] == null
          ? 0
          : _toDouble(json['current_hours']),
      hoursSinceMaintenance: json['hours_since_maintenance'] == null
          ? 0
          : _toDouble(json['hours_since_maintenance']),
      hoursUntilDue: json['hours_until_due'] == null
          ? 0
          : _toDouble(json['hours_until_due']),
      daysSinceMaintenance: _toDoubleOrNull(json['days_since_maintenance']),
      daysUntilDue: _toDoubleOrNull(json['days_until_due']),
      isDue: json['is_due'] as bool? ?? false,
      isWarning: json['is_warning'] as bool? ?? false,
      lastPerformedAtRaw: json['last_performed_at'] as String?,
    );

MaintenanceType _$MaintenanceTypeFromJson(Map<String, dynamic> json) =>
    MaintenanceType(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String?,
      defaultIntervalHours: json['default_interval_hours'] == null
          ? 100
          : _toDouble(json['default_interval_hours']),
      intervalType: json['interval_type'] as String? ?? 'hours',
      icon: json['icon'] as String?,
      wikiUrl: json['wiki_url'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
    );

MaintenanceHistoryEntry _$MaintenanceHistoryEntryFromJson(
  Map<String, dynamic> json,
) => MaintenanceHistoryEntry(
  id: (json['id'] as num).toInt(),
  printerMaintenanceId: (json['printer_maintenance_id'] as num).toInt(),
  performedAt: json['performed_at'] as String?,
  hoursAtMaintenance: json['hours_at_maintenance'] == null
      ? 0
      : _toDouble(json['hours_at_maintenance']),
  notes: json['notes'] as String?,
);
