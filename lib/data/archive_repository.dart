import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive.dart';
import '../core/models/archive_purge.dart';
import '../core/models/json_utils.dart';
import '../core/models/no_3mf_warning.dart';
import '../core/models/plate_list.dart';

/// REST data source for print archive (M5).
///
/// Auth adds [AuthInterceptor] to the shared Dio.
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
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archives,
        queryParameters: query,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Archive.fromJson);
  }

  /// GET /archives/search?q=&limit=&offset= — full-text search.
  ///
  /// Defensive parsing: unparseable entries are skipped. [cancelToken] lets
  /// callers cancel a stale in-flight search (e.g. search-as-you-type) instead
  /// of letting it resolve and race with a newer request.
  Future<List<Archive>> search(
    String q, {
    int limit = 50,
    int offset = 0,
    CancelToken? cancelToken,
  }) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archivesSearch,
        queryParameters: {'q': q, 'limit': limit, 'offset': offset},
        cancelToken: cancelToken,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Archive.fromJson);
  }

  /// GET /archives/{id} — one archive, re-read rather than reused from the
  /// list: the finish photo is attached in the background after the print
  /// ends, so a list loaded before that still shows the print without it.
  Future<Archive> byId(int archiveId) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.archive(archiveId),
        );
        return Archive.fromJson(res.data ?? const {});
      });

  /// POST /archives/{id}/favorite — toggle the favorite flag server-side and
  /// return the updated archive (defensively parsed).
  Future<Archive> toggleFavorite(int archiveId) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.archiveFavorite(archiveId),
        );
        return Archive.fromJson(res.data ?? const {});
      });

  /// DELETE /archives/{id} — delete a print from the archive. Soft-delete by
  /// default; [purgeStats] sends `?purge_stats=true` to also remove the print
  /// from aggregate statistics.
  Future<void> delete(int archiveId, {bool purgeStats = false}) => guard(() => _dio.delete<dynamic>(
        Endpoints.archive(archiveId),
        queryParameters: {'purge_stats': purgeStats},
      ));

  /// GET /archives/purge/preview — count + size of prints older than
  /// [olderThanDays] eligible for purge. Read-only.
  Future<ArchivePurgePreview> purgePreview({
    required int olderThanDays,
    bool purgeStats = false,
  }) =>
      guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.archivesPurgePreview,
          queryParameters: {
            'older_than_days': olderThanDays,
            'purge_stats': purgeStats,
          },
        );
        return ArchivePurgePreview.fromJson(res.data ?? const {});
      });

  /// GET /archives/{id}/plates — the plates of a multi-plate 3MF.
  ///
  /// Best-effort by design: every failure answers [PlateList.none], which reads
  /// as "no plate to choose" and leaves the caller looking exactly as it did
  /// before plates existed. That covers a server without the route, an archive
  /// whose file is gone (404), a `.gcode` that was never a 3MF, and an account
  /// without `archives:read` (403) — four causes, one correct response.
  Future<PlateList> plates(int archiveId) async {
    final data = await guardOrNullAllowingForbidden(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivePlates(archiveId),
      );
      return res.data;
    });
    return data == null ? PlateList.none : PlateList.fromJson(data);
  }

  /// GET /archives/no-3mf-warning — whether any print in the last 30 days
  /// archived without its 3MF, and why.
  ///
  /// Best-effort like [plates]: a server that lacks the route, or a user whose
  /// permissions do not reach it (403), gets no nudge rather than an error. The
  /// `reason` key is newer than the route, and its absence is a meaningful
  /// answer rather than a gap — see [No3mfReason.slicerSetting].
  Future<No3mfWarning> no3mfWarning() async {
    final data = await guardOrNullAllowingForbidden(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesNo3mfWarning,
      );
      return res.data;
    });
    return data == null ? No3mfWarning.none : No3mfWarning.fromJson(data);
  }

  /// POST /archives/purge — bulk-delete prints older than [olderThanDays].
  /// [purgeStats] also drops them from statistics (irreversible). Returns the
  /// number of deleted prints.
  Future<int> purge({
    required int olderThanDays,
    bool purgeStats = false,
  }) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.archivesPurge,
          data: {'older_than_days': olderThanDays, 'purge_stats': purgeStats},
        );
        return toInt(res.data?['deleted']);
      });
}
