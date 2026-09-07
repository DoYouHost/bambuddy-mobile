import '../settings/server_profile.dart';
import 'camera_token.dart';
import 'media_token.dart';

/// The credential a media request carries: thumbnails, covers, plate renders,
/// photos and timelapses are loaded by `Image.network` and the video player,
/// which build their own request, so the Dio interceptor never sees them.
///
/// Two shapes, because the server has two answers — see [MediaAuthService].
class MediaAuth {
  const MediaAuth({this.queryToken, this.headers = const {}});

  /// Appended as `?token=`; `null` when the credential travels in [headers].
  final String? queryToken;

  /// Passed to `Image.network(headers:)` or a Dio `Options`.
  final Map<String, String> headers;

  /// Query parameters for a Dio request fetching the same resource.
  Map<String, String> get query =>
      queryToken == null ? const {} : {'token': queryToken!};

  /// [url] with the credential appended when it travels in the query string.
  /// Keeps any query the caller already put there (`?view=top`).
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

/// Resolves which credential this server and this sign-in accept on the media
/// routes, and hides the difference from the call sites.
///
/// Three answers, all of them live in the field:
///
/// * **1.2.5.5+, signed in as a user** — a media token from
///   `POST /auth/media-token` ([MediaTokenService]).
/// * **1.2.5.5+, API key** — the `X-API-Key` header. A media token minted by a
///   key names no principal, and the route refuses it for exactly that reason
///   (`core/auth.py::_user_from_media_token`); the same routes take the header
///   directly, and `Image.network` can carry one.
/// * **older than #3025** — the camera stream token, the only thing those
///   builds accept here. The mint 404s on them, which is how they are told
///   apart; nothing is gated on the reported server version.
class MediaAuthService {
  MediaAuthService({
    required MediaTokenService media,
    required CameraTokenService camera,
    required AuthMode authMode,
    required Future<String?> Function() readApiKey,
  }) : // Initializing formals would need public parameter names, so the lint
       // cannot be satisfied while the fields stay private.
       // ignore: prefer_initializing_formals
       _media = media,
       // ignore: prefer_initializing_formals
       _camera = camera,
       // ignore: prefer_initializing_formals
       _authMode = authMode,
       // ignore: prefer_initializing_formals
       _readApiKey = readApiKey;

  final MediaTokenService _media;
  final CameraTokenService _camera;
  final AuthMode _authMode;
  final Future<String?> Function() _readApiKey;

  /// `false` once the mint has 404'd — without it every media load re-asks an
  /// old server for an endpoint it does not have. Cleared by [invalidate], so a
  /// server upgraded under a running app is re-probed on the first 401.
  bool? _mediaTokenSupported;

  /// When the credential expires, for the proactive refresher; `null` when it
  /// is a header, which does not.
  DateTime? get expiresAt {
    if (_mediaTokenSupported == false) return _camera.expiresAt;
    return _authMode == AuthMode.apiKey ? null : _media.expiresAt;
  }

  Future<MediaAuth> auth({bool forceRefresh = false}) async {
    // A forced resolve follows a refusal, and the verdict is part of what was
    // refused: re-probe the mint rather than keep assuming the server is the
    // build it was when this service started. Costs one POST an hour on a
    // server that stays old, and is how the background isolate — which never
    // calls [invalidate] — notices one that has been upgraded under it.
    if (forceRefresh) _mediaTokenSupported = null;
    if (_mediaTokenSupported != false) {
      final token = await _media.token(forceRefresh: forceRefresh);
      _mediaTokenSupported = token != null;
      if (token != null) {
        if (_authMode != AuthMode.apiKey) return MediaAuth(queryToken: token);
        final key = await _readApiKey();
        return key == null
            ? const MediaAuth()
            : MediaAuth(headers: {'X-API-Key': key});
      }
    }
    return MediaAuth(
      queryToken: await _camera.token(forceRefresh: forceRefresh),
    );
  }

  /// Forces a fresh resolve on the next [auth], e.g. after a 401. Re-probes the
  /// mint too: the 401 may be the server having gained the endpoint.
  void invalidate() {
    // Only the fallback path holds a camera token worth dropping; on a 1.2.5.5
    // server it belongs to the camera view alone, which re-mints it itself.
    if (_mediaTokenSupported == false) _camera.invalidate();
    _mediaTokenSupported = null;
    _media.invalidate();
  }
}
