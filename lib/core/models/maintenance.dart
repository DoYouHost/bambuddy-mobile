import 'package:json_annotation/json_annotation.dart';

part 'maintenance.g.dart';

/// Pilność czynności konserwacji wyliczona z flag serwera.
enum MaintenanceSeverity { ok, warning, due }

/// Przegląd konserwacji jednej drukarki z `GET /maintenance/overview`
/// (i `GET /maintenance/printers/{id}`) — `PrinterMaintenanceOverview`.
/// Parsujemy defensywnie: poza identyfikatorami wszystko liczbowe przez helpery
/// tolerujące int/num/string, nieznane klucze ignorowane.
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

  /// Pozycje przeterminowane (po reset licznika znikają stąd).
  List<MaintenanceStatus> get dueItems =>
      [for (final i in maintenanceItems) if (i.isDue) i];
}

/// Stan pojedynczej czynności konserwacji (`MaintenanceStatus`).
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

  /// Nazwa ikony w stylu Lucide (np. „Droplet", „Flame") — mapowana na Material
  /// w [maintenance_icons.dart]. Serwer może jej nie podać.
  final String? maintenanceTypeIcon;
  final String? maintenanceTypeWikiUrl;

  final bool enabled;

  @JsonKey(fromJson: _toDouble)
  final double intervalHours;

  /// Jednostka interwału (np. „hours"). Surowo, nie enumujemy.
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

  /// ISO8601 (czasem z „Z", czasem bez) — parsujemy do [lastPerformedAt].
  @JsonKey(name: 'last_performed_at')
  final String? lastPerformedAtRaw;

  DateTime? get lastPerformedAt =>
      lastPerformedAtRaw == null ? null : DateTime.tryParse(lastPerformedAtRaw!);

  MaintenanceSeverity get severity => isDue
      ? MaintenanceSeverity.due
      : isWarning
          ? MaintenanceSeverity.warning
          : MaintenanceSeverity.ok;

  /// Postęp do terminu w zakresie 0..1 (do paska postępu). Powyżej terminu
  /// klamrowany do 1.
  double get progress {
    if (intervalHours <= 0) return 0;
    return (hoursSinceMaintenance / intervalHours).clamp(0, 1).toDouble();
  }
}

/// Wpis historii wykonania konserwacji (`MaintenanceHistoryResponse`).
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
