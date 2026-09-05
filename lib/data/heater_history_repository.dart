import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/heater_history.dart';

/// REST data source for printer heater history
/// (`GET /printer-sensor-history/{printerId}?hours=N&kinds=…`).
///
/// Auth adds the shared [AuthInterceptor]; [DioException] is mapped to
/// [AppApiException].
class HeaterHistoryRepository {
  HeaterHistoryRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsHistory] until a real call has answered it.
  final ServerVersionService? _serverVersion;

  /// Whether to offer the history chart at all.
  ///
  /// What the route did outranks the version, and a 403 (no
  /// `printer_sensor_history:read`) outranks both — see [ObservedCapability].
  /// Unknown → offered, unlike most gates: a wrongly offered chart costs one
  /// error line in a sheet the user opened, while wrongly hiding it takes the
  /// feature away from a healthy server whose version read merely failed. The
  /// first call settles it either way.
  late final _history = ObservedCapability(
    ServerFeature.printerSensorHistory,
    _serverVersion,
    whenUnknown: true,
  );

  Future<bool> supportsHistory() => _history.supported;

  /// Fetch the last [hours] of samples (backend clamps to 1..168) for [kinds];
  /// an empty list asks for every sensor the server records.
  Future<HeaterHistory> fetch(
    int printerId, {
    int hours = 24,
    List<String> kinds = const [],
  }) =>
      // No 404 anywhere in `routes/printer_sensor_history.py`: a printer with
      // nothing recorded answers an empty series, so a 404 is the route.
      _history.watching(observing: treat404AsAbsent, () async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.printerSensorHistory(printerId),
          queryParameters: {
            'hours': hours,
            if (kinds.isNotEmpty) 'kinds': kinds.join(','),
          },
        );
        return HeaterHistory.fromJson(res.data ?? const {});
      });
}
