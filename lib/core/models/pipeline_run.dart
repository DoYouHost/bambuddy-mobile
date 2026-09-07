/// Pipeline runs and their eligibility pre-flight (`/pipeline-runs`,
/// `POST /slicer-pipelines/{id}/run` and `…/check-eligibility`).
///
/// A run slices the source once and then dispatches `copies` print jobs to the
/// pipeline's target — one [PipelineJob] per copy. Everything here is parse-only
/// and forward-tolerant: an unrecognised `status` or issue `kind` from a newer
/// server maps to an `unknown` member instead of throwing, because these arrive
/// over both REST and a WebSocket push.
library;

import 'json_utils.dart';
import 'slicer_pipeline.dart';

/// Why a pipeline cannot (or should not) run, per
/// `services/pipeline_eligibility.py`.
enum EligibilityIssueKind {
  printerNotSet,
  printerNotFound,
  printerDisabled,
  printerOffline,
  filamentTypeMismatch,
  filamentColorMismatch,
  amsSlotMissing,

  /// The pipeline's filament preset sits on a tier the server cannot read
  /// statically (cloud / orca_cloud / standard). Advisory — the run proceeds.
  filamentUnverified,

  /// `printer_class` target with no printer of that model in the install.
  noClassMatches,

  /// `printer_class` target with no model class picked yet.
  classNotSet,

  /// A kind this build does not know. Shown as its raw string rather than
  /// hidden, so a newer server's reason still reaches the user.
  unknown;

  static EligibilityIssueKind parse(String? raw) => switch (raw) {
    'printer_not_set' => EligibilityIssueKind.printerNotSet,
    'printer_not_found' => EligibilityIssueKind.printerNotFound,
    'printer_disabled' => EligibilityIssueKind.printerDisabled,
    'printer_offline' => EligibilityIssueKind.printerOffline,
    'filament_type_mismatch' => EligibilityIssueKind.filamentTypeMismatch,
    'filament_color_mismatch' => EligibilityIssueKind.filamentColorMismatch,
    'ams_slot_missing' => EligibilityIssueKind.amsSlotMissing,
    'filament_unverified' => EligibilityIssueKind.filamentUnverified,
    'no_class_matches' => EligibilityIssueKind.noClassMatches,
    'class_not_set' => EligibilityIssueKind.classNotSet,
    _ => EligibilityIssueKind.unknown,
  };
}

/// One eligibility complaint (`EligibilityIssueResponse`).
class EligibilityIssue {
  const EligibilityIssue({
    required this.kind,
    required this.rawKind,
    this.slotIndex,
    this.expected,
    this.actual,
  });

  factory EligibilityIssue.fromJson(Map<String, dynamic> json) {
    final raw = json['kind'] as String?;
    return EligibilityIssue(
      kind: EligibilityIssueKind.parse(raw),
      rawKind: raw ?? '',
      slotIndex: toIntOrNull(json['slot_index']),
      expected: json['expected'] as String?,
      actual: json['actual'] as String?,
    );
  }

  final EligibilityIssueKind kind;

  /// Verbatim, so an [EligibilityIssueKind.unknown] can still name itself.
  final String rawKind;

  /// 0-based AMS slot the complaint is about, for the filament kinds.
  final int? slotIndex;
  final String? expected;
  final String? actual;

  /// Whether this blocks the run or is only worth reading.
  ///
  /// The server's own policy is lenient — `filament_unverified` never clears
  /// `ok`, it just asks the operator to look (`pipeline_eligibility.py`). Every
  /// other kind contributes to a `not ok` report.
  bool get isAdvisory => kind == EligibilityIssueKind.filamentUnverified;
}

/// One candidate printer's verdict when a class is targeted (`PerPrinterReport`).
class PerPrinterReport {
  const PerPrinterReport({
    required this.printerId,
    required this.printerName,
    required this.ok,
    this.issues = const [],
  });

