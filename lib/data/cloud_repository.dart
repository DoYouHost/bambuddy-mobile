import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/cloud_auth.dart';

/// REST data source for Bambu cloud login (prerequisite for MakerWorld downloads).
/// Maps [DioException] to [AppApiException].
class CloudRepository {
  CloudRepository(this._dio);

  final Dio _dio;

  /// GET /cloud/status — login state (email/region if logged in).
  Future<CloudAuthStatus> status() => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(Endpoints.cloudStatus);
    return CloudAuthStatus.fromJson(res.data ?? const {});
  });

  /// POST /cloud/login — start login. `needs_verification=true` → [verify].
  Future<CloudLoginResult> login({
    required String email,
    required String password,
    String region = 'global',
  }) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.cloudLogin,
      data: <String, dynamic>{
        'email': email,
        'password': password,
        'region': region,
      },
    );
    return CloudLoginResult.fromJson(res.data ?? const {});
  });

  /// POST /cloud/verify — submit 2FA/OTP code (email or TOTP).
  Future<CloudLoginResult> verify({
    required String email,
    required String code,
    String? tfaKey,
    String region = 'global',
  }) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.cloudVerify,
      data: <String, dynamic>{
        'email': email,
        'code': code,
        'tfa_key': ?tfaKey,
        'region': region,
      },
    );
    return CloudLoginResult.fromJson(res.data ?? const {});
  });

  /// POST /cloud/logout — logout (clears cloud token on server side).
  Future<void> logout() => guard(() async {
    await _dio.post<dynamic>(Endpoints.cloudLogout);
  });
}
