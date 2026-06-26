import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'endpoints.dart';

/// Mints and caches camera stream token (`POST /printers/camera/stream-token`).
///
/// Token is shared per server, valid ~60 min, and required as `?token=`
/// when fetching print covers (`cover_url`). Groundwork for M2: the same token
/// will authorize MJPEG stream and camera snapshots — then add proactive
/// refresh (~50 min) and handling for close code 4401.
class CameraTokenService {
  CameraTokenService(this._dio);

  final Dio _dio;

  /// Conservatively shorter than server's 60 min to avoid token expiry during use.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;

  /// Returns a valid token; mints a new one if missing, expired, or
  /// if [forceRefresh] is true (e.g., after 401 from a token-protected resource).
  Future<String> token({bool forceRefresh = false}) async {
    final cached = _token;
    final expiry = _expiresAt;
    if (!forceRefresh &&
        cached != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry)) {
      return cached;
    }

    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(Endpoints.cameraStreamToken);
    } on DioException catch (e) {
      throw mapDioException(e);
    }

    final token = res.data?['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(AppErrorCode.malformedResponse);
    }
    _token = token;
    _expiresAt = DateTime.now().add(_ttl);
    return token;
  }

  /// Forces a fresh mint on next [token] call (e.g., after 401).
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}