  factory PerPrinterReport.fromJson(Map<String, dynamic> json) =>
      PerPrinterReport(
        printerId: toIntOrNull(json['printer_id']) ?? 0,
        printerName: json['printer_name'] as String? ?? '',
        ok: json['ok'] == true,
        issues: parseJsonList(json['issues'], EligibilityIssue.fromJson),
      );

  final int printerId;
  final String printerName;
  final bool ok;
  final List<EligibilityIssue> issues;
}

/// The pre-flight verdict (`EligibilityReportResponse`), returned both by
/// `check-eligibility` and — inside the `detail` of a **409** — by a `run` the
/// operator has not forced.
///
/// [ok] means different things per target kind, and the difference matters to
/// what the confirmation screen may claim: for a pinned printer it mirrors that
/// one printer, while for a class it is true when **at least one** candidate
/// passes, since the scheduler picks an eligible one. So a class run can be
/// `ok` with half its [printerReports] failing.
class EligibilityReport {
  const EligibilityReport({
    required this.ok,
    this.targetKind = PipelineTargetKind.specificPrinter,
    this.targetPrinterId,
    this.targetPrinterName,
    this.targetModelClass,
    this.issues = const [],
    this.printerReports = const [],
  });

  factory EligibilityReport.fromJson(Map<String, dynamic> json) =>
      EligibilityReport(
        ok: json['ok'] == true,
        // The response's own default is `specific_printer` here, unlike the
        // pipeline schema's `printer_class` — mirrored rather than unified.
        targetKind: json['target_kind'] == null
            ? PipelineTargetKind.specificPrinter
            : PipelineTargetKind.parse(json['target_kind'] as String?),
        targetPrinterId: toIntOrNull(json['target_printer_id']),
        targetPrinterName: json['target_printer_name'] as String?,
        targetModelClass: json['target_model_class'] as String?,
        issues: parseJsonList(json['issues'], EligibilityIssue.fromJson),
        printerReports: parseJsonList(
          json['printer_reports'],
          PerPrinterReport.fromJson,
        ),
      );

  final bool ok;
  final PipelineTargetKind targetKind;
  final int? targetPrinterId;
  final String? targetPrinterName;
  final String? targetModelClass;

  /// Class-level complaints only (`no_class_matches`, `class_not_set`);
  /// per-printer detail lives in [printerReports].
  final List<EligibilityIssue> issues;
  final List<PerPrinterReport> printerReports;

  /// Candidates that would accept the job — the "3 of 5" numerator.
  int get eligibleCount => printerReports.where((r) => r.ok).length;

  /// Everything worth showing, class-level first then per-printer.
  List<EligibilityIssue> get allIssues => [
    ...issues,
    for (final r in printerReports) ...r.issues,
  ];

  /// Whether anything at all is worth putting in front of the operator — an
  /// advisory-only report is still [ok] but should not slip past silently.
  bool get hasAnything => allIssues.isNotEmpty;
}

/// Lifecycle of a whole run (`PipelineRunResponse.status`).
enum PipelineRunStatus {
  queued,
  slicing,
  dispatching,
  inProgress,
  completed,
  failed,

  /// Some copies made it, some did not — the state `retry-failed` exists for.
  partialFailure,
  cancelled,
  unknown;

  static PipelineRunStatus parse(String? raw) => switch (raw) {
    'queued' => PipelineRunStatus.queued,
    'slicing' => PipelineRunStatus.slicing,
    'dispatching' => PipelineRunStatus.dispatching,
    'in_progress' => PipelineRunStatus.inProgress,
    'completed' => PipelineRunStatus.completed,
    'failed' => PipelineRunStatus.failed,
    'partial_failure' => PipelineRunStatus.partialFailure,
    'cancelled' => PipelineRunStatus.cancelled,
    _ => PipelineRunStatus.unknown,
  };

