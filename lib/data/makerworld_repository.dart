import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/makerworld.dart';

/// REST data source for MakerWorld integration.
///
/// Auth adds [AuthInterceptor] to the shared Dio (thumbnails go separately —
/// `/makerworld/thumbnail` proxy is public). Each method maps [DioException]
/// to [AppApiException].
class MakerWorldRepository {
  MakerWorldRepository(this._dio);

  final Dio _dio;

  /// GET /makerworld/status — whether downloading is available (cloud token).
  Future<MakerWorldStatus> status() => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.makerworldStatus,
    );
    return MakerWorldStatus.fromJson(res.data ?? const {});
  });

  /// POST /makerworld/resolve — resolve model URL to design + instances.
  Future<MakerWorldResolvedModel> resolve(String url) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.makerworldResolve,
      data: <String, dynamic>{'url': url},
    );
    return MakerWorldResolvedModel.fromJson(res.data ?? const {});
  });

  /// POST /makerworld/import — download instance to library.
  Future<MakerWorldImportResponse> import({
    required int modelId,
    int? profileId,
    int? folderId,
  }) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.makerworldImport,
      data: <String, dynamic>{
        'model_id': modelId,
        'profile_id': ?profileId,
        'folder_id': ?folderId,
      },
    );
    return MakerWorldImportResponse.fromJson(res.data ?? const {});
  });

  /// GET /makerworld/recent-imports — recent imports. Defensive parsing.
  Future<List<MakerWorldRecentImport>> recentImports({int limit = 20}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.makerworldRecentImports,
        queryParameters: {'limit': limit},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, MakerWorldRecentImport.fromJson);
  }
}
