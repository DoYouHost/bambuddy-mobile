import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints and caches the camera stream token, shared per server and required as
/// `?token=` on the MJPEG stream and snapshots, neither of which accepts a
/// header.
///
/// Minting it costs `camera:view`, which is why server 1.2.5.5 (#3025) took the
/// thumbnails and covers off it and onto [MediaTokenService]. Older servers
/// still want this one there, and [MediaAuthService] falls back to it for them.
class CameraTokenService extends CachedTokenService {
  CameraTokenService(Dio dio) : super(dio, Endpoints.cameraStreamToken);

  /// Unlike `WsTokenService`, a 404 here means an unexpectedly old server —
  /// camera tokens have always been required — so it surfaces as an API error
  /// instead of degrading silently.
  Future<String> token({bool forceRefresh = false}) async {
    final token = await cachedToken(forceRefresh: forceRefresh);
    if (token == null) {
      throw const ApiException(AppErrorCode.badResponse, statusCode: 404);
    }
    return token;
  }
}
