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

  /// Fetch the last [hours] of samples (backend clamps to 1..168).
  Future<AmsHistory> fetch(int printerId, int amsId, {int hours = 24}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.amsHistory(printerId, amsId),
        queryParameters: {'hours': hours},
      );
      return AmsHistory.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
