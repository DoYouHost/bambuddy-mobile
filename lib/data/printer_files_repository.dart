import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/printer_download_job.dart';
import '../core/models/printer_file.dart';
import 'streamed_download.dart';

/// The printer's on-device storage: `GET/DELETE /printers/{id}/files`,
/// `/files/download[-zip]` and `/storage`, with every download streamed into a
/// file the caller names rather than into memory.
///
/// No polling — each list call opens a fresh FTP connection to the printer, so
/// the UI refreshes only on navigation, pull-to-refresh or a mutation, which is
/// what the server's own web UI does for fragile controllers.
class PrinterFilesRepository {
  PrinterFilesRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsDownloadJobs] until a `download-job` request has.
  final ServerVersionService? _serverVersion;

  /// Whether this server prepares a download in the background instead of
  /// behind a held request.
  ///
  /// Unknown → not offered, which is free here: the legacy route exists on every
  /// server generation and downloads the same bytes. Only the progress and the
  /// Cancel button are lost.
  late final _downloadJobs = ObservedCapability(
    ServerFeature.printerFilesDownloadJob,
    _serverVersion,
  );

  Future<bool> supportsDownloadJobs() => _downloadJobs.supported;

  /// Entries at [path], directories and files mixed, for the caller to sort.
  /// The listing rather than the bare list because an empty `files` has two
  /// meanings and only the response tells them apart.
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
    return data == null
        ? const PrinterStorage()
        : PrinterStorage.fromJson(data);
  }

  /// Streams one printer file into [savePath].
  ///
  /// No receive deadline, on any server version: both download routes answer
  /// only once the whole payload exists (the current one allows itself 30
  /// minutes, `MAX_PRINTER_ZIP_PREPARE_SECONDS`) while the printer feeds it over
  /// one FTP socket. Dio measures the gap between chunks, so the client-wide
  /// 15 s failed a transfer that was merely slow. `connectTimeout` still guards
  /// a server that is not there at all.
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

  /// Asks the server to prepare [paths] and answers as soon as there is a job to
  /// watch, so the preparation runs on the server — reportable and cancellable —
  /// instead of inside a request held open for up to 30 minutes.
  ///
  /// **Null means this server has no such route** and the caller falls back to
  /// [downloadZipTo] / [downloadFileTo]. A deleted printer 404s the same way,
  /// which is harmless: the legacy route answers that 404 itself, so the user
  /// sees the real error rather than silence.
  ///
  /// [sizes] lets the server check its free space before touching the printer,
  /// which is worth only as much as the numbers are real — hence [_vouchedSizes].
  /// [asZip] false is a native single-file download, for exactly one path.
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) => _downloadJobs.watching(
    () async {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.printerFilesJob(printerId),
        data: {
          'paths': paths,
          'sizes': ?_vouchedSizes(paths, sizes),
          'filename': filename,
          'as_zip': asZip,
        },
      );
      return PrinterDownloadJob.fromJson(res.data ?? const {});
    },
    absent: () => null,
    // Not a 403: this runs because the user pressed Download, so a refusal
    // is the one thing they have to be told.
    absentOn: const {404},
    // Against the usual rule, because this latch picks between two *working*
    // paths rather than between a feature and nothing: wrong costs a slower
    // download, not latching costs a 404 before every download.
    observing: treat404AsAbsent,
  );

  /// [sizes] as the server may be told them, or **null when they are not worth
  /// sending** — the whole map goes or none of it does.
  ///
  /// **Incomplete** is refused by the schema outright
  /// (`PrinterFilesDownloadRequest._validate_sizes` wants exactly [paths]), and
  /// **a size the listing could not read** arrives as `0`: claiming a gigabyte
  /// of models is empty passes the free-space check on a lie and fails the
  /// transfer halfway instead. Better no check than one on invented numbers.
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
  /// file behind it, so a broken stream needs a fresh job — and it expires in
  /// five minutes, which is why this runs the moment a job reports `ready`
  /// rather than after asking the user anything.
  ///
  /// No receive deadline, as everywhere else here: a phone that dozes
  /// mid-transfer looks like a stall and would lose a bundle that cannot be
  /// asked for again.
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
