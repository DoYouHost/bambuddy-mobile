import 'package:dio/dio.dart';

import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints and caches the WebSocket token (`POST /auth/ws-token`).
///
/// The `/ws` handshake validates an opaque `?token=` before `accept()`
/// (GHSA-r2qv follow-up) because the upgrade can't carry `Authorization`/
/// `X-API-Key` headers. Minting is gated by the standard auth (the
/// authenticated [Dio] supplies the header/JWT).
class WsTokenService extends CachedTokenService {
  WsTokenService(Dio dio) : super(dio, Endpoints.wsToken);

  /// Returns a valid token, minting a new one if missing, expired, or when
  /// [forceRefresh] is set (e.g. after a rejected handshake). Returns `null`
  /// when the server lacks the endpoint (older build) — caller then connects
  /// header-only.
  Future<String?> token({bool forceRefresh = false}) =>
      cachedToken(forceRefresh: forceRefresh);
}
