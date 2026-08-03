import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/group_summary.dart';
import '../core/models/group_write.dart';
import '../core/models/json_utils.dart';
import '../core/models/permission_catalog.dart';

/// REST data source for groups — a group is a named permission set, and the
/// membership in it is what a household account's rights are made of.
///
/// Reading is gated on `groups:read`; changing who is in a group is admin-only
/// on top of `groups:update` (`backend/app/api/routes/groups.py:263`).
class GroupsRepository {
  GroupsRepository(this._dio);

  final Dio _dio;

  /// GET /groups/ — every group, by name (`groups.py:69`).
  Future<List<GroupSummary>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.groups);
      return parseJsonList(res.data, GroupSummary.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /groups/{id} — the group with its member list.
  Future<GroupDetail> get(int groupId) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(Endpoints.groupById(groupId));
      return GroupDetail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /groups/permissions — the catalog the permission editor is built
  /// from.
  Future<PermissionCatalog> permissions() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(Endpoints.groupPermissions);
      return PermissionCatalog.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /groups/ — the group as the server stored it.
  Future<GroupSummary> create(GroupCreateInput body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.groups,
        data: body.toJson(),
      );
      return GroupSummary.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// PATCH /groups/{id}. Refused for a system group's name or permission set
  /// (`groups.py:187`, `:200`) — the form disables both rather than try.
  Future<GroupSummary> update(int groupId, GroupUpdateInput body) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.groupById(groupId),
        data: body.toJson(),
      );
      return GroupSummary.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// DELETE /groups/{id} — system groups are refused (`groups.py:249`).
  /// Members are not deleted with it; they only lose what it granted.
  Future<void> delete(int groupId) async {
    try {
      await _dio.delete<void>(Endpoints.groupById(groupId));
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// POST /groups/{id}/users/{userId} — 400 "User is already in this group"
  /// when it is a repeat, which the caller shows rather than pre-empts.
  Future<void> addMember(int groupId, int userId) async {
    try {
      await _dio.post<void>(Endpoints.groupMember(groupId, userId));
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// DELETE /groups/{id}/users/{userId}.
  Future<void> removeMember(int groupId, int userId) async {
    try {
      await _dio.delete<void>(Endpoints.groupMember(groupId, userId));
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }
}
