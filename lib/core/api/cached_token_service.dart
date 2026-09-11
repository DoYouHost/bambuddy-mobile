import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import 'api_exceptions.dart';

/// Cache, TTL and single-flight mint shared by the three token services.
/// Without the single flight, concurrent callers meeting an expired cache each
/// fire their own mint.
abstract class CachedTokenService {
  CachedTokenService(this._dio, this._endpoint);

  final Dio _dio;
  final String _endpoint;

  /// Conservatively shorter than the server's 60 min to avoid mid-use expiry.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;
  bool _routeAbsent = false;

  /// Lets a proactive refresher schedule a re-mint ahead of the lapse.
  DateTime? get expiresAt => _expiresAt;

  /// Whether the last mint found no such route on this server, so [cachedToken]
  /// now answers `null` without asking again — see [_routeMissing] for what
  /// "no such route" looks like on the wire.
  ///
  /// Remembering the absence is the point: a token this old a server does not
  /// have is asked for once per *use*, not once per session — a page of
  /// thumbnails or a run of WebSocket reconnects would otherwise fire a 404
  /// POST apiece, forever. Cleared by [invalidate] and by a forced refresh, so
  /// a server that gains the route while the app runs is picked up.
  bool get routeAbsent => _routeAbsent;

  Future<String?>? _pending;

  /// `null` when the route is not on this server, which each subclass reads
  /// differently — an older build for `WsTokenService` and `MediaTokenService`,
  /// an error for `CameraTokenService`.
  Future<String?> cachedToken({bool forceRefresh = false}) async {
    if (forceRefresh) _routeAbsent = false;
    if (_routeAbsent) return null;

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

  /// A mint this server does not have. 404 is the obvious answer; **405 is the
  /// one bambuddy actually gives**, and missing it is what broke every
  /// thumbnail on a pre-#3025 server: the SPA catch-all (`main.py::serve_spa`)
  /// is declared `@app.get("/{full_path:path}")`, so an unknown
  /// `POST /api/v1/auth/…` matches its path but not its method —
  /// Starlette answers such a partial match with 405 and never reaches its own
  /// 404 (`starlette/routing.py`, `Match.PARTIAL`).
  static bool _routeMissing(int? status) => status == 404 || status == 405;

  Future<String?> _mint() async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(_endpoint);
    } on DioException catch (e) {
      if (_routeMissing(e.response?.statusCode)) {
        _routeAbsent = true;
        return null;
      }
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

  /// Forces a fresh mint on the next [cachedToken], e.g. after a 401 — and
  /// re-probes a route previously found absent, since a refusal is also how an
  /// upgraded server first makes itself known.
  void invalidate() {
    _token = null;
    _expiresAt = null;
    _routeAbsent = false;
  }
}
