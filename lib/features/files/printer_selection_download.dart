import 'dart:io';

import '../../core/models/printer_download_job.dart';
import '../../data/printer_files_repository.dart';
import '../common/file_export.dart';
import 'printer_download_job.dart';

/// One file in a selection: where it is on the printer, and how big the listing
/// said it was.
///
/// A record rather than a shared model class, because the two screens that
/// download a selection hold different things — the file manager a
/// `PrinterFile`, the archive's media sheet an `ArchiveMediaFile` — and the
/// download only ever needs these two fields of either.
typedef PrinterDownloadItem = ({String path, int size});

/// Pulls a selection of a printer's files down into a cache file.
///
/// Everything between "the user pressed Download" and "there is a file on disk"
/// is the same wherever the selection came from, and it is the part that is
/// easy to get subtly wrong: which route this server has, what a single file
/// means, and streaming into the cache rather than through memory — a printer's
/// card holds gigabytes, and reading a bundle into a list of bytes first costs
/// that size in RAM and then copies it into the file, peaking at twice it.
///
/// What is deliberately **not** here is everything after: the save dialog, the
/// message, and the diagnostic record. Those differ by screen — the record's id
/// is a wire value that a report is correlated on — and none of them is where
/// the mistakes were.
///
/// One instance per download; it holds the job it started, so [cancel] has
/// something to name.
class PrinterSelectionDownload {
  PrinterSelectionDownload(this._repo, {required this.printerId});

  final PrinterFilesRepository _repo;
  final int printerId;

  PrinterDownloadRun? _run;

  /// A Cancel that arrived before there was a run to name.
  ///
  /// [_asJob] awaits the capability latch before it builds one, and on the
  /// first download of a session that latch may itself be waiting on the
  /// server's version. A sheet dismissed inside that window used to leave the
  /// preparation to start afterwards and run to completion — the server pulling
  /// gigabytes off a printer for a screen that had gone.
  bool _cancelled = false;

  /// Downloads [files] under [fileName] and answers with the cache copy.
  ///
  /// [scratchName] is the part-file's name while the transfer runs; naming it
  /// after what is being downloaded means an interrupted transfer leaves one
  /// stale part-file rather than one per attempt.
  ///
  /// Throws [PrinterDownloadFailure] when a server-side preparation ends any
  /// way other than ready, and the repository's own exception for a transfer
  /// that fails. Either way nothing is left in the cache — [downloadToCacheFile]
  /// drops the part-file on the way out.
  ///
  /// [onJob] fires on every state a preparation reports, for a bar that can say
  /// "3 of 7 files" while nothing is transferring yet; [onProgress] is the byte
  /// progress of the transfer that follows.
  Future<File> run({
    required List<PrinterDownloadItem> files,
    required String fileName,
    required String scratchName,
    void Function(PrinterDownloadJob job)? onJob,
    void Function(int received, int total)? onProgress,
  }) {
    final paths = [for (final file in files) file.path];
    // A single file is asked for natively, as the browser does: the user gets
    // the model rather than a ZIP holding one model. The server accepts that
    // for exactly one path.
    final single = paths.length == 1;
    return downloadToCacheFile(
      scratchName: scratchName,
      download: (savePath) async {
        _throwIfCancelled();
        if (!await _asJob(
          files,
          fileName,
          savePath,
          single: single,
          onJob: onJob,
          onProgress: onProgress,
        )) {
          // No preparation route on this server: the same bytes, fetched the
          // way every server generation serves them — one held request, no
          // progress until the bundle exists, and no way to call it off.
          if (single) {
            await _repo.downloadFileTo(
              printerId,
              paths.first,
              savePath,
              onProgress: onProgress,
            );
          } else {
            await _repo.downloadZipTo(
              printerId,
              paths,
              savePath,
              onProgress: onProgress,
            );
          }
        }
        // The name is already known here; the served content type only matters
        // for routes that answer with more than one kind of file.
        return null;
      },
      name: (_) => fileName,
    );
  }

  /// Asks for the download to stop, wherever it has got to. Safe before a job
  /// exists and after one has finished; a cancellation that lands before there
  /// is anything to name is remembered rather than dropped.
  Future<void> cancel() async {
    _cancelled = true;
    await _run?.cancel();
  }

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const PrinterDownloadFailure(PrinterDownloadStopped.cancelled);
    }
  }

  /// Runs the download as a server-side preparation job, when this server has
  /// one. False means it has not, and the caller falls back to the legacy
  /// route.
  ///
  /// The gate is the repository's capability latch rather than an attempt: an
  /// unknown answer leaves the legacy path in place, which downloads the same
  /// bytes and costs only the progress and the Cancel button. A `1.2.6` daily
  /// from before the routes landed is told yes by the version table and answers
  /// 404, which the start call reports as "not supported" and falls back too.
  Future<bool> _asJob(
    List<PrinterDownloadItem> files,
    String fileName,
    String savePath, {
    required bool single,
    void Function(PrinterDownloadJob job)? onJob,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!await _repo.supportsDownloadJobs()) return false;
    // Checked after the await, not only before it: this is the window
    // [_cancelled] exists for. The legacy path is guarded the same way, at the
    // top of the download callback — it cannot be called off once it is in
    // flight, which is all the more reason not to start one nobody wants.
    _throwIfCancelled();
    final run = PrinterDownloadRun(_repo, printerId: printerId);
    _run = run;
    return run.download(
      paths: [for (final file in files) file.path],
      // Handed over whole; the repository decides whether they are worth
      // sending (`_vouchedSizes`), which is the one place that rule belongs.
      sizes: {for (final file in files) file.path: file.size},
      filename: fileName,
      asZip: !single,
      savePath: savePath,
      onJob: onJob,
      onProgress: onProgress,
    );
  }
}
