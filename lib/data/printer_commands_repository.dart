import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';

/// Printer control commands: pause/resume/stop, chamber light, speed, and
/// temperatures (nozzle/bed/chamber) + airduct mode.
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
    assert(mode >= 1 && mode <= 4, 'speed mode out of range 1..4: $mode');
    return _post(Endpoints.printSpeed(printerId), query: {'mode': mode});
  }

  /// Nozzle target temperature (°C, 0 turns heating off). [nozzle] 0=right/
  /// default, 1=left (dual-head only).
  Future<void> setNozzleTemperature(int printerId, int target,
      {int nozzle = 0}) {
    assert(target >= 0 && target <= 320, 'nozzle target out of range: $target');
    return _post(Endpoints.nozzleTemperature(printerId),
        query: {'target': target, 'nozzle': nozzle});
  }

  /// Bed target temperature (°C, 0 turns heating off).
  Future<void> setBedTemperature(int printerId, int target) {
    assert(target >= 0 && target <= 140, 'bed target out of range: $target');
    return _post(Endpoints.bedTemperature(printerId), query: {'target': target});
  }

  /// Chamber target temperature (°C, 0 turns heating off). Only call for models
  /// with an active chamber heater — the server 400s otherwise.
  Future<void> setChamberTemperature(int printerId, int target) {
    assert(target >= 0 && target <= 60, 'chamber target out of range: $target');
    return _post(Endpoints.chamberTemperature(printerId),
        query: {'target': target});
  }

  /// Airduct flap mode. Only call for models with an airduct (P2S/X2D/H2*).
  Future<void> setAirductMode(int printerId, {required bool heating}) =>
      _post(Endpoints.airductMode(printerId),
          query: {'mode': heating ? 'heating' : 'cooling'});

  /// Fan speed as a percentage. [fan] is 'part', 'aux', or 'chamber'.
  Future<void> setFanSpeed(int printerId, String fan, int speed) {
    assert(speed >= 0 && speed <= 100, 'fan speed out of range: $speed');
    return _post(Endpoints.fanSpeed(printerId),
        query: {'fan': fan, 'speed': speed});
  }

  /// Select active extruder (0=right, 1=left) on dual-nozzle printers.
  Future<void> selectExtruder(int printerId, int extruder) {
    assert(extruder == 0 || extruder == 1, 'extruder must be 0 or 1');
    return _post(Endpoints.selectExtruder(printerId),
        query: {'extruder': extruder});
  }

  /// Start AMS drying. [temp] 45–85 °C, [duration] 1–24 hours. Filament is
  /// backfilled server-side from the loaded tray when omitted.
  Future<void> startDrying(
    int printerId, {
    required int amsId,
    required int temp,
    required int duration,
    String filament = '',
  }) {
    assert(temp >= 45 && temp <= 85, 'dry temp out of range: $temp');
    assert(duration >= 1 && duration <= 24, 'dry duration out of range');
    return _post(Endpoints.dryingStart(printerId), query: {
      'ams_id': amsId,
      'temp': temp,
      'duration': duration,
      if (filament.isNotEmpty) 'filament': filament,
    });
  }

  /// Stop AMS drying for one unit.
  Future<void> stopDrying(int printerId, {required int amsId}) =>
      _post(Endpoints.dryingStop(printerId), query: {'ams_id': amsId});

  /// Relative nozzle-bed gap jog (mm). Negative decreases the gap ("up").
  /// [force] bypasses soft endstops (use when Z is not homed). The server
  /// inverts the Z sign on A1 bed-slingers so "up" is consistent across models.
  Future<void> bedJog(int printerId, double distance, {bool force = false}) {
    assert(distance != 0 && distance.abs() <= 200, 'bed jog out of range');
    return _post(Endpoints.bedJog(printerId),
        query: {'distance': distance, 'force': force});
  }

  /// Relative toolhead X/Y jog (mm).
  Future<void> xyJog(int printerId, {double x = 0, double y = 0}) {
    assert((x != 0 || y != 0) && x.abs() <= 200 && y.abs() <= 200,
        'xy jog out of range');
    return _post(Endpoints.xyJog(printerId), query: {'x': x, 'y': y});
  }

  /// Relative extrusion (mm). Positive extrudes, negative retracts. Firmware
  /// refuses extrusion below the min-extrude temperature, so a cold call is
  /// rejected at the printer.
  Future<void> extruderJog(int printerId, double distance) {
    assert(distance != 0 && distance.abs() <= 100, 'extruder jog out of range');
    return _post(Endpoints.extruderJog(printerId),
        query: {'distance': distance});
  }

  /// Run the printer's full auto-home sequence (`G28`).
  Future<void> homeAxes(int printerId) =>
      _post(Endpoints.homeAxes(printerId), query: {'axes': 'all'});

  Future<void> _post(String path, {Map<String, dynamic>? query}) async {
    try {
      await _dio.post<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
