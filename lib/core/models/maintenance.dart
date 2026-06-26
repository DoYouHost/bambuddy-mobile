import 'package:json_annotation/json_annotation.dart';

part 'maintenance.g.dart';

/// Urgency of maintenance task calculated from server flags.
enum MaintenanceSeverity { ok, warning, due }

/// Maintenance overview for single printer from `GET /maintenance/overview`
/// (and `GET /maintenance/printers/{id}`) — `PrinterMaintenanceOverview`.
/// Defensive parsing: besides IDs, all numeric via tolerant helpers accepting
/// int/num/string, unknown keys ignored.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrinterMaintenanceOverview {
  const PrinterMaintenanceOverview({
    required this.printerId,
    required this.printerName,
    this.printerModel,
    this.totalPrintHours = 0,
    this.maintenanceItems = const [],
    this.dueCount = 0,
    this.warningCount = 0,
  });

  factory PrinterMaintenanceOverview.fromJson(Map<String, dynamic> json) =>
      _$PrinterMaintenanceOverviewFromJson(json);

  final int printerId;
  final String printerName;
  final String? printerModel;

  @JsonKey(fromJson: _toDouble)
  final double totalPrintHours;

  final List<MaintenanceStatus> maintenanceItems;

  @JsonKey(fromJson: _toInt)
  final int dueCount;

  @JsonKey(fromJson: _toInt)
  final int warningCount;

  /// Overdue items (disappear after counter reset).
  List<MaintenanceStatus> get dueItems =>
      [for (final i in maintenanceItems) if (i.isDue) i];
}

/// State of a single maintenance task (`MaintenanceStatus`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class MaintenanceStatus {
  const MaintenanceStatus({
    required this.id,
    required this.printerId,
    this.printerName,
    this.printerModel,
    required this.maintenanceTypeId,
    required this.maintenanceTypeName,
    this.maintenanceTypeIcon,
    this.maintenanceTypeWikiUrl,
    this.enabled = true,
    this.intervalHours = 0,
    this.intervalType = 'hours',
    this.currentHours = 0,
    this.hoursSinceMaintenance = 0,
    this.hoursUntilDue = 0,
    this.daysSinceMaintenance,
    this.daysUntilDue,
    this.isDue = false,
    this.isWarning = false,
    this.lastPerformedAtRaw,
  });

  factory MaintenanceStatus.fromJson(Map<String, dynamic> json) =>
      _$MaintenanceStatusFromJson(json);

  final int id;
  final int printerId;
  final String? printerName;
  final String? printerModel;
  final int maintenanceTypeId;
  final String maintenanceTypeName;

  /// Lucide-style icon name (e.g. "Droplet", "Flame") — mapped to Material in
  /// [maintenance_icons.dart]. Server may omit.
  final String? maintenanceTypeIcon;
  final String? maintenanceTypeWikiUrl;

  final bool enabled;

  @JsonKey(fromJson: _toDouble)
  final double intervalHours;

  /// Interval unit (e.g. "hours"). Raw, not enum-backed.
  final String intervalType;

  @JsonKey(fromJson: _toDouble)
  final double currentHours;

  @JsonKey(fromJson: _toDouble)
  final double hoursSinceMaintenance;

  @JsonKey(fromJson: _toDouble)
  final double hoursUntilDue;

  @JsonKey(fromJson: _toDoubleOrNull)
  final double? daysSinceMaintenance;

  @JsonKey(fromJson: _toDoubleOrNull)
  final double? daysUntilDue;

  final bool isDue;
  final bool isWarning;

  /// ISO8601 (sometimes with "Z", sometimes without) — parsed to [lastPerformedAt].
  @JsonKey(name: 'last_performed_at')
  final String? lastPerformedAtRaw;

  DateTime? get lastPerformedAt =>
      lastPerformedAtRaw == null ? null : DateTime.tryParse(lastPerformedAtRaw!);

  MaintenanceSeverity get severity => isDue
      ? MaintenanceSeverity.due
      : isWarning
          ? MaintenanceSeverity.warning
          : MaintenanceSeverity.ok;

  /// Progress to due date in range 0..1 (for progress bar). Beyond due clamped to 1.
  double get progress {
    if (intervalHours <= 0) return 0;
    return (hoursSinceMaintenance / intervalHours).clamp(0, 1).toDouble();
  }
}

/// Maintenance execution history entry (`MaintenanceHistoryResponse`).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class MaintenanceHistoryEntry {
  const MaintenanceHistoryEntry({
    required this.id,
    required this.printerMaintenanceId,
    this.performedAt,
    this.hoursAtMaintenance = 0,
    this.notes,
  });

  factory MaintenanceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$MaintenanceHistoryEntryFromJson(json);

  final int id;
  final int printerMaintenanceId;

  @JsonKey(name: 'performed_at')
  final String? performedAt;

  @JsonKey(fromJson: _toDouble)
  final double hoursAtMaintenance;

  final String? notes;

  DateTime? get performedAtDate =>
      performedAt == null ? null : DateTime.tryParse(performedAt!);
}

double _toDouble(dynamic value) => _toDoubleOrNull(value) ?? 0;

double? _toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int _toInt(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };
