// ignore_for_file: prefer_initializing_formals — the fields are private, and a
// named parameter cannot be `this._field`.

import 'package:dio/dio.dart';

import '../auth/auth_headers.dart';
import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import 'camera_token.dart';
import 'media_token.dart';

/// The credential a media request carries. `Image.network` and the video player
/// build their own request, so the Dio interceptor never sees these — each URL
/// has to arrive already signed, or already paired with a header.
class MediaAuth {
  const MediaAuth({this.queryToken, this.headers = const {}});

  final String? queryToken;
  final Map<String, String> headers;

  Map<String, String> get query =>
      queryToken == null ? const {} : {'token': queryToken!};

  /// [url] with the credential appended, keeping any query already on it.
  String sign(String url) {
    final token = queryToken;
    if (token == null) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}token=${Uri.encodeQueryComponent(token)}';
  }

  @override
  bool operator ==(Object other) =>
      other is MediaAuth &&
      other.queryToken == queryToken &&
      _sameHeaders(other.headers);

  bool _sameHeaders(Map<String, String> other) {
    if (other.length != headers.length) return false;
    for (final entry in headers.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    queryToken,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Picks the credential this server and this sign-in accept on the media
/// routes, and hides the difference from the call sites.
///
/// A signed-in user gets a media token. An **API key** gets its own header
/// instead: the token it mints names no principal, and the route refuses it for
/// exactly that reason (`core/auth.py::_user_from_media_token`). A server older
/// than #3025 gets the camera stream token, the only thing it accepts here —
/// recognised by the mint refusing the route (404/405, see
/// `CachedTokenService`), never by the version it reports.
class MediaAuthService {
  MediaAuthService({
    required MediaTokenService media,
    required CameraTokenService camera,
    required AuthMode authMode,
    required CredentialsStore credentials,
  }) : _media = media,
       _camera = camera,
       _authMode = authMode,
       _credentials = credentials;

  /// For an isolate with no providers. Kept separate because under Riverpod the
  /// camera service is shared with the live view, and a fresh one there would
  /// split one token's cache in two.
  MediaAuthService.forIsolate({
    required Dio dio,
    required AuthMode authMode,
    required CredentialsStore credentials,
  }) : this(
         media: MediaTokenService(dio),
         camera: CameraTokenService(dio),
         authMode: authMode,
         credentials: credentials,
       );

  final MediaTokenService _media;
  final CameraTokenService _camera;
  final AuthMode _authMode;
  final CredentialsStore _credentials;

  /// When the credential expires, for the proactive refresher.
  DateTime? get expiresAt {
    if (_media.routeAbsent) return _camera.expiresAt;
    return _authMode == AuthMode.apiKey ? null : _media.expiresAt;
  }

  Future<MediaAuth> auth({bool forceRefresh = false}) async {
    // Answers null without a request once the mint has refused the route, and
    // probes again on a forced refresh — [CachedTokenService.routeAbsent].
    final token = await _media.token(forceRefresh: forceRefresh);
    if (token != null) {
      if (_authMode != AuthMode.apiKey) return MediaAuth(queryToken: token);
      return MediaAuth(headers: await authHeaders(_authMode, _credentials));
    }
    return MediaAuth(
      queryToken: await _camera.token(forceRefresh: forceRefresh),
    );
  }

  /// Forces a fresh resolve on the next [auth], e.g. after a 401 — which is
  /// also how an upgraded server first announces itself, so the mint is probed
  /// again too.
  void invalidate() {
    // Before `_media.invalidate()`, which clears the verdict this reads.
    if (_media.routeAbsent) _camera.invalidate();
    _media.invalidate();
  }
}
