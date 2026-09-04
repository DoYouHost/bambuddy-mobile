import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/printer_download_job.dart';
import '../core/models/printer_file.dart';
import 'streamed_download.dart';

/// REST data source for the printer's on-device storage (file manager).
///
/// Backs `GET/DELETE /printers/{id}/files`, `/files/download[-zip]` and
/// `/storage`. Listing and storage read-only; a download is streamed into a
/// file the caller names, never into memory — see [streamDownload].
///
/// No polling: each list call opens a fresh FTP connection to the printer, so
/// the UI refreshes only on navigation, pull-to-refresh, or after a mutation
/// (mirrors the server web UI, which throttles for fragile controllers).
class PrinterFilesRepository {
  PrinterFilesRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsDownloadJobs] until a `download-job` request has.
  final ServerVersionService? _serverVersion;

  /// Whether this server prepares a download in the background instead of
  /// behind a held request.
  ///
  /// Unknown → not offered, which is free here in a way it rarely is: the
  /// legacy route the app falls back to exists on every server generation and
  /// downloads the same bytes. The only thing lost is the progress and the
  /// Cancel button.
  late final _downloadJobs = ObservedCapability(
    ServerFeature.printerFilesDownloadJob,
    _serverVersion,
  );

  Future<bool> supportsDownloadJobs() => _downloadJobs.supported;

  /// List entries at [path] (default root). Directories and files mixed;
  /// caller sorts. Auth/network errors bubble up via [guard].
  ///
  /// Returns the listing rather than the bare list because an empty `files` has
  /// two meanings and only the response can tell them apart — see
  /// [PrinterFileListing].
  Future<PrinterFileListing> listFiles(int printerId, String path) async {
    final data = await guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerFiles(printerId),
        queryParameters: {'path': path},
      );
      return res.data;
    });
    return PrinterFileListing.fromJson(data ?? const {});
  }

  /// Storage usage. Degrades to an empty [PrinterStorage] on non-auth errors
  /// (a printer that doesn't report storage must not break the screen).
  Future<PrinterStorage> fetchStorage(int printerId) async {
    final data = await guardOrNull(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerStorage(printerId),
      );
      return res.data;
    });
    return data == null ? const PrinterStorage() : PrinterStorage.fromJson(data);
  }

  /// Streams one printer file into [savePath].
  ///
  /// No receive deadline, on any server version: both download routes answer
  /// only once the whole payload exists — older servers built it in memory,
  /// current ones assemble it on disk and allow themselves 30 minutes
  /// (`MAX_PRINTER_ZIP_PREPARE_SECONDS`) — while the printer feeds it over its
  /// single FTP socket. Dio's deadline measures the gap between chunks, so the
  /// client-wide 15 s failed a transfer that was merely slow, and the user
  /// could not tell that from a broken one. `connectTimeout` still guards a
  /// server that is not there at all.
  Future<void> downloadFileTo(
    int printerId,
    String path,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await streamDownload(
      _dio,
      Endpoints.printerFileDownload(printerId),
      savePath,
      queryParameters: {'path': path},
      onProgress: onProgress,
    );
  }

  /// Streams [paths] into [savePath] as one ZIP.
  ///
  /// The body stays `{"paths": [...]}`: every server version accepts it, and
  /// the optional `sizes` the newest one takes only buys an earlier rejection.
  Future<void> downloadZipTo(
    int printerId,
    List<String> paths,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await streamDownload(
      _dio,
      Endpoints.printerFilesDownloadZip(printerId),
      savePath,
      method: 'POST',
      data: {'paths': paths},
      onProgress: onProgress,
    );
  }

  /// Asks the server to prepare [paths] and answers as soon as it has a job to
  /// watch — the preparation itself then runs on the server, reportable and
  /// cancellable, instead of inside a request held open for up to 30 minutes.
  ///
  /// **Null means this server has no such route**, and the caller must fall
  /// back to [downloadZipTo] / [downloadFileTo]. A 404 cannot be told apart
  /// from a printer that has just been deleted (`_load_printer_or_404` answers
  /// the same status), and that ambiguity is harmless: the legacy route answers
  /// that 404 itself, so the user sees the real error rather than a silent
  /// nothing.
  ///
  /// [sizes] buys the only thing it can: the server checks its own free space
  /// before touching the printer, so an impossible selection is refused in a
  /// second rather than after a long transfer. What it is worth depends
  /// entirely on the numbers being real, which is why the map is vouched for
  /// here rather than at each call site — see [_vouchedSizes].
  ///
  /// [asZip] false is a native single-file download, which the server accepts
  /// for exactly one path.
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.printerFilesJob(printerId),
        data: {
          'paths': paths,
          'sizes': ?_vouchedSizes(paths, sizes),
          'filename': filename,
          'as_zip': asZip,
        },
      );
      _downloadJobs.observe(present: true);
      return PrinterDownloadJob.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      _downloadJobs.observeFailure(status);
      if (status == 404) return null;
      throw mapDioException(e);
    }
  }

  /// [sizes] as the server may be told them, or **null when they are not worth
  /// sending** — the whole map goes or none of it does.
  ///
  /// Two ways a map fails to be worth sending, and they cost the same:
  ///
  ///  * **Incomplete.** The schema refuses a partial map outright
  ///    (`PrinterFilesDownloadRequest._validate_sizes`: its keys must be
  ///    exactly [paths]).
  ///  * **A size the listing could not read**, which arrives as `0`. Claiming
  ///    a gigabyte of models is empty passes the server's free-space check on
  ///    a lie, and the transfer then fails halfway through instead. Better no
  ///    check than a check on invented numbers.
  ///
  /// The rule lives here because it is about what this route may be told, not
  /// about the screen that happens to be asking — it was written out once per
  /// caller before it lived here.
  Map<String, int>? _vouchedSizes(List<String> paths, Map<String, int> sizes) {
    if (sizes.length != paths.length) return null;
    if (sizes.values.any((size) => size <= 0)) return null;
    return sizes;
  }

  /// One poll of a job's state. **Null means the job itself is gone** — an id
  /// the server no longer holds, or one belonging to another printer.
  ///
  /// Deliberately does not touch the capability latch: a 404 here is about the
  /// job, not about the route family, and recording it as absence would send
  /// the next download down the legacy path over an expired staging folder.
  Future<PrinterDownloadJob?> downloadJob(int printerId, String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerFilesJobStatus(printerId, jobId),
      );
      return PrinterDownloadJob.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw mapDioException(e);
    }
  }

  /// Stops a job and deletes whatever it had already staged, including a bundle
  /// that was already `ready`.
  ///
  /// A job the server no longer knows is not an error: cancelling something
  /// that has already finished, expired or been cancelled elsewhere leaves
  /// exactly the state the caller asked for.
  Future<void> cancelDownloadJob(int printerId, String jobId) async {
    try {
      await _dio.delete<dynamic>(
        Endpoints.printerFilesJobStatus(printerId, jobId),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
      throw mapDioException(e);
    }
  }

  /// Streams a `ready` job's bundle into [savePath].
  ///
  /// The token authorises this one transfer and the server deletes the staged
  /// file behind it, so there is no retry: a stream that breaks needs a fresh
  /// job. It is also short-lived (five minutes), which is why this is called
  /// the moment a job reports `ready` rather than after asking the user
  /// anything.
  ///
  /// No receive deadline, as everywhere else on this screen: the bytes come off
  /// the server's own disk here, but a phone that dozes mid-transfer looks
  /// exactly like a stall and would lose a bundle that cannot be asked for
  /// again.
  Future<void> downloadPreparedTo(
    int printerId, {
    required String token,
    required String filename,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await streamDownload(
      _dio,
      Endpoints.printerFilesPrepared(printerId, token, filename),
      savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Delete a single file. 404/500 surface as [ApiException] via [guard].
  Future<void> deleteFile(int printerId, String path) => guard(
        () => _dio.delete<dynamic>(
          Endpoints.printerFileDelete(printerId),
          queryParameters: {'path': path},
        ),
      );
}
