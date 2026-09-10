/// What the app knows about one run of a print, whichever route described it.
///
/// The server keeps runs in a single table, `print_log_entries`, and serves it
/// through two routes with different shapes: `GET /print-log/`, the whole row
/// for the log screen, and `GET /archives/slim`, a projection joined to the
/// archive for the slicer's estimate, which the statistics aggregate
/// (`archives.py::list_archives_slim`). [PrintLogEntry] and [ArchiveSlim] are
/// those two shapes, and what they agree on lives here so that a rule like
/// "which statuses count as a failure" cannot answer differently depending on
/// which screen asked.
///
/// The app's third model of a print, `Archive`, is deliberately not one of
/// these: it is the *file*, reused by every reprint, not a run of it.
library;

import '../format/filament_colour.dart';

/// The failure causes `PATCH /print-log/{id}` accepts, in the server's order.
///
/// These are i18n keys, not labels — render them through
/// `failureReasonLabel`, never directly. The server validates writes against
/// this exact list (`print_log.py::_FAILURE_REASON_KEYS`) and 400s on anything
/// else, so the picker must not offer a value that is not here. Clearing the
/// classification is `''`, which is not part of the list because it is an
/// action rather than a cause.
const printLogFailureReasons = <String>[
  'adhesionFailure',
  'spaghettiDetached',
  'layerShift',
  'cloggedNozzle',
  'filamentRunout',
  'warping',
  'stringing',
  'underExtrusion',
  'powerFailure',
  'userCancelled',
  'other',
];

/// The statuses `PATCH /print-log/{id}` accepts
/// (`print_log.py::_STATUS_KEYS`).
///
/// Deliberately missing `aborted`, which archives do use and which
/// [printRunIsFailure] still counts: a row that carries it keeps it as long as
/// the field is left unsent, and cannot be given it back once something else
/// has been written. See `PrintLogEntry.status`.
const printLogStatuses = <String>[
  'completed',
  'failed',
  'stopped',
  'cancelled',
  'skipped',
];

/// Whether a run in this status is counted as a failure by the server's
/// Failure Analysis (`FailureAnalysisService`: `status.in_(['failed',
/// 'aborted'])`), and by the archive list's "hide failed" filter, which hides
/// exactly the rows this analysis counts.
///
/// This is also what makes a failure cause visible or invisible: the widget
/// groups by `failure_reason` **within** these statuses only, so a cause set
/// on a completed or cancelled run is stored and then never shown anywhere.
bool printRunIsFailure(String? status) =>
    status == 'failed' || status == 'aborted';

/// Whether the run finished the thing it was asked to print. Everything else —
/// a failure, a cancellation, a status this build has never heard of — is not
/// a success, which is what keeps a new server-side status out of the success
/// count until someone has decided what it means.
bool printRunIsSuccess(String? status) => status?.toLowerCase() == 'completed';

/// The run facts both shapes carry, and the answers derived from them.
///
/// A mixin rather than a base class: the two parse different payloads and keep
/// their own fields, so what is shared is the vocabulary, not the storage.
mixin PrintRun {
  /// One of [printLogStatuses], or a value outside it — `aborted` on rows
  /// written by the archive side, `unknown` when the field failed to parse.
  String get status;

  DateTime get createdAt;
  DateTime? get startedAt;
  String? get filamentColor;

  /// Measured run time in seconds. One column, two wire names:
  /// `duration_seconds` on `/print-log/`, `actual_time_seconds` on
  /// `/archives/slim`.
  int? get runSeconds;

  bool get isSuccess => printRunIsSuccess(status);

  bool get countsAsFailure => printRunIsFailure(status);

  /// The date a listing orders and groups by, matching the server's own `date`
  /// column: `started_at` when the run started, `created_at` for the ones that
  /// never did.
  DateTime get displayDate => startedAt ?? createdAt;

  List<String> get filamentColors => filamentColourTokens(filamentColor);

  String? get primaryColor => primaryFilamentColour(filamentColor);
}
