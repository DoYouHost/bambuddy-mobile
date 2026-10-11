import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/manyfold.dart';

/// A self-hosted Manyfold library, browsed and imported through the server
/// (#1471). Shares the authenticated Dio.
class ManyfoldRepository {
  ManyfoldRepository(this._dio);

  final Dio _dio;

  /// `null` when this server has no Manyfold routes (404, every release before
  /// it) or this session may not browse them (403) — the screen then has no
  /// Manyfold tab, as the web hides it without `manyfold:view`.
  Future<ManyfoldStatus?> status() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.manyfoldStatus,
      );
      return ManyfoldStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 403) return null;
      throw mapDioException(e);
    }
  }

  Future<ManyfoldModelPage> models({String query = '', int page = 1}) =>
      _call(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.manyfoldModels,
          queryParameters: {'q': query, 'page': page},
        );
        return ManyfoldModelPage.fromJson(res.data ?? const {});
      });

  Future<ManyfoldModel> model(String id) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.manyfoldModel(id),
    );
    return ManyfoldModel.fromJson(res.data ?? const {});
  });

  /// The preview image, or `null` for a model without one (404).
  Future<Uint8List?> preview(String id) async {
    try {
      final res = await _dio.get<List<int>>(
        Endpoints.manyfoldPreview(id),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw mapDioException(e);
    }
  }

  /// [folderId] `null` files it under the server's "Manyfold" folder.
  Future<ManyfoldImportResult> import({
    required String modelId,
    required String fileId,
    int? folderId,
  }) => _call(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.manyfoldImport,
      data: {'model_id': modelId, 'file_id': fileId, 'folder_id': folderId},
    );
    return ManyfoldImportResult.fromJson(res.data ?? const {});
  });

  Future<ManyfoldConfig> config() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(Endpoints.manyfoldConfig);
    return ManyfoldConfig.fromJson(res.data ?? const {});
  });

  /// An empty [clientSecret] keeps the stored one.
  Future<ManyfoldConfig> saveConfig({
    required String url,
    required String clientId,
    String clientSecret = '',
  }) => _call(() async {
    final res = await _dio.put<Map<String, dynamic>>(
      Endpoints.manyfoldConfig,
      data: _connection(url, clientId, clientSecret),
    );
    return ManyfoldConfig.fromJson(res.data ?? const {});
  });

  /// Files imported earlier stay in the library.
  Future<void> deleteConfig() =>
      _call(() => _dio.delete<void>(Endpoints.manyfoldConfig));

  /// Signs in with these values without storing them; the number of models
  /// the application can see. An empty [clientSecret] tests the stored one.
  Future<int> testConfig({
    required String url,
    required String clientId,
    String clientSecret = '',
  }) => _call(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.manyfoldConfigTest,
      data: _connection(url, clientId, clientSecret),
    );
    final count = res.data?['model_count'];
    return count is int ? count : 0;
  });

  Map<String, dynamic> _connection(String url, String id, String secret) => {
    'url': url.trim(),
    'client_id': id.trim(),
    if (secret.trim().isNotEmpty) 'client_secret': secret.trim(),
  };

  /// A coded Manyfold failure becomes a [ManyfoldFailure], anything else maps
  /// as everywhere else.
  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final code = manyfoldCodeOf(e.response?.data);
      if (code != null) {
        throw ManyfoldFailure(code, mapDioException(e));
      }
      throw mapDioException(e);
    }
  }
}

/// `detail.code` of a Manyfold failure, or `null` for any other body.
String? manyfoldCodeOf(Object? body) {
  final detail = body is Map ? body['detail'] : null;
  final code = detail is Map ? detail['code'] : null;
  return code is String && code.startsWith('manyfold_') ? code : null;
}
