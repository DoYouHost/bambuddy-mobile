import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/models/ams_history.dart';

/// REST data source for AMS sensor history
/// (`GET /ams-history/{printerId}/{amsId}?hours=N`).
///
/// Auth adds the shared [AuthInterceptor]; [DioException] is mapped to
/// [AppApiException]. Native backend only — Spoolman has no such endpoint.
class AmsHistoryRepository {
  AmsHistoryRepository(this._dio);

  final Dio _dio;

  /// Whether to offer the history chart at all.
  ///
  /// Observation only, with no version row behind it: the route shipped in
  /// v0.1.5 (server commit 0dc76746, December 2025), older than any server this
  /// app talks to, so a threshold could only ever hide the chart from a healthy
  /// server whose version read failed. What is worth watching is the
  /// permission — a restricted key or group gets a 403 that no version knows
  /// about.
  final _history = ObservedCapability.unversioned();

  Future<bool> supportsHistory() => _history.supported;

  /// Fetch the last [hours] of samples (backend clamps to 1..168).
  Future<AmsHistory> fetch(int printerId, int amsId, {int hours = 24}) =>
      _history.watching(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.amsHistory(printerId, amsId),
          queryParameters: {'hours': hours},
        );
        return AmsHistory.fromJson(res.data ?? const {});
      });
}
