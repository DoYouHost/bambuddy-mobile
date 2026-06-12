import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';

/// Komendy sterujące drukarką (M4): pauza/wznów/stop, światło komory,
/// prędkość. Wszystkie to `POST` z pustym body; parametry idą w query.
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio (X-API-Key lub
/// Bearer). Każda metoda mapuje [DioException] na [AppApiException] — w tym
/// 403 → `AuthException(forbidden)`, gdy klucz nie ma `can_control_printer`.
/// Sukces = zwrot bez wyjątku; treści odpowiedzi nie potrzebujemy.
class PrinterCommandsRepository {
  PrinterCommandsRepository(this._dio);

  final Dio _dio;

  Future<void> pause(int printerId) => _post(Endpoints.printPause(printerId));

  Future<void> resume(int printerId) => _post(Endpoints.printResume(printerId));

  Future<void> stop(int printerId) => _post(Endpoints.printStop(printerId));

  /// Światło komory: `on=true|false`.
  Future<void> setChamberLight(int printerId, {required bool on}) =>
      _post(Endpoints.chamberLight(printerId), query: {'on': on});

  /// Prędkość: `mode` 1–4 (1 Silent … 4 Ludicrous). Wartość spoza zakresu
  /// odrzucamy lokalnie — serwer i tak zwróciłby 422.
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
