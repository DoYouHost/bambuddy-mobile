import 'package:dio/dio.dart';

import 'cached_token_service.dart';
import 'endpoints.dart';

/// Mints the token an `<img>`/video element carries in `?token=`, having no way
/// to send a header. `null` on a server predating #3025 — see
/// [MediaAuthService], which decides what to send instead.
class MediaTokenService extends CachedTokenService {
  MediaTokenService(Dio dio) : super(dio, Endpoints.mediaToken);

  Future<String?> token({bool forceRefresh = false}) =>
      cachedToken(forceRefresh: forceRefresh);
}
