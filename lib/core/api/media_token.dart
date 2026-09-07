import 'package:dio/dio.dart';

import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints and caches the media token, required as `?token=` on thumbnails,
/// covers, plate renders, photos and timelapses — none of which accept a
/// header from an `<img>`/video element.
///
/// Server 1.2.5.5 (#3025) split these routes off the camera stream token, which
/// cost `camera:view` to mint (a library thumbnail should not hand out the live
/// feed of the room) and named no principal, so an ownership-scoped row was
/// served to any holder. This one is minted behind plain authentication and
/// carries the user, so each route applies its own permission and ownership
/// rules.
class MediaTokenService extends CachedTokenService {
  MediaTokenService(Dio dio) : super(dio, Endpoints.mediaToken);

  /// `null` when the server lacks the endpoint, which is a build older than
  /// #3025 — the caller then falls back to the camera stream token, which those
  /// builds still accept on media routes. See [MediaAuthService].
  Future<String?> token({bool forceRefresh = false}) =>
      cachedToken(forceRefresh: forceRefresh);
}
