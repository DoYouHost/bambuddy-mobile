import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import 'api_exceptions.dart';

/// Cache, TTL and single-flight mint shared by `WsTokenService` and
/// `CameraTokenService`. Without the single flight, concurrent callers meeting
/// an expired cache each fire their own mint.
abstract class CachedTokenService {
  CachedTokenService(this._dio, this._endpoint);

  final Dio _dio;
  final String _endpoint;

  /// Conservatively shorter than the server's 60 min to avoid mid-use expiry.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;

  /// Lets a proactive refresher schedule a re-mint ahead of the lapse.
  DateTime? get expiresAt => _expiresAt;

  Future<String?>? _pending;

  /// `null` on a 404, which each subclass reads differently — an older server
  /// for `WsTokenService`, an error for `CameraTokenService`.
  Future<String?> cachedToken({bool forceRefresh = false}) async {
    final cached = _token;
    final expiry = _expiresAt;
    if (!forceRefresh &&
        cached != null &&
        expiry != null &&
        clock.now().isBefore(expiry)) {
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
    _expiresAt = clock.now().add(_ttl);
    return token;
  }

  /// Forces a fresh mint on the next [cachedToken], e.g. after a 401.
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}
