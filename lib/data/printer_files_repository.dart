import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
  PrinterFilesRepository(this._dio);

  final Dio _dio;

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

  /// Delete a single file. 404/500 surface as [ApiException] via [guard].
  Future<void> deleteFile(int printerId, String path) => guard(
        () => _dio.delete<dynamic>(
          Endpoints.printerFileDelete(printerId),
          queryParameters: {'path': path},
        ),
      );
}