  /// The value the `status` query parameter takes. [unknown] has none — it
  /// stands for a status this build has not heard of, so there is nothing to
  /// ask the server for.
  String? get wire => switch (this) {
    PipelineRunStatus.queued => 'queued',
    PipelineRunStatus.slicing => 'slicing',
    PipelineRunStatus.dispatching => 'dispatching',
    PipelineRunStatus.inProgress => 'in_progress',
    PipelineRunStatus.completed => 'completed',
    PipelineRunStatus.failed => 'failed',
    PipelineRunStatus.partialFailure => 'partial_failure',
    PipelineRunStatus.cancelled => 'cancelled',
    PipelineRunStatus.unknown => null,
  };

  /// Every status the dashboard may filter by, in the order a run passes
  /// through them.
  static const filterable = [
    queued,
    slicing,
    dispatching,
    inProgress,
    completed,
    partialFailure,
    failed,
    cancelled,
  ];

  /// The four the server itself treats as finished (`_TERMINAL_RUN_STATUSES`).
  /// [unknown] is deliberately not terminal: a status this build cannot name is
  /// more likely a new in-flight state than a finished one, and polling a
  /// finished run costs one request while stopping early strands the UI.
  bool get isTerminal =>
      this == completed ||
      this == failed ||
      this == cancelled ||
      this == partialFailure;
}

/// Lifecycle of one copy (`PipelineJobResponse.status`).
enum PipelineJobStatus {
  pending,

  /// Sliced and waiting for a printer of the target class to free up.
  awaitingPrinter,
  queued,
  printing,
  completed,
  failed,
  cancelled,
  unknown;

  static PipelineJobStatus parse(String? raw) => switch (raw) {
    'pending' => PipelineJobStatus.pending,
    'awaiting_printer' => PipelineJobStatus.awaitingPrinter,
    'queued' => PipelineJobStatus.queued,
    'printing' => PipelineJobStatus.printing,
    'completed' => PipelineJobStatus.completed,
    'failed' => PipelineJobStatus.failed,
    'cancelled' => PipelineJobStatus.cancelled,
    _ => PipelineJobStatus.unknown,
  };

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

/// One copy of a run (`PipelineJobResponse`).
class PipelineJob {
  const PipelineJob({
    required this.id,
    required this.copyIndex,
    required this.status,
    this.assignedPrinterId,
    this.assignedPrinterName,
    this.queueEntryId,
    this.errorMessage,
    this.dispatchedAt,
    this.completedAt,
  });

  factory PipelineJob.fromJson(Map<String, dynamic> json) => PipelineJob(
    id: toIntOrNull(json['id']) ?? 0,
    copyIndex: toIntOrNull(json['copy_index']) ?? 0,
    status: PipelineJobStatus.parse(json['status'] as String?),
    assignedPrinterId: toIntOrNull(json['assigned_printer_id']),
    assignedPrinterName: json['assigned_printer_name'] as String?,
    queueEntryId: toIntOrNull(json['queue_entry_id']),
    errorMessage: json['error_message'] as String?,
    dispatchedAt: dateTimeFromJson(json['dispatched_at']),
    completedAt: dateTimeFromJson(json['completed_at']),
  );

  final int id;
  final int copyIndex;
  final PipelineJobStatus status;
  final int? assignedPrinterId;
  final String? assignedPrinterName;
  final int? queueEntryId;
  final String? errorMessage;
  final DateTime? dispatchedAt;
  final DateTime? completedAt;
}

/// One run (`PipelineRunResponse`).
class PipelineRun {
  const PipelineRun({
    required this.id,
    required this.copies,
    required this.status,
    this.pipelineId,
    this.pipelineName,
    this.sourceLibraryFileId,
    this.sourceArchiveId,
    this.sourceFilename,
    this.parentRunId,
    this.copiesCompleted = 0,
    this.copiesFailed = 0,
    this.copiesCancelled = 0,
    this.copiesInProgress = 0,
    this.sliceJobId,
    this.slicedLibraryFileId,
    this.eligibilityOverridden = false,
    this.errorMessage,
    this.createdBy,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.jobs = const [],
    this.targetKind,
    this.targetPrinterId,
    this.targetModelClass,
    this.fanoutStrategy,
  });

