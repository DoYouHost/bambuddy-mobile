import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'endpoints.dart';

/// Mints and caches the WebSocket token (`POST /auth/ws-token`).
///
/// The `/ws` handshake validates an opaque `?token=` before `accept()`
/// (GHSA-r2qv follow-up) because the upgrade can't carry `Authorization`/
/// `X-API-Key` headers. Minting is gated by the standard auth (the
/// authenticated [Dio] supplies the header/JWT). Token is valid ~60 min;
/// we cache slightly shorter and re-mint on expiry or after a rejected
/// handshake ([invalidate]).
class WsTokenService {
  WsTokenService(this._dio);

  final Dio _dio;

  /// Conservatively shorter than the server's 60 min to avoid mid-use expiry.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;

  /// Returns a valid token, minting a new one if missing, expired, or when
  /// [forceRefresh] is set (e.g. after a 401 on the handshake). Returns `null`
  /// when the server lacks the endpoint (older build) — caller then connects
  /// header-only.
  Future<String?> token({bool forceRefresh = false}) async {
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
      res = await _dio.post<Map<String, dynamic>>(Endpoints.wsToken);
    } on DioException catch (e) {
      // Older server without `/auth/ws-token` → fall back to header auth.
      if (e.response?.statusCode == 404) return null;
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

  /// Forces a fresh mint on the next [token] call (e.g. after a 401).
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}
