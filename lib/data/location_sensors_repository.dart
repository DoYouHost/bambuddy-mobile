import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/json_utils.dart';
import '../core/models/location_sensor.dart';

/// REST data source for the Home Assistant sensors a storage location can be
/// given — `GET /location-ha-sensors/` and the per-location readings behind it
/// (server #2827).
///
/// Read-only by design: binding an entity needs `smart_plugs:create`, which no
/// API key can hold (`_APIKEY_DENIED_PERMISSIONS`, `backend/app/core/auth.py`),
/// and the picker behind it needs the Home Assistant URL and token that only
/// the server's own settings hold.
///
/// Auth adds the shared `AuthInterceptor`; [DioException] is mapped to
/// [AppApiException].
class LocationSensorsRepository {
  LocationSensorsRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsLocationSensors] until the listing has.
  final ServerVersionService? _serverVersion;

  /// Whether the server has the route family at all. Unknown → not offered,
  /// which costs nothing: every surface here is hidden unless a sensor is
  /// actually bound, so all the gate saves is one 404 on an older server.
  late final _sensors = ObservedCapability(
    ServerFeature.locationHaSensors,
    _serverVersion,
  );

  Future<bool> supportsLocationSensors() => _sensors.supported;

  /// Every binding the server holds, so a caller can tell which locations have
  /// something to show before asking any of them for a reading.
  ///
  /// A 404 (no such route) or 403 (a key without `smart_plugs:read`) answers
  /// with an empty list rather than throwing: the whole feature is additive,
  /// and the latch above has already recorded why there is nothing to add.
  Future<List<LocationSensorBinding>> listBindings() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.locationHaSensors);
      _sensors.observe(present: true);
      return parseJsonList(res.data, LocationSensorBinding.fromJson);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      _sensors.observeFailure(status);
      if (status == 404 || status == 403) return const [];
      throw mapDioException(e);
    }
  }

  /// The live state of one location's card-visible sensors, in the order the
  /// bindings were sorted into. A sensor the poller has not reached yet comes
  /// back with its last persisted state and `reachable: false` rather than
  /// dropping out of the list on every server restart.
  Future<List<LocationSensorReading>> readings(int locationId) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.locationHaSensorReadings(locationId),
      );
      _sensors.observe(present: true);
      return parseJsonList(res.data, LocationSensorReading.fromJson);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      _sensors.observeFailure(status);
      if (status == 404 || status == 403) return const [];
      throw mapDioException(e);
    }
  }
}
