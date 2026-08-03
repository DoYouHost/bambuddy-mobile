import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/group_summary.dart';
import '../core/models/json_utils.dart';

/// REST data source for groups. Read-only so far — the account form needs the
/// list to offer a membership picker; managing the groups themselves comes
/// with its own screens.
class GroupsRepository {
  GroupsRepository(this._dio);

  final Dio _dio;

  /// GET /groups/ — gated on `groups:read` (`backend/app/api/routes/groups.py:65`).
  Future<List<GroupSummary>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.groups);
      return parseJsonList(res.data, GroupSummary.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
