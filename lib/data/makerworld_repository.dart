import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
  Future<MakerWorldStatus> status() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(Endpoints.makerworldStatus);
      return MakerWorldStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /makerworld/resolve — resolve model URL to design + instances.
  Future<MakerWorldResolvedModel> resolve(String url) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.makerworldResolve,
        data: <String, dynamic>{'url': url},
      );
      return MakerWorldResolvedModel.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /makerworld/import — download instance to library.
  Future<MakerWorldImportResponse> import({
    required int modelId,
    int? profileId,
    int? folderId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.makerworldImport,
        data: <String, dynamic>{
          'model_id': modelId,
          'profile_id': ?profileId,
          'folder_id': ?folderId,
        },
      );
      return MakerWorldImportResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /makerworld/recent-imports — recent imports. Defensive parsing.
  Future<List<MakerWorldRecentImport>> recentImports({int limit = 20}) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.makerworldRecentImports,
        queryParameters: {'limit': limit},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final out = <MakerWorldRecentImport>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        out.add(MakerWorldRecentImport.fromJson(item));
      } on Object {
        continue;
      }
    }
    return out;
  }
}