  factory PipelineRun.fromJson(Map<String, dynamic> json) => PipelineRun(
    id: toIntOrNull(json['id']) ?? 0,
    pipelineId: toIntOrNull(json['pipeline_id']),
    pipelineName: json['pipeline_name'] as String?,
    sourceLibraryFileId: toIntOrNull(json['source_library_file_id']),
    sourceArchiveId: toIntOrNull(json['source_archive_id']),
    sourceFilename: json['source_filename'] as String?,
    parentRunId: toIntOrNull(json['parent_run_id']),
    copies: toIntOrNull(json['copies']) ?? 0,
    copiesCompleted: toIntOrNull(json['copies_completed']) ?? 0,
    copiesFailed: toIntOrNull(json['copies_failed']) ?? 0,
    copiesCancelled: toIntOrNull(json['copies_cancelled']) ?? 0,
    copiesInProgress: toIntOrNull(json['copies_in_progress']) ?? 0,
    status: PipelineRunStatus.parse(json['status'] as String?),
    sliceJobId: toIntOrNull(json['slice_job_id']),
    slicedLibraryFileId: toIntOrNull(json['sliced_library_file_id']),
    eligibilityOverridden: json['eligibility_overridden'] == true,
    errorMessage: json['error_message'] as String?,
    createdBy: toIntOrNull(json['created_by']),
    createdAt: dateTimeFromJson(json['created_at']),
    startedAt: dateTimeFromJson(json['started_at']),
    completedAt: dateTimeFromJson(json['completed_at']),
    jobs: parseJsonList(json['jobs'], PipelineJob.fromJson),
    // Null rather than the enum default: these are a snapshot of the
    // pipeline's target and the server omits them for a run whose pipeline
    // is gone, which is not the same as "targets a class".
    targetKind: json['target_kind'] == null
        ? null
        : PipelineTargetKind.parse(json['target_kind'] as String?),
    targetPrinterId: toIntOrNull(json['target_printer_id']),
    targetModelClass: json['target_model_class'] as String?,
    fanoutStrategy: json['fanout_strategy'] == null
        ? null
        : FanoutStrategy.parse(json['fanout_strategy'] as String?),
  );

  final int id;

  /// Null once the pipeline has been deleted — the run rows outlive it, which
  /// is why the delete is a soft one. Retry needs it and 400s without it.
  final int? pipelineId;
  final String? pipelineName;
  final int? sourceLibraryFileId;
  final int? sourceArchiveId;
  final String? sourceFilename;

  /// Set on a run created by `retry-failed`.
  final int? parentRunId;

  final int copies;

  /// Roll-ups the server recomputes per read from the live job statuses, so
  /// they agree with [jobs] rather than with a stale snapshot.
  final int copiesCompleted;
  final int copiesFailed;
  final int copiesCancelled;
  final int copiesInProgress;

  final PipelineRunStatus status;
  final int? sliceJobId;
  final int? slicedLibraryFileId;

  /// The operator ran it past a failing pre-flight.
  final bool eligibilityOverridden;
  final String? errorMessage;
  final int? createdBy;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<PipelineJob> jobs;

  final PipelineTargetKind? targetKind;
  final int? targetPrinterId;
  final String? targetModelClass;
  final FanoutStrategy? fanoutStrategy;

  /// Whether `retry-failed` has anything to do. The server counts the parent's
  /// failed **and** cancelled copies and 400s on zero, so this mirrors that sum
  /// rather than [copiesFailed] alone.
  bool get hasRetryableCopies => copiesFailed + copiesCancelled > 0;

