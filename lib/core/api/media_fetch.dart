import 'package:dio/dio.dart';

import 'media_auth.dart';

/// GETs a media route's bytes with a bare Dio, which carries no interceptor and
/// so no credential of its own — [auth] supplies it. On a 401 the credential is
/// re-resolved once and the request repeated; a token that lapsed server-side
/// (a restart, an early expiry) is indistinguishable from a broken resource
/// until a fresh one is tried.
///
/// **401 only, deliberately** — unlike `MediaAuthImageRecovery`, which also
/// retries a 403. Every lapsed credential on these routes answers 401
/// (`_user_from_media_token` raises it for an unknown, expired or principal-less
/// token, and the pre-#3025 camera-token dependency has no other code either);
/// a 403 is `Missing required permissions`, which a fresh mint cannot change.
/// The widget mixin can afford the wider net because it latches per token and
/// so fires at most once; here there is no latch, and retrying would double
/// every genuinely refused request for as long as the background service runs.
///
/// Used by the two things the isolates fetch outside the API client: the home
/// screen widget's cover and a finished print's photo.
Future<List<int>?> mediaBytes(
  String url,
  Dio dio,
  Future<MediaAuth> Function({bool forceRefresh}) auth,
) async {
  Future<Response<List<int>>> get(MediaAuth credential) => dio.get<List<int>>(
    url,
    queryParameters: credential.query,
    options: Options(
      responseType: ResponseType.bytes,
      headers: credential.headers,
    ),
  );

  try {
    return (await get(await auth())).data;
  } on DioException catch (e) {
    if (e.response?.statusCode != 401) rethrow;
    return (await get(await auth(forceRefresh: true))).data;
  }
}
