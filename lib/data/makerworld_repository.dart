import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/makerworld.dart';

/// REST-owe źródło danych integracji MakerWorld.
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio (miniatury idą osobno —
/// proxy `/makerworld/thumbnail` jest publiczne). Każda metoda mapuje
/// [DioException] na [AppApiException].
class MakerWorldRepository {
  MakerWorldRepository(this._dio);

  final Dio _dio;

  /// GET /makerworld/status — czy pobieranie jest dostępne (token chmury).
  Future<MakerWorldStatus> status() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(Endpoints.makerworldStatus);
      return MakerWorldStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /makerworld/resolve — rozwiązanie URL-a modelu na design + instancje.
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

  /// POST /makerworld/import — pobranie instancji do biblioteki.
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

  /// GET /makerworld/recent-imports — ostatnie importy. Defensywne parsowanie.
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
