import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive_slim.dart';
import '../core/models/archive_stats.dart';
import '../core/models/failure_analysis.dart';
import '../core/models/json_utils.dart';
import '../core/models/user_summary.dart';

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

  /// Whether this server has [Endpoints.usersSlim]; `null` until probed. Lives
  /// on the instance, which is rebuilt on every profile change — exactly how
  /// long the answer holds.
  ///
  /// The route's release is recorded in [ServerFeature.usersSlimListing], but
  /// deliberately not consulted here: that table answers "does this generation
  /// have the route", while this has to answer "will it serve *me*" — a 1.2.6
  /// server still refuses a session holding neither `users:read_slim` nor
  /// `users:read`. Swapping the probe for the version check would also strand
  /// any server whose reported version parses low, on the full listing an API
  /// key cannot read at all.
  bool? _hasSlimListing;

  /// Statuses that mean "this server will not serve me the slim listing".
  ///
  /// A pre-1.2.6 server declares `/{user_id}` as an `int`, so the path is a
  /// **422**, or a **403** for a caller refused before it is parsed — never a
  /// 404. Anything else (401, 5xx, no response at all) says nothing about the
  /// route and must not pin the fallback.
  static const _routeUnavailable = {403, 404, 422};

  /// Fetch all users, for the Stats "filter by user" picker.
  ///
  /// [Endpoints.usersSlim] first, falling back to the full [Endpoints.users]
  /// listing, so this works against both server generations — and, on 1.2.6+,
  /// for the sessions the full listing has always refused: API keys, and groups
  /// holding `users:read_slim` without `users:read`. A 403 from both is a
  /// normal outcome (the caller hides the picker), not an error to surface.
  Future<List<UserSummary>> fetchUsers() async {
    if (_hasSlimListing != false) {
      try {
        final res = await _dio.get<List<dynamic>>(Endpoints.usersSlim);
        _hasSlimListing = true;
        return _byUsername(res.data);
      } on DioException catch (e) {
        // The full listing is strictly harder to reach, so once slim is known
        // to work, falling back would only turn one error into two.
        if (_hasSlimListing == true ||
            !_routeUnavailable.contains(e.response?.statusCode)) {
          throw mapDioException(e);
        }
        _hasSlimListing = false;
      }
    }
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.users);
      return _byUsername(res.data);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Slim sorts by username, the full listing by `created_at`, so without this
  /// the same server would present the same people differently depending on
  /// which route answered. `toList()` because [parseJsonList] can hand back a
  /// `const []`, which cannot be sorted in place.
  static List<UserSummary> _byUsername(List<dynamic>? data) =>
      parseJsonList(data, UserSummary.fromJson).toList()..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );

  static String? _ymd(DateTime? d) => d == null ? null : calendarDateToJson(d);
}
