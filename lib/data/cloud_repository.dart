import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/cloud_auth.dart';

/// REST-owe źródło danych logowania do chmury Bambu (warunek pobierania
/// z MakerWorld). Mapuje [DioException] na [AppApiException].
class CloudRepository {
  CloudRepository(this._dio);

  final Dio _dio;

  /// GET /cloud/status — stan logowania (e-mail/region jeśli zalogowany).
  Future<CloudAuthStatus> status() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.cloudStatus);
      return CloudAuthStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /cloud/login — start logowania. `needs_verification=true` → [verify].
  Future<CloudLoginResult> login({
    required String email,
    required String password,
    String region = 'global',
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.cloudLogin,
        data: <String, dynamic>{
          'email': email,
          'password': password,
          'region': region,
        },
      );
      return CloudLoginResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /cloud/verify — dosłanie kodu 2FA/OTP (e-mail lub TOTP).
  Future<CloudLoginResult> verify({
    required String email,
    required String code,
    String? tfaKey,
    String region = 'global',
  }) async {
    try {
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
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /cloud/logout — wylogowanie (kasuje token chmury po stronie serwera).
  Future<void> logout() async {
    try {
      await _dio.post<dynamic>(Endpoints.cloudLogout);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
