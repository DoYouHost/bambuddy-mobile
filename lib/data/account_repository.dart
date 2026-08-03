import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/current_user.dart';

/// REST data source for the signed-in account. Maps [DioException] to
/// [AppApiException].
class AccountRepository {
  AccountRepository(this._dio);

  final Dio _dio;

  /// GET /auth/me — who this session belongs to, and what it may do.
  Future<CurrentUser> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.authMe);
      return CurrentUser.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
