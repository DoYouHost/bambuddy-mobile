import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/printer_file.dart';

/// REST data source for the printer's on-device storage (file manager).
///
/// Backs `GET/DELETE /printers/{id}/files`, `/files/download[-zip]` and
/// `/storage`. Listing and storage read-only; download returns raw bytes for
/// the caller to hand to the system "save file" dialog.
///
/// No polling: each list call opens a fresh FTP connection to the printer, so
/// the UI refreshes only on navigation, pull-to-refresh, or after a mutation
/// (mirrors the server web UI, which throttles for fragile controllers).
class PrinterFilesRepository {
  PrinterFilesRepository(this._dio);

  final Dio _dio;

  /// No receive deadline for a download, on any server version. Both routes
  /// answer only once the whole payload exists — older servers built it in
  /// memory, current ones assemble it on disk and allow themselves 30 minutes
  /// (`MAX_PRINTER_ZIP_PREPARE_SECONDS`) — while the printer feeds it over one
  /// FTP socket. The client-wide 15 s in `api_client.dart` measures the gap
  /// between bytes, so it fails a transfer that is merely slow, and the user
  /// cannot tell that from a broken one. `connectTimeout` still guards a server
  /// that is not there at all.
  static const Duration _downloadTimeout = Duration.zero;

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

  /// Download a single file's raw bytes.
  Future<Uint8List> downloadFile(int printerId, String path) => guard(() async {
        final res = await _dio.get<List<int>>(
          Endpoints.printerFileDownload(printerId),
          queryParameters: {'path': path},
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: _downloadTimeout,
          ),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// Download [paths] bundled as a single ZIP archive.
  ///
  /// The body stays `{"paths": [...]}`: every server version accepts it, and
  /// the optional `sizes` the newest one takes only buys an earlier rejection.
  Future<Uint8List> downloadZip(int printerId, List<String> paths) =>
      guard(() async {
        final res = await _dio.post<List<int>>(
          Endpoints.printerFilesDownloadZip(printerId),
          data: {'paths': paths},
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: _downloadTimeout,
            sendTimeout: _downloadTimeout,
          ),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// Delete a single file. 404/500 surface as [ApiException] via [guard].
  Future<void> deleteFile(int printerId, String path) => guard(
        () => _dio.delete<dynamic>(
          Endpoints.printerFileDelete(printerId),
          queryParameters: {'path': path},
        ),
      );
}
