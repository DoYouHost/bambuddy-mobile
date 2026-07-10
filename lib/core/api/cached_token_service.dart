import 'package:dio/dio.dart';

import 'api_exceptions.dart';

/// Shared cache + TTL + single-flight mint for short-lived server tokens
/// (`WsTokenService` / `CameraTokenService`) — both mint via a bare `POST`
/// returning `{"token": ...}`, cache for ~55 min, and re-mint on
/// [invalidate]. Without single-flight, concurrent callers hitting an
/// expired cache each fire their own mint request.
abstract class CachedTokenService {
  CachedTokenService(this._dio, this._endpoint);

  final Dio _dio;
  final String _endpoint;

  /// Conservatively shorter than the server's 60 min to avoid mid-use expiry.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;

  /// When the currently cached token lapses (client-side TTL), or `null` if no
  /// token is cached. Lets a proactive refresher schedule a re-mint before it.
  DateTime? get expiresAt => _expiresAt;

  /// In-flight mint shared by concurrent callers instead of each starting
  /// their own request.
  Future<String?>? _pending;

  /// Returns a valid token, minting a new one if missing, expired, or when
  /// [forceRefresh] is set (e.g. after a 401 on the protected resource).
  /// Returns `null` on a 404 from [_endpoint] — meaning depends on the
  /// subclass (see [WsTokenService] vs [CameraTokenService]).
  Future<String?> cachedToken({bool forceRefresh = false}) async {
    final cached = _token;
    final expiry = _expiresAt;
    if (!forceRefresh &&
        cached != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry)) {
      return cached;
    }

    final pending = _pending;
    if (pending != null) return pending;
    final future = _mint();
    _pending = future;
    try {
      return await future;
    } finally {
      _pending = null;
    }
  }

  Future<String?> _mint() async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(_endpoint);
    } on DioException catch (e) {
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

  /// Forces a fresh mint on the next [cachedToken] call (e.g. after a 401).
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}
