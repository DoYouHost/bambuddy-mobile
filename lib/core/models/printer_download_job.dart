import 'json_utils.dart';

/// How far a server-side download preparation has got
/// (`services/printer_media.py::PrinterFilesJobStatus.state`).
enum PrinterDownloadJobState {
  /// Accepted, nothing pulled off the printer yet.
  queued,

  /// Pulling the selected files over the printer's FTP socket. The only state
  /// that reports counts as it goes.
  preparing,

  /// Prepared and waiting behind [PrinterDownloadJob.token], which expires five
  /// minutes later.
  ready,

  /// Gave up — [PrinterDownloadJob.message] says why, in the server's words.
  failed,

  /// Cancelled, either by us or by another client holding the same job.
  cancelled,

  /// A state this app does not know. Treated as "still working": a newer server
  /// naming an intermediate phase must not read as a finished download. What
  /// ends the polling then is the server's own answer, or `PrinterDownloadRun
  /// .maxWait` behind it — never a guess about what the name meant.
  unknown;

  bool get isTerminal => this == ready || this == failed || this == cancelled;
}

/// One asynchronous printer-file download prepared on the server (server
/// #2850): `POST /printers/{id}/files/download-job` answers with this, `GET
/// …/download-jobs/{job_id}` repeats it as the work progresses.
///
/// It replaces holding a request open for the whole bundle — up to the server's
/// own 30-minute ceiling — with something that can be reported on and
/// cancelled.
class PrinterDownloadJob {
  const PrinterDownloadJob({
    required this.jobId,
    required this.printerId,
    required this.state,
    required this.requested,
    this.successful = 0,
    this.failed = 0,
    this.token,
    this.filename,
    this.message,
  });

  factory PrinterDownloadJob.fromJson(Map<String, dynamic> json) =>
      PrinterDownloadJob(
        jobId: toStringOrNull(json['job_id']) ?? '',
        printerId: toInt(json['printer_id']),
        state: _stateFrom(json['state']),
        requested: toInt(json['requested']),
        successful: toInt(json['successful']),
        failed: toInt(json['failed']),
        token: toStringOrNull(json['token']),
        filename: toStringOrNull(json['filename']),
        message: toStringOrNull(json['message']),
      );

  final String jobId;
  final int printerId;
  final PrinterDownloadJobState state;

  /// How many files were selected.
  final int requested;

  /// How many are staged so far. On a [PrinterDownloadJobState.ready] job this
  /// is the final tally, and it can be lower than [requested]: the server
  /// bundles what it could read and reports the rest in [failed] rather than
  /// throwing the whole selection away.
  final int successful;

  /// How many could not be read off the printer.
  final int failed;

  /// Single-use download credential, present only once the job is `ready`.
  final String? token;

  /// What the prepared file should be called. Echoed from the request, so it is
  /// known before the job finishes.
  final String? filename;

  /// The server's own explanation of a `failed` job.
  final String? message;

  /// Whether every selected file made it into the bundle. Only meaningful on a
  /// `ready` job.
  bool get isComplete => failed == 0 && successful >= requested;

  /// Fraction of the selection that is staged, or null when the job has not
  /// said anything countable yet — a bar has to stay indeterminate then rather
  /// than show a zero that never moves.
  ///
  /// Counts the failures too: they are files the server has finished with, and
  /// a bar that stalls at 6/7 over one unreadable file describes the wait
  /// wrongly.
  double? get progress {
    if (requested <= 0) return null;
    final done = successful + failed;
    if (done <= 0) return null;
    return (done / requested).clamp(0.0, 1.0);
  }

  static PrinterDownloadJobState _stateFrom(dynamic value) =>
      switch (toStringOrNull(value)) {
        'queued' => PrinterDownloadJobState.queued,
        'preparing' => PrinterDownloadJobState.preparing,
        'ready' => PrinterDownloadJobState.ready,
        'failed' => PrinterDownloadJobState.failed,
        'cancelled' => PrinterDownloadJobState.cancelled,
        _ => PrinterDownloadJobState.unknown,
      };
}
