import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/ams_history.dart';

/// REST data source for AMS sensor history
/// (`GET /ams-history/{printerId}/{amsId}?hours=N`).
///
/// Auth adds the shared [AuthInterceptor]; [DioException] is mapped to
/// [AppApiException]. Native backend only — Spoolman has no such endpoint.
class AmsHistoryRepository {
  AmsHistoryRepository(this._dio);

  final Dio _dio;

  /// What the route actually did, once it has been called (`false` after 404).
  bool? _observedRoute;

  /// Whether this caller was refused the route (403 — no `ams_history:read`).
  bool _forbidden = false;

  /// Whether to offer the history chart at all.
  ///
  /// Observation only, with no version row behind it: the route shipped in
  /// v0.1.5 (server commit 0dc76746, December 2025), older than any server this
  /// app talks to, so a threshold could only ever hide the chart from a healthy
  /// server whose version read failed. What is worth watching is the
  /// permission — a restricted key or group gets a 403 that no version knows
  /// about. Both latches last as long as the instance, which the dashboard's
  /// pull-to-refresh recreates: with the chip's chart gone nothing would call
  /// the route again, so a permission granted server-side needs that nudge.
  Future<bool> supportsHistory() async =>
      !_forbidden && (_observedRoute ?? true);

  /// Fetch the last [hours] of samples (backend clamps to 1..168).
  Future<AmsHistory> fetch(int printerId, int amsId, {int hours = 24}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.amsHistory(printerId, amsId),
        queryParameters: {'hours': hours},
      );
      _observedRoute = true;
      _forbidden = false;
      return AmsHistory.fromJson(res.data ?? const {});
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
