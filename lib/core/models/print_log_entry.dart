import 'package:copy_with_extension/copy_with_extension.dart';

import 'json_utils.dart';
import 'print_run.dart';

part 'print_log_entry.g.dart';

/// One run from `GET /print-log/` — the table that outlives the archives it
/// points at, so a run whose archive was deleted is still here with
/// [archiveId] null.
///
/// Defensive parsing throughout: [id], [status] and [createdAt] are the only
/// fields the server always sends, and even those are coerced rather than cast
/// so one malformed record drops itself instead of the whole page (see
/// `parseJsonList`).
///
/// [copyWith] is generated from the constructor. It exists because a `PATCH
/// /print-log/{id}` answer is **merged** into the local row rather than
/// replacing it: a server older than 1.2.6 omits `cost` / `energy_kwh` /
/// `energy_cost` from that answer the same way it omits them from the list, so
/// taking the response wholesale would blank whatever those columns held.
/// Passing null to a nullable field nullifies it, which is how a cleared
/// failure cause travels — the hand-written version needed a separate
/// `clearFailureReason` flag to say the same thing.
@CopyWith(skipFields: true)
class PrintLogEntry with PrintRun {
  const PrintLogEntry({
    required this.id,
    required this.status,
    required this.createdAt,
    this.archiveId,
    this.printName,
    this.printerName,
    this.printerId,
    this.startedAt,
    this.completedAt,
    this.durationSeconds,
    this.filamentType,
    this.filamentColor,
    this.filamentUsedGrams,
    this.cost,
    this.energyKwh,
    this.energyCost,
    this.failureReason,
    this.thumbnailPath,
    this.createdById,
    this.createdByUsername,
  });

  factory PrintLogEntry.fromJson(Map<String, dynamic> json) => PrintLogEntry(
    id: toInt(json['id']),
    status: toStringOrNull(json['status']) ?? 'unknown',
    createdAt:
        dateTimeFromJson(json['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    archiveId: toIntOrNull(json['archive_id']),
    printName: toStringOrNull(json['print_name']),
    printerName: toStringOrNull(json['printer_name']),
    printerId: toIntOrNull(json['printer_id']),
    startedAt: dateTimeFromJson(json['started_at']),
    completedAt: dateTimeFromJson(json['completed_at']),
    durationSeconds: toIntOrNull(json['duration_seconds']),
    filamentType: toStringOrNull(json['filament_type']),
    filamentColor: toStringOrNull(json['filament_color']),
    filamentUsedGrams: toDoubleOrNull(json['filament_used_grams']),
    cost: toDoubleOrNull(json['cost']),
    energyKwh: toDoubleOrNull(json['energy_kwh']),
    energyCost: toDoubleOrNull(json['energy_cost']),
    failureReason: toStringOrNull(json['failure_reason']),
    thumbnailPath: toStringOrNull(json['thumbnail_path']),
    createdById: toIntOrNull(json['created_by_id']),
    createdByUsername: toStringOrNull(json['created_by_username']),
  );

  final int id;

  /// The archive this run produced, or null once that archive is gone — the FK
  /// is `ON DELETE SET NULL`, so the run survives it. Those orphans are half
  /// the reason this screen exists: nothing else in the app can reach them.
  final int? archiveId;

  final String? printName;
  final String? printerName;
  final int? printerId;

  /// One of [printLogStatuses], or a value outside it — `aborted` on rows
  /// written by the archive side, `unknown` when the field failed to parse.
  /// Never assume it is in the vocabulary.
  @override
  final String status;

  @override
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Measured run time. Present for failed runs too — they ran for a while.
  final int? durationSeconds;

  final String? filamentType;

  /// `#RRGGBB`, sometimes a multi-colour list: `#AABBCC,#112233`.
  @override
  final String? filamentColor;

  final double? filamentUsedGrams;

  /// Filament cost of this run, in the server's configured currency.
  ///
  /// Null on every row from a server older than 1.2.6, which records the value
  /// but never sends it — see `ServerFeature.printLogCostEnergy`.
  final double? cost;

  /// Energy this run drew and what it cost, from the smart plug bound to the
  /// printer. Null when no plug is bound, and — like [cost] — null on every row
  /// from a server older than 1.2.6.
  final double? energyKwh;
  final double? energyCost;

  /// One of [printLogFailureReasons], or free text: older web builds saved the
  /// translated label instead of the key, and the archive-side `PATCH` that
  /// mirrors this field validates nothing.
  final String? failureReason;

  /// Path on the server, not a URL — its only use is knowing whether
  /// `Endpoints.printLogThumbnail` has anything to serve. See [hasThumbnail].
  final String? thumbnailPath;

  final int? createdById;
  final String? createdByUsername;

  @override
  final DateTime createdAt;

  /// The run's own archive is gone (or it never had one — a queue-skipped run).
  bool get isOrphan => archiveId == null;

  bool get hasThumbnail => thumbnailPath != null;

  /// The measured duration under the name [PrintRun] gives it — the same
  /// column `GET /archives/slim` calls `actual_time_seconds`.
  @override
  int? get runSeconds => durationSeconds;
}

/// One page of `GET /print-log/`: the rows asked for, plus how many rows the
/// filter matches in total — which is what tells a "load more" list whether
/// there is more, and what the clear-log confirmation counts.
class PrintLogPage {
  const PrintLogPage({required this.items, required this.total});

  final List<PrintLogEntry> items;
  final int total;
}
