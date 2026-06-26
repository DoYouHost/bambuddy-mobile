import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';

/// Printer control commands (M4): pause/resume/stop, chamber light, speed.
/// All are `POST` with empty body; parameters go in query.
///
/// Auth adds [AuthInterceptor] to the shared Dio (X-API-Key or Bearer).
/// Each method maps [DioException] to [AppApiException] — including 403 →
/// `AuthException(forbidden)` if key lacks `can_control_printer`.
/// Success = return without exception; response content not needed.
class PrinterCommandsRepository {
  PrinterCommandsRepository(this._dio);

  final Dio _dio;

  Future<void> pause(int printerId) => _post(Endpoints.printPause(printerId));

  Future<void> resume(int printerId) => _post(Endpoints.printResume(printerId));

  Future<void> stop(int printerId) => _post(Endpoints.printStop(printerId));

  /// Acknowledge the build plate has been cleared (lets the scheduler start the
  /// next queued print). Empty body.
  Future<void> clearPlate(int printerId) =>
      _post(Endpoints.printerClearPlate(printerId));

  /// Chamber light: `on=true|false`.
  Future<void> setChamberLight(int printerId, {required bool on}) =>
      _post(Endpoints.chamberLight(printerId), query: {'on': on});

  /// Print speed: `mode` 1–4 (1 Silent … 4 Ludicrous). Out-of-range values
  /// rejected locally — server would return 422 anyway.
  Future<void> setPrintSpeed(int printerId, int mode) {
    assert(mode >= 1 && mode <= 4, 'speed mode poza zakresem 1..4: $mode');
    return _post(Endpoints.printSpeed(printerId), query: {'mode': mode});
  }

  Future<void> _post(String path, {Map<String, dynamic>? query}) async {
    try {
      await _dio.post<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
