import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive.dart';

/// REST-owe źródło danych archiwum wydruków (M5).
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio.
/// Każda metoda mapuje [DioException] na [AppApiException].
/// Sukces = zwrot bez wyjątku (dla void) lub sparsowane dane.
class ArchiveRepository {
  ArchiveRepository(this._dio);

  final Dio _dio;

  /// GET /archives/ — paginowana lista archiwum.
  ///
  /// Defensywne parsowanie: niesparsowalny wpis jest pomijany, nie
  /// wywala całej listy.
  Future<List<Archive>> list({
    int limit = 50,
    int offset = 0,
    int? printerId,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'printer_id': printerId,
    }..removeWhere((_, v) => v == null);
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archives,
        queryParameters: query,
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final archives = <Archive>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        archives.add(Archive.fromJson(item));
      } on Object {
        // Pojedynczy niesparsowalny wpis nie może zabić całej listy.
        continue;
      }
    }
    return archives;
  }

  /// GET /archives/search?q=&limit=&offset= — wyszukiwanie pełnotekstowe.
  ///
  /// Defensywne parsowanie: niesparsowalny wpis jest pomijany.
  Future<List<Archive>> search(
    String q, {
    int limit = 50,
    int offset = 0,
  }) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archivesSearch,
        queryParameters: {'q': q, 'limit': limit, 'offset': offset},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final archives = <Archive>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        archives.add(Archive.fromJson(item));
      } on Object {
        // Pojedynczy niesparsowalny wpis nie może zabić całej listy.
        continue;
      }
    }
    return archives;
  }

  /// POST /archives/{id}/reprint?printer_id=PRINTER — wznowienie wydruku
  /// z archiwum na wskazanej drukarce. Body puste; parametr idzie w query.
  Future<void> reprint(int archiveId, {required int printerId}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.archiveReprint(archiveId),
        queryParameters: {'printer_id': printerId},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
