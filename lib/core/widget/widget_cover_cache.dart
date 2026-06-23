import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Pobiera i cache'uje okładkę bieżącego wydruku (`cover_url`) do pliku, którego
/// ścieżkę bierze widget ekranu głównego (dekoduje ją natywny provider przez
/// `setImageViewBitmap`). Okładka jest uwierzytelniana tokenem kamery jako
/// `?token=` (NIE nagłówkiem — patrz pamięć archive-thumbnail-auth-m5), więc
/// ściągamy gołym Dio z mintowanym tokenem i retry na 401.
///
/// Stan cache jest per-isolate (statyczny): apka na pierwszym planie i isolate
/// tła mają osobne instancje — każda ściąga raz na zmianę `cover_url`. Plik jest
/// stały (`widget_cover.jpg`) i nadpisywany, więc nie puchnie.
class WidgetCoverCache {
  WidgetCoverCache._();

  static String? _lastUrl;
  static String? _lastPath;

  /// Zwraca lokalną ścieżkę pliku okładki albo `null` (brak/nieudane). Pomija
  /// pobranie, gdy `cover_url` się nie zmienił od ostatniego razu.
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
      // Pobranie okładki nie może wywrócić publikacji widgetu.
      return null;
    }
  }

  /// GET obrazka z `?token=`; po 401 mintuje świeży token i próbuje raz jeszcze.
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

  /// Czyści zapamiętany URL — wymusza ponowne pobranie przy następnej publikacji
  /// (np. gdy druk się skończył i okładka ma zniknąć).
  static void reset() {
    _lastUrl = null;
    _lastPath = null;
  }
}
