import 'dart:async';

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
  ///
  /// The ceiling is the server's, not a constant: 60 up to 1.2.5.x and 65 from
  /// 1.2.6 (`MAX_CHAMBER_TEMP_C`). The assert takes the higher one because it
  /// guards against a caller bug, not against an old server — the UI never
  /// offers more than [chamberMaxTargetProvider] allows, and a server that
  /// disagrees answers 422, which is a server answer and not an assertion.
  Future<void> setChamberTemperature(int printerId, int target) {
    assert(target >= 0 && target <= 65, 'chamber target out of range: $target');
    return _post(Endpoints.chamberTemperature(printerId),
        query: {'target': target});
  }

  /// Airduct flap mode. Only call for models with an airduct (P2S/X2D/H2*).
  Future<void> setAirductMode(int printerId, {required bool heating}) =>
      _post(Endpoints.airductMode(printerId),
          query: {'mode': heating ? 'heating' : 'cooling'});

  /// Fan speed as a percentage. [fan] is 'part', 'aux', 'chamber', or — from
  /// server 1.2.5.2 — 'aux2' for the left auxiliary fan. Only send 'aux2' for a
  /// printer whose status reports `left_aux_fan_speed`: the server rejects it
  /// with 400 otherwise, and an older one rejects it always.
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

  /// Clear the printer's active error dialog. Printer-wide by nature: the
  /// firmware command behind it (`clean_print_error`) takes no code and drops
  /// whatever is on screen, so there is no per-error variant to offer.
  Future<void> clearHmsErrors(int printerId) =>
      _post(Endpoints.hmsClear(printerId));

  /// Run one of the firmware's remediation actions for a fault.
  ///
  /// [printError] must be the fault's `full_code` **verbatim** — the server
  /// validates it as 8 or 16 hex digits and the firmware matches on it; a code
  /// rebuilt from `attr`/`code` is silently ignored by the printer. [jobId] is
  /// the fault's own `job_id` snapshot, omitted for an idle-state error.
  ///
  /// Throws `ApiException(statusCode: 502)` when the publish succeeded but the
  /// printer sent nothing back within the server's 2.5s window — a real outcome
  /// worth its own message, not a transport failure.
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) =>
      _post(Endpoints.hmsExecuteAction(printerId), data: {
        'print_error': printError,
        'action': action,
        if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
      });

  /// Nudge the printer into republishing its full state. Read-level route, so
  /// it works with a key that may not control anything; callers treat it as a
  /// hint and ignore both the answer and a 400 from a disconnected printer.
  Future<void> refreshStatus(int printerId) =>
      _post(Endpoints.printerRefreshStatus(printerId));

  /// [refreshStatus] as the hint it is: sent for each printer and then
  /// forgotten.
  ///
  /// Nothing useful comes back — the republish arrives over the WebSocket, not
  /// in this response — and every way it can fail is one the caller already
  /// accepts: an offline printer answers 400, a narrow key may be refused, and
  /// neither is a reason to fail whatever the user actually asked for. Returning
  /// void rather than a future says that out loud, so no call site has to
  /// re-derive the same `unawaited(...).catchError(...)` and get it right.
  void nudgeRepublish(Iterable<int> printerIds) {
    for (final id in printerIds) {
      unawaited(refreshStatus(id).catchError((Object _) {}));
    }
  }

  /// Load filament from one slot. [trayId] is the global tray number from
  /// [amsLoadTrayId] — not the slot's local id.
  Future<void> amsLoad(int printerId, int trayId) {
    assert(_isLoadableTrayId(trayId), 'tray id not loadable: $trayId');
    return _post(Endpoints.amsLoad(printerId), query: {'tray_id': trayId});
  }

  /// Unload the filament currently in the extruder — printer-wide, see
  /// [Endpoints.amsUnload].
  Future<void> amsUnload(int printerId) =>
      _post(Endpoints.amsUnload(printerId));

  /// Re-read the RFID tag of one AMS slot. Ids are local to the unit.
  Future<void> refreshAmsSlot(
    int printerId, {
    required int amsId,
    required int slotId,
  }) =>
      _post(Endpoints.amsSlotRfidRefresh(printerId, amsId, slotId));

  Future<void> _post(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _dio.post<dynamic>(path, queryParameters: query, data: data);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// The global tray number `POST /ams/load` takes for a slot, or null where the
/// server has no encoding for it.
///
/// An external spool is already global (254 = Ext-L, 255 = Ext-R), a regular
/// AMS slot is `unit * 4 + slot`. The one hole is AMS-HT: its units are numbered
/// from 128, so the same arithmetic lands far outside the accepted range and the
/// server answers 400 — the caller hides the action instead of offering a button
/// that cannot work.
int? amsLoadTrayId({required int amsId, required int trayId}) {
  // Only the two external ids pass through unchanged. Accepting the whole
  // loadable range here would turn an unexpected external id into a valid AMS
  // slot number — the printer would load a different spool, and nothing on the
  // way would flag it.
  if (amsId == 255) return trayId == 254 || trayId == 255 ? trayId : null;
  if (amsId >= 128) return null;
  final global = amsId * 4 + trayId;
  return _isLoadableTrayId(global) ? global : null;
}

/// Mirrors the server's own validation (`printers.py` `ams_load`): AMS slots
/// 0..15, the A2L AMS-Lite's normalised 24..27, and the two external ids.
bool _isLoadableTrayId(int trayId) =>
    (trayId >= 0 && trayId <= 15) ||
    (trayId >= 24 && trayId <= 27) ||
    trayId == 254 ||
    trayId == 255;
