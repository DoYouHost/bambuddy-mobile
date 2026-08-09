import 'package:dio/dio.dart';

import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints and caches the WebSocket token. The handshake validates an opaque
/// `?token=` before `accept()` (GHSA-r2qv follow-up) because the upgrade cannot
/// carry `Authorization`/`X-API-Key` headers.
class WsTokenService extends CachedTokenService {
  WsTokenService(Dio dio) : super(dio, Endpoints.wsToken);

  /// `null` when the server lacks the endpoint, which is an older build — the
  /// caller then connects header-only.
  Future<String?> token({bool forceRefresh = false}) =>
      cachedToken(forceRefresh: forceRefresh);
}
