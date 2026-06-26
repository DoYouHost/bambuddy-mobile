import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive.dart';

/// REST data source for print archive (M5).
///
/// Auth adds [AuthInterceptor] to the shared Dio instance.
/// Each method maps [DioException] to [AppApiException].
class ArchiveRepository {
  ArchiveRepository(this._dio);

  final Dio _dio;

  /// GET /archives/ — paginated archive list.
  ///
  /// Defensive parsing: unparseable entries are skipped.
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
        continue;
      }
    }
    return archives;
  }

  /// GET /archives/search?q=&limit=&offset= — full-text search.
  ///
  /// Defensive parsing: unparseable entries are skipped.
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
        continue;
      }
    }
    return archives;
  }

  /// POST /archives/{id}/reprint?printer_id=PRINTER — resume print from archive
  /// on the specified printer. Empty body; parameter goes in query.
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

  /// DELETE /archives/{id} — delete a print from the archive. Soft-delete by
  /// default; [purgeStats] sends `?purge_stats=true` to also remove the print
  /// from aggregate statistics.
  Future<void> delete(int archiveId, {bool purgeStats = false}) async {
    try {
      await _dio.delete<dynamic>(
        Endpoints.archive(archiveId),
        queryParameters: {'purge_stats': purgeStats},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
