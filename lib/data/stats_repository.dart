import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive_slim.dart';
import '../core/models/archive_stats.dart';
import '../core/models/failure_analysis.dart';

/// REST data source for archive stats (`GET /archives/stats`).
///
/// Auth adds [AuthInterceptor] to the shared Dio. [DioException] mapped
/// to [AppApiException]; response parsing is defensive (see [ArchiveStats.fromJson]).
class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  /// Page size when fetching lightweight list.
  static const _pageSize = 500;

  /// Hard limit on fetched entries (safeguard for pathologically large archives).
  static const _maxSlim = 10000;

  /// Fetch stats for optional date range and creator.
  ///
  /// [from]/[to] sent as `YYYY-MM-DD` (inclusive). [createdById] filters by
  /// print creator (`-1` = no assigned user); `null` omits filter.
  Future<ArchiveStats> fetch({
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final query = <String, dynamic>{
      'date_from': _ymd(from),
      'date_to': _ymd(to),
      'created_by_id': createdById,
    }..removeWhere((_, v) => v == null);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesStats,
        queryParameters: query,
      );
      return ArchiveStats.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Fetch full lightweight entry list for range (paginate by [_pageSize] until
  /// server returns incomplete page). Used to count rich stats client-side.
  /// Archive is usually hundreds of entries, not millions.
  Future<List<ArchiveSlim>> fetchSlim({
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final out = <ArchiveSlim>[];
    var offset = 0;
    while (true) {
      final query = <String, dynamic>{
        'date_from': _ymd(from),
        'date_to': _ymd(to),
        'created_by_id': createdById,
        'limit': _pageSize,
        'offset': offset,
      }..removeWhere((_, v) => v == null);
      final List<dynamic> body;
      try {
        final res = await _dio.get<List<dynamic>>(
          Endpoints.archivesSlim,
          queryParameters: query,
        );
        body = res.data ?? const [];
      } on DioException catch (e) {
        throw mapDioException(e);
      }
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;
        try {
          out.add(ArchiveSlim.fromJson(item));
        } on Object {
          continue;
        }
      }
      if (body.length < _pageSize) break;
      offset += _pageSize;
      if (offset >= _maxSlim) break;
    }
    return out;
  }

  /// Fetch failure analysis. Provide [days] (last N days) OR range [from]/[to].
  /// Response has no declared schema — parse defensively.
  Future<FailureAnalysis> fetchFailures({
    int? days,
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final query = <String, dynamic>{
      'days': days,
      'date_from': _ymd(from),
      'date_to': _ymd(to),
      'created_by_id': createdById,
    }..removeWhere((_, v) => v == null);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesFailures,
        queryParameters: query,
      );
      return FailureAnalysis.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Format date as `YYYY-MM-DD` (no timezone/time) — server contract.
  static String? _ymd(DateTime? d) {
    if (d == null) return null;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
