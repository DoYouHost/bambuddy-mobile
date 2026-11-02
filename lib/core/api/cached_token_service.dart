import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'endpoints.dart';

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
  int? _routeAbsentStatus;

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

  /// What the mint actually refused with when [routeAbsent] latched. A subclass
  /// that turns the absence back into an error reports the server's own status
  /// instead of assuming which of the two it was.
  int? get routeAbsentStatus => _routeAbsentStatus;

  Future<String?>? _pending;

  /// `null` when the route is not on this server, which each subclass reads
  /// differently — an older build for `WsTokenService` and `MediaTokenService`,
  /// an error for `CameraTokenService`.
  Future<String?> cachedToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _routeAbsent = false;
      _routeAbsentStatus = null;
    }
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
      final status = e.response?.statusCode;
      if (_routeMissing(status)) {
        _routeAbsent = true;
        _routeAbsentStatus = status;
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
    _routeAbsentStatus = null;
  }
}

/// Mints the token an `<img>`/video element carries in `?token=`, having no way
/// to send a header. `null` on a server predating #3025 — see
/// [MediaAuthService], which decides what to send instead.
///
/// That server answers the mint with 405, not 404; `CachedTokenService` reads
/// both as absence and says why.
class MediaTokenService extends CachedTokenService {
  MediaTokenService(Dio dio) : super(dio, Endpoints.mediaToken);

  Future<String?> token({bool forceRefresh = false}) =>
      cachedToken(forceRefresh: forceRefresh);
}

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
