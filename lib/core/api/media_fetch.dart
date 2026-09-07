import 'package:dio/dio.dart';

import 'media_auth.dart';

/// GETs a media route's bytes with a bare Dio, which has no interceptor and so
/// no credential of its own — [auth] supplies it, and is re-resolved once on a
/// 401. Not on a 403: see `media_fetch_test.dart`.
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
