import 'json_utils.dart';
import 'print_run.dart';

/// One print run as `GET /archives/slim` describes it: the row of
/// `print_log_entries` the log screen also reads, minus everything the
/// statistics do not aggregate and plus the slicer's estimate joined from the
/// archive (`archives.py::list_archives_slim`). It feeds the widgets
/// `/archives/stats` does not compute — heatmap, records, colour
/// distribution, consumption over time, histograms.
///
/// The same run reaches the log screen as [PrintLogEntry]; the rules both
/// shapes answer with live in [PrintRun].
///
/// Defensive parsing: all fields except [status]/[createdAt] may be null, and
/// each one is coerced rather than cast — the payload is assembled per row
/// from a query, so a single odd value must not take the whole listing down.
class ArchiveSlim with PrintRun {
  const ArchiveSlim({
    required this.status,
    required this.createdAt,
    this.printerId,
    this.printName,
    this.printTimeSeconds,
    this.actualTimeSeconds,
    this.filamentUsedGrams,
    this.filamentType,
    this.filamentColor,
    this.startedAt,
    this.completedAt,
    this.cost,
    this.energyKwh,
    this.energyCost,
    this.quantity = 1,
  });

  factory ArchiveSlim.fromJson(Map<String, dynamic> json) => ArchiveSlim(
    status: toStringOrNull(json['status']) ?? 'unknown',
    createdAt:
        dateTimeFromJson(json['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    printerId: toIntOrNull(json['printer_id']),
    printName: toStringOrNull(json['print_name']),
    printTimeSeconds: toIntOrNull(json['print_time_seconds']),
    actualTimeSeconds: toIntOrNull(json['actual_time_seconds']),
    filamentUsedGrams: toDoubleOrNull(json['filament_used_grams']),
    filamentType: toStringOrNull(json['filament_type']),
    filamentColor: toStringOrNull(json['filament_color']),
    startedAt: dateTimeFromJson(json['started_at']),
    completedAt: dateTimeFromJson(json['completed_at']),
    cost: toDoubleOrNull(json['cost']),
    energyKwh: toDoubleOrNull(json['energy_kwh']),
    energyCost: toDoubleOrNull(json['energy_cost']),
    quantity: toIntOrNull(json['quantity']) ?? 1,
  );

  @override
  final String status;
  @override
  final DateTime createdAt;
  final int? printerId;
  final String? printName;

  /// Estimated print time from gcode/slicer.
  final int? printTimeSeconds;

  /// Actual print time (measured). Base for duration histogram.
  final int? actualTimeSeconds;

  final double? filamentUsedGrams;
  final String? filamentType;

  /// Filament color — `#RRGGBB`, sometimes multi-color: `#AABBCC,#112233`.
  @override
  final String? filamentColor;

  @override
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? cost;

  /// Energy this run drew, in kWh, and what it cost — per print, from the smart
  /// plug records (server ≥ 1.2.5.2; `null` on older ones, and on any run made
  /// before energy tracking was switched on). `/archives/stats` has carried the
  /// period *totals* all along; these are what let the breakdowns be computed
  /// per printer and over time.
  final double? energyKwh;
  final double? energyCost;

  final int quantity;

  /// The measured duration under the name [PrintRun] gives it — the same
  /// column `GET /print-log/` calls `duration_seconds`.
  @override
  int? get runSeconds => actualTimeSeconds;

  /// Time for stats: prefer what the run measured, fall back to what the
  /// slicer estimated. Only this shape can offer the fallback — the estimate
  /// lives on the archive, and `/print-log/` does not join it.
  int? get effectiveSeconds => actualTimeSeconds ?? printTimeSeconds;
}
