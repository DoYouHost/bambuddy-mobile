import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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

  /// What the route actually did, once it has been called: `false` after a 404
  /// on a server whose version claimed otherwise, `true` after any answer.
  bool? _observedRoute;

  /// Whether this caller was refused the route (403 — no
  /// `printer_sensor_history:read`). Kept apart from [_observedRoute] because
  /// it answers a different question: the route is there, this session may not
  /// read it. Both latches live as long as the instance, which is rebuilt when
  /// `apiClientProvider` changes and on the dashboard's pull-to-refresh — the
  /// only in-app way to notice a permission granted server-side, since a hidden
  /// shortcut never calls the route again.
  bool _forbidden = false;

  /// Whether to offer the history chart at all.
  ///
  /// Observation first, version second. Unknown version → `true`, unlike
  /// [ServerVersionService.supports]: what a wrongly offered chart costs here
  /// is one error line in a sheet the user opened, while wrongly hiding it
  /// takes the feature away from a healthy server whose version read merely
  /// failed. The first call settles it either way.
  Future<bool> supportsHistory() async {
    if (_forbidden) return false;
    final observed = _observedRoute;
    if (observed != null) return observed;
    final version = await _serverVersion?.current();
    return version?.supports(ServerFeature.printerSensorHistory) ?? true;
  }

  /// Fetch the last [hours] of samples (backend clamps to 1..168) for [kinds];
  /// an empty list asks for every sensor the server records.
  Future<HeaterHistory> fetch(
    int printerId, {
    int hours = 24,
    List<String> kinds = const [],
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerSensorHistory(printerId),
        queryParameters: {
          'hours': hours,
          if (kinds.isNotEmpty) 'kinds': kinds.join(','),
        },
      );
      _observedRoute = true;
      _forbidden = false;
      return HeaterHistory.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 404:
          _observedRoute = false;
        case 403:
          _forbidden = true;
      }
      throw mapDioException(e);
    }
  }
}