  /// Terminal *and* worth retrying *and* still able to be —
  /// `retry-failed` has three preconditions and answers **400** on each
  /// (`routes/pipeline_runs.py`): the pipeline must still be linked, a source
  /// must still be linked, and something must have failed.
  ///
  /// The source is the reachable one. Both columns are `ondelete="SET NULL"`,
  /// so deleting the library file or the archive a run was sliced from empties
  /// them while the run itself stays — which is the point of keeping the
  /// history. A retry then cannot re-slice anything.
  bool get canRetry =>
      status.isTerminal &&
      hasRetryableCopies &&
      pipelineId != null &&
      (sourceLibraryFileId != null || sourceArchiveId != null);

  /// Copies that reached a terminal state, for a progress fraction.
  int get copiesFinished => copiesCompleted + copiesFailed + copiesCancelled;
}

/// What the dashboard narrows the run list to (`list_all_runs`).
///
/// Server-side because two of the four cannot be answered here: `target_*`
/// JOIN to the pipeline's current target, which a page of runs does not carry,
/// and `status` matches the **persisted snapshot** rather than the live roll-up
/// — so an in-flight run can sit under `dispatching` until its next transition
/// writes through, and filtering the fetched page on [PipelineRun.status] would
/// disagree with what the server counted in `total`.
class PipelineRunFilter {
  const PipelineRunFilter({
    this.pipelineId,
    this.status,
    this.targetPrinterId,
    this.targetModelClass,
  });

  /// Only runs of this saved pipeline. A run whose pipeline was deleted has a
  /// null `pipeline_id` and no filter can reach it.
  final int? pipelineId;

  /// One [PipelineRunStatus.wire] value. Held as the wire string rather than
  /// the enum so [PipelineRunStatus.unknown] — a status this build does not
  /// know — is never offered as something to filter by.
  final String? status;

  final int? targetPrinterId;
  final String? targetModelClass;

  bool get isEmpty =>
      pipelineId == null &&
      status == null &&
      targetPrinterId == null &&
      targetModelClass == null;

  /// How many of the four are set — for the badge on the filter button.
  int get activeCount => [
    pipelineId,
    status,
    targetPrinterId,
    targetModelClass,
  ].where((v) => v != null).length;

  /// Only the keys that are set: the route reads `None` as "do not filter", and
  /// an explicit null in the query string arrives as the string `"None"`.
  Map<String, dynamic> get queryParameters => {
    'pipeline_id': ?pipelineId,
    'status': ?status,
    'target_printer_id': ?targetPrinterId,
    'target_model_class': ?targetModelClass,
  };

  /// A copy with one field changed, where null **clears** it — the opposite of
  /// the pipeline update body, and the right rule for a filter the user is
  /// turning off. Each field is passed as a sentinel-wrapped value so "leave
  /// alone" and "clear" stay distinguishable.
  PipelineRunFilter copyWith({
    ({int? value})? pipelineId,
    ({String? value})? status,
    ({int? value})? targetPrinterId,
    ({String? value})? targetModelClass,
  }) => PipelineRunFilter(
    pipelineId: pipelineId == null ? this.pipelineId : pipelineId.value,
    status: status == null ? this.status : status.value,
    targetPrinterId: targetPrinterId == null
        ? this.targetPrinterId
        : targetPrinterId.value,
    targetModelClass: targetModelClass == null
        ? this.targetModelClass
        : targetModelClass.value,
  );

  @override
  bool operator ==(Object other) =>
      other is PipelineRunFilter &&
      other.pipelineId == pipelineId &&
      other.status == status &&
      other.targetPrinterId == targetPrinterId &&
      other.targetModelClass == targetModelClass;

  @override
  int get hashCode =>
      Object.hash(pipelineId, status, targetPrinterId, targetModelClass);
}

/// A page of runs (`PipelineRunListResponse`).
class PipelineRunPage {
  const PipelineRunPage({this.runs = const [], this.total = 0});

  factory PipelineRunPage.fromJson(Map<String, dynamic> json) =>
      PipelineRunPage(
        runs: parseJsonList(json['runs'], PipelineRun.fromJson),
        total: toIntOrNull(json['total']) ?? 0,
      );

  final List<PipelineRun> runs;
  final int total;
}
