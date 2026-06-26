import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Fetches and caches the current print cover (`cover_url`) to a file, whose path
/// the home screen widget reads (native provider decodes it via `setImageViewBitmap`).
/// The cover is authenticated as a camera token via `?token=` (NOT a header — see
/// archive-thumbnail-auth-m5 memory), so we fetch with bare Dio using a minted token
/// and retry on 401.
///
/// Cache state is per-isolate (static): the foreground app and background isolate have
/// separate instances — each fetches once per `cover_url` change. The file is fixed
/// (`widget_cover.jpg`) and overwritten, so it doesn't grow.
class WidgetCoverCache {
  WidgetCoverCache._();

  static String? _lastUrl;
  static String? _lastPath;

  /// Returns the local cover file path, or `null` (missing/failed). Skips fetching
  /// if `cover_url` hasn't changed since the last call.
  static Future<String?> fetch({
    required String baseUrl,
    required String coverPath,
    required Dio dio,
    required Future<String> Function({bool forceRefresh}) token,
  }) async {
    final url = '$baseUrl$coverPath';
    if (url == _lastUrl && _lastPath != null) return _lastPath;

    try {
      final bytes = await _download(url, dio, token);
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_cover.jpg');
      await file.writeAsBytes(bytes, flush: true);
      _lastUrl = url;
      _lastPath = file.path;
      return file.path;
    } on Object {
      // Cover fetch failure cannot break widget publication.
      return null;
    }
  }

  /// GETs the image using `?token=`; on 401, mints a fresh token and retries once.
  static Future<List<int>?> _download(
    String url,
    Dio dio,
    Future<String> Function({bool forceRefresh}) token,
  ) async {
    Future<Response<List<int>>> get(String t) => dio.get<List<int>>(
          url,
          queryParameters: {'token': t},
          options: Options(responseType: ResponseType.bytes),
        );

    try {
      final res = await get(await token());
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final res = await get(await token(forceRefresh: true));
        return res.data;
      }
      rethrow;
    }
  }

  /// Clears the cached URL — forces a re-fetch on the next publish
  /// (e.g., when a print finishes and the cover should disappear).
  static void reset() {
    _lastUrl = null;
    _lastPath = null;
  }
}
