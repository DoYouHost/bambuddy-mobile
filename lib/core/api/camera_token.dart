import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints and caches camera stream token (`POST /printers/camera/stream-token`).
///
/// Token is shared per server, valid ~60 min, and required as `?token=`
/// when fetching print covers (`cover_url`). Also authorizes the MJPEG
/// stream and camera snapshots.
class CameraTokenService extends CachedTokenService {
  CameraTokenService(Dio dio) : super(dio, Endpoints.cameraStreamToken);

  /// Returns a valid token; mints a new one if missing, expired, or if
  /// [forceRefresh] is true (e.g., after 401 from a token-protected resource).
  ///
  /// Unlike [WsTokenService], a 404 here means an unexpectedly old server —
  /// camera tokens have always been required — so it's surfaced as a normal
  /// API error instead of silently degrading.
  Future<String> token({bool forceRefresh = false}) async {
    final token = await cachedToken(forceRefresh: forceRefresh);
    if (token == null) {
      throw const ApiException(AppErrorCode.badResponse, statusCode: 404);
    }
    return token;
  }
}
