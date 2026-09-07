import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/firmware.dart';

/// REST data source for printer firmware.
///
/// Currently uses reads only ([fetchUpdates]/[fetchForPrinter]) — to show version
/// and "update available" flag. Execution methods ([prepareUpload]/[startUpload]/
/// [uploadStatus]) are ready (typed) so future update flow can be integrated without
/// data-layer changes.
///
/// Auth adds [AuthInterceptor] to the shared Dio. Defensive parsing; single-printer
/// reads degrade to `null` on non-auth errors — missing firmware data won't break the card.
class FirmwareRepository {
  FirmwareRepository(this._dio);

  final Dio _dio;

  /// `GET /firmware/updates` — firmware for entire farm in one request.
  Future<FirmwareUpdatesResponse> fetchUpdates() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.firmwareUpdates,
      );
      return FirmwareUpdatesResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /firmware/updates/{id}` — firmware for one printer. Auth errors bubble up
  /// (UI → /setup); other errors degrade to `null`.
  Future<FirmwareUpdateInfo?> fetchForPrinter(int printerId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.firmwareUpdate(printerId),
      );
      final body = res.data;
      return body == null ? null : FirmwareUpdateInfo.fromJson(body);
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

  // --- Firmware update execution (for future use; not yet used in UI) ---

  /// `GET /firmware/updates/{id}/prepare` — probe before firmware upload.
  Future<FirmwareUploadPrepare> prepareUpload(int printerId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.firmwarePrepare(printerId),
      );
      return FirmwareUploadPrepare.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `POST /firmware/updates/{id}/upload` — start upload. Optional `version`
  /// (server uses latest if omitted). 403 = key lacks permissions.
  Future<FirmwareUploadStartResult> startUpload(
    int printerId, {
    String? version,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.firmwareUpload(printerId),
        queryParameters: {'version': ?version},
      );
      return FirmwareUploadStartResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /firmware/updates/{id}/upload/status` — upload progress.
  Future<FirmwareUploadStatus> uploadStatus(int printerId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.firmwareUploadStatus(printerId),
      );
      return FirmwareUploadStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
