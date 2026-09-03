import 'json_utils.dart';

/// Why a due scheduled drying run has not started yet, as the scheduler's
/// `waiting_reason` names it.
///
/// A token rather than a sentence: the server writes the same identifiers the
/// web frontend translates, so the wording is ours to choose per locale. An
/// unrecognised token maps to [unknown] and the row simply says nothing about
/// why — which is what an older or newer server adding a reason should cost.
enum DryingWaitReason {
  /// The AMS needs its external power adapter before it can heat
  /// (`dry_sf_reason` 1 or 8).
  powerRequired('ams_power_required'),

  /// Filament is sitting at the AMS outlet and has to be retracted first
  /// (`dry_sf_reason` 3).
  retractFilament('ams_retract_filament'),

  /// The AMS refuses for a reason that clears by itself (busy, upgrading, …).
  blocked('ams_blocked'),

  /// The run names an AMS unit the live status does not report.
  amsNotFound('ams_not_found'),

  printerOffline('printer_offline'),
  printerBusy('printer_busy'),
  alreadyDrying('already_drying'),

  /// The run started and was stopped by something else; it will restart when
  /// the printer is free again.
  interrupted('interrupted'),

  /// A token this build has no wording for.
  unknown('');

  const DryingWaitReason(this.wire);

  /// The value the server writes into `waiting_reason`.
  final String wire;

  static DryingWaitReason? fromWire(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return unknown;
  }
}

/// A manual AMS drying run the server will start later — `GET/POST/DELETE
/// /scheduled-dryings` (server #2638, reference
/// `backend/app/api/routes/scheduled_dryings.py`).
///
/// The list route returns only `pending`, `running` and `failed` rows: a
/// finished or cancelled run is dropped from the listing, and a failed one
/// stays until the client dismisses it with the same DELETE that cancels a
/// pending one. Failure can only happen at dispatch — an offline printer is
/// schedulable and its firmware is judged when the run is due — so without the
/// failed row the schedule would just vanish.
class ScheduledDrying {
  const ScheduledDrying({
    required this.id,
    required this.printerId,
    required this.amsId,
    required this.temp,
    required this.durationHours,
    required this.filament,
    required this.rotateTray,
    required this.status,
    this.startAfter,
    this.waitingReason,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  factory ScheduledDrying.fromJson(Map<String, dynamic> json) =>
      ScheduledDrying(
        id: toInt(json['id']),
        printerId: toInt(json['printer_id']),
        amsId: toInt(json['ams_id']),
        temp: toInt(json['temp']),
        durationHours: toInt(json['duration_hours']),
        filament: toStringOrNull(json['filament']) ?? '',
        rotateTray: toBoolOrFalse(json['rotate_tray']),
        status: toStringOrNull(json['status']) ?? 'pending',
        startAfter: dateTimeFromJson(json['start_after']),
        waitingReason: DryingWaitReason.fromWire(
          toStringOrNull(json['waiting_reason']),
        ),
        errorMessage: toStringOrNull(json['error_message']),
        startedAt: dateTimeFromJson(json['started_at']),
        completedAt: dateTimeFromJson(json['completed_at']),
      );

  final int id;
  final int printerId;
  final int amsId;
  final int temp;
  final int durationHours;

  /// Empty when the run was scheduled without one; the scheduler fills it from
  /// the loaded tray at dispatch, so a pending row can legitimately show none.
  final String filament;

  final bool rotateTray;

  /// `pending` / `running` / `failed` on a listed row (`completed` and
  /// `cancelled` are filtered out server-side, so they only ever arrive as the
  /// echo of a DELETE).
  final String status;

  /// Earliest start instant, in local time. Null means "as soon as the printer
  /// is idle".
  final DateTime? startAfter;

  final DryingWaitReason? waitingReason;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isPending => status == 'pending';
  bool get isRunning => status == 'running';
  bool get isFailed => status == 'failed';
}
