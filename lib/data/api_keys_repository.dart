import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/api_key.dart';

/// REST data source for API keys — the credentials handed to things that are
/// not this app (Home Assistant, SpoolBuddy, a script).
///
/// Unlike users and groups these routes carry no admin gate: the `api_keys:*`
/// permissions alone decide
/// (`backend/app/api/routes/api_keys.py::list_api_keys`).
class ApiKeysRepository {
  ApiKeysRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [notificationScopeCapability] until a key row has.
  final ServerVersionService? _serverVersion;

  /// Whether the form may offer [ApiKeyScope.sendNotifications]. A server that
  /// has the flag sends it on every row; one without it takes the field on
  /// create and drops it without a word.
  late final notificationScopeCapability = ObservedCapability(
    ServerFeature.apiKeyNotificationScope,
    _serverVersion,
  );

  /// GET /api-keys/ — newest first, as the server orders them.
  Future<List<ApiKey>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.apiKeys);
      notificationScopeCapability.observeKey(
        res.data?.firstOrNull,
        ApiKeyScope.sendNotifications.wire,
      );
      return parseJsonList(res.data, ApiKey.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /api-keys/ — the only response that carries the key itself. The
  /// caller must show it and let it go: there is no route that returns it
  /// again.
  Future<CreatedApiKey> create(ApiKeyCreateInput body) {
    return guardKeepingDetail(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.apiKeys,
        data: body.toJson(),
      );
      return CreatedApiKey.fromJson(res.data ?? const {});
    });
  }

  /// PATCH /api-keys/{id}.
  Future<ApiKey> update(int keyId, ApiKeyUpdateInput body) {
    return guardKeepingDetail(() async {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.apiKeyById(keyId),
        data: body.toJson(),
      );
      return ApiKey.fromJson(res.data ?? const {});
    });
  }

  /// DELETE /api-keys/{id} — revocation. Whatever holds the key stops working
  /// at once, which is the point.
  Future<void> delete(int keyId) {
    return guardKeepingDetail(() async {
      await _dio.delete<void>(Endpoints.apiKeyById(keyId));
    });
  }
}
