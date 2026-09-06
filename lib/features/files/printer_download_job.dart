import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import '../../core/models/printer_download_job.dart';
import '../../data/printer_files_repository.dart';

/// Why a prepared download produced no file.
enum PrinterDownloadStopped {
  /// The user pressed Cancel. The server has been told, and whatever it had
  /// staged is deleted.
  cancelled,

  /// The server gave up on the preparation — see [PrinterDownloadFailure.detail]
  /// for its own words (over-large selection, no disk space, its 30-minute
  /// ceiling, an unreadable file).
  failed,

  /// The job disappeared while being polled, or sat unfinished past the
  /// server's own ceiling. The server prunes abandoned staging and a restart
  /// drops every job it was holding, so this is a preparation that will never
  /// finish rather than one that failed.
  lost,
}

/// A prepared download that ended without a file. Thrown rather than returned
/// so the caller's existing `try`/`finally` discards the half-written cache
/// copy exactly as it does for a network failure.
class PrinterDownloadFailure implements Exception {
  const PrinterDownloadFailure(this.reason, {this.detail});

  final PrinterDownloadStopped reason;

  /// The server's message on a [PrinterDownloadStopped.failed] job, unlocalized
  /// — it names a limit or a file, which is worth more to the user than the
  /// generic sentence that would replace it.
  final String? detail;
}

/// Runs one printer-file download through the server's preparation job (server
/// #2850): start it, watch it, then stream what it staged.
///
/// The point of the job over the legacy `download-zip` is the middle step. That
/// route builds the whole bundle inside the request, so a multi-gigabyte
/// selection is a socket that says nothing for up to half an hour and cannot be
/// called off; here the same work reports how many files it has pulled and stops
/// when asked.
///
/// One instance per download — it holds the job it started, so [cancel] has
/// something to name.
class PrinterDownloadRun {
  PrinterDownloadRun(
    this._repo, {
    required this.printerId,
    this.pollInterval = const Duration(seconds: 1),
    this.maxWait = const Duration(minutes: 35),
  });

  final PrinterFilesRepository _repo;
  final int printerId;

  /// How often to ask for the job's state. A second is what the preparation
  /// changes on: each file lands as a whole, and the counts are read from a
  /// file the server rewrites per file.
  final Duration pollInterval;

  /// When to stop polling a job that never reaches a terminal state.
  ///
  /// The server ends its own jobs at `MAX_PRINTER_ZIP_PREPARE_SECONDS` (30
  /// minutes) by writing them `failed`, so in the ordinary case this never
  /// fires. What it covers is the server going away mid-preparation: the status
  /// it left on disk still reads `preparing`, nothing will ever rewrite it, and
  /// without a ceiling here the screen polls that forever. Slack over the
  /// server's own limit, so its answer is always the one the user sees.
  final Duration maxWait;

  String? _jobId;
  bool _cancelling = false;

  /// Aborts the transfer, for the caller that has given up on the file
  /// altogether — see [cancel].
  final _transfer = CancelToken();

  /// Prepares [paths] and streams the result into [savePath].
  ///
  /// **False means this server has no preparation route** and nothing has been
  /// downloaded — the caller falls back to the legacy path, which every server
  /// still serves. True means [savePath] holds the bundle.
  ///
  /// [onJob] fires on every state the job reports, for a progress bar that can
  /// say "3 of 7 files" while nothing is transferring yet. [onProgress] is the
  /// byte progress of the transfer that follows.
  Future<bool> download({
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    required bool asZip,
    required String savePath,
    void Function(PrinterDownloadJob job)? onJob,
    void Function(int received, int total)? onProgress,
  }) async {
    final started = await _repo.startDownloadJob(
      printerId,
      paths: paths,
      sizes: sizes,
      filename: filename,
      asZip: asZip,
    );
    if (started == null) return false;
    var job = started;
    _jobId = job.jobId;
    onJob?.call(job);

    final giveUpAt = clock.now().add(maxWait);
    while (!job.state.isTerminal) {
      // Checked before sleeping as well as after, so a Cancel pressed while the
      // start request was in flight is acted on rather than waited out.
      await _stopIfCancelling();
      await Future<void>.delayed(pollInterval);
      await _stopIfCancelling();
      final next = await _repo.downloadJob(printerId, job.jobId);
      if (next == null) {
        // A job that vanishes *while being cancelled* is the cancellation
        // landing, not a loss: the poll and the DELETE are in flight together,
        // and whichever the server answers first, what the user asked for
        // happened.
        throw PrinterDownloadFailure(
          _cancelling
              ? PrinterDownloadStopped.cancelled
              : PrinterDownloadStopped.lost,
        );
      }
      job = next;
      onJob?.call(job);
      if (clock.now().isAfter(giveUpAt)) {
        throw const PrinterDownloadFailure(PrinterDownloadStopped.lost);
      }
    }

    switch (job.state) {
      case PrinterDownloadJobState.ready:
        break;
      case PrinterDownloadJobState.cancelled:
        throw const PrinterDownloadFailure(PrinterDownloadStopped.cancelled);
      default:
        throw PrinterDownloadFailure(
          PrinterDownloadStopped.failed,
          detail: job.message,
        );
    }

    // A Cancel that landed while the last poll was in flight arrives here with
    // the job already `ready`. Checked before the transfer rather than after,
    // or a cancelled download would still stream and still raise the save
    // dialog.
    await _stopIfCancelling();

    final token = job.token;
    if (token == null) {
      // `ready` without a token cannot be downloaded and cannot be retried —
      // the staged file is addressed by that token alone.
      throw const PrinterDownloadFailure(PrinterDownloadStopped.lost);
    }
    try {
      await _repo.downloadPreparedTo(
        printerId,
        token: token,
        filename: job.filename ?? filename,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: _transfer,
      );
    } on Object {
      // A transfer [cancel] aborted reports as itself rather than as a network
      // failure — the screen it belonged to has gone, and the record should say
      // what happened rather than blame the connection.
      if (_cancelling) {
        throw const PrinterDownloadFailure(PrinterDownloadStopped.cancelled);
      }
      rethrow;
    }
    // Consumed: the token is single-use and the server has deleted the staging
    // copy, so there is nothing left for [cancel] to clean up.
    _jobId = null;
    return true;
  }

  /// Asks for the download to stop, wherever it has got to: the server-side
  /// preparation, and a transfer already in flight.
  ///
  /// Safe before a job exists and after one has finished. The run itself ends
  /// by throwing [PrinterDownloadStopped.cancelled].
  ///
  /// Aborting the transfer too is for the caller that has given up on the file
  /// — the screen that raised it is gone, so the bytes would land in a cache
  /// copy nothing will save. It costs nothing the user could have had anyway:
  /// the token is single-use and the server deletes what it staged, so a
  /// half-finished transfer was never resumable.
  Future<void> cancel() async {
    _cancelling = true;
    if (!_transfer.isCancelled) _transfer.cancel('download cancelled');
    final id = _jobId;
    if (id == null) return;
    _jobId = null;
    await _repo.cancelDownloadJob(printerId, id);
  }

  Future<void> _stopIfCancelling() async {
    if (!_cancelling) return;
    await cancel();
    throw const PrinterDownloadFailure(PrinterDownloadStopped.cancelled);
  }
}
