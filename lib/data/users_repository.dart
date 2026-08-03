import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/current_user.dart';
import '../core/models/json_utils.dart';
import '../core/models/user_items_count.dart';
import '../core/models/user_write.dart';

/// REST data source for the accounts on the server.
///
/// The list carries `UserResponse`, the very shape `/auth/me` answers with
/// (`backend/app/api/routes/users.py:48`), so [CurrentUser] parses both; only
/// which account it describes differs.
///
/// Writes are admin-only server-side on top of the `users:*` permission
/// (`RequireAdminIfAuthEnabled`, `users.py:86`), and an API-key session is
/// refused every one of them.
class UsersRepository {
  UsersRepository(this._dio);

  final Dio _dio;

  /// GET /users/ — every account, oldest first (the server orders by
  /// `created_at`). `users:read`; an identity without it gets a 403.
  Future<List<CurrentUser>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.users);
      return parseJsonList(res.data, CurrentUser.fromJson);
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// GET /users/{id}/items-count — archives, queue items and library files
  /// created by this account.
  Future<UserItemsCount> itemsCount(int userId) async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.userItemsCount(userId));
      return UserItemsCount.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// POST /users/ — the created account, as the server stored it.
  Future<CurrentUser> create(UserCreateInput body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.users,
        data: body.toJson(),
      );
      return CurrentUser.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// PATCH /users/{id} — only the fields [body] carries are touched.
  Future<CurrentUser> update(int userId, UserUpdateInput body) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.userById(userId),
        data: body.toJson(),
      );
      return CurrentUser.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// DELETE /users/{id}.
  ///
  /// [deleteItems] decides what happens to the archives, queue items and
  /// library files the account created: `true` deletes them with it, `false`
  /// (the server's own default) leaves them in place with no owner
  /// (`users.py:409`). There is no third option, so the caller has to ask.
  Future<void> delete(int userId, {required bool deleteItems}) async {
    try {
      await _dio.delete<void>(
        Endpoints.userById(userId),
        queryParameters: {'delete_items': deleteItems},
      );
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// GET /auth/advanced-auth/status — whether the server mails a generated
  /// password instead of taking one. A server that doesn't know the route (or
  /// won't answer it) falls back to the classic shape rather than blocking the
  /// form.
  Future<AdvancedAuthStatus> advancedAuthStatus() async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.advancedAuthStatus);
      return AdvancedAuthStatus.fromJson(res.data ?? const {});
    } on DioException {
      return AdvancedAuthStatus.legacy;
    }
  }
}

