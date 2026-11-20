import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

/// The JSON shapes the repositories repeat. None wraps errors: the caller
/// keeps its `guard(...)` so a [DioException] still maps there.
extension DioJson on Dio {
  /// GET a JSON object. A missing body decodes as an empty object, and a body
  /// that is not an object is Dio's own cast failure, as with a bare
  /// `get<Map<String, dynamic>>`.
  Future<T> getObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    final res = await get<Map<String, dynamic>>(
      path,
      queryParameters: query,
      options: options,
    );
    return fromJson(res.data ?? const {});
  }

  /// GET a JSON array, decoded with the tolerant [parseJsonList]: a record
  /// that fails to parse is dropped, and a body that is not an array is Dio's
  /// own cast failure, as with a bare `get<List<dynamic>>`.
  Future<List<T>> getList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    final res = await get<List<dynamic>>(
      path,
      queryParameters: query,
      options: options,
    );
    return parseJsonList(res.data, fromJson);
  }

  /// POST a body and decode the JSON object the server answers with, the way
  /// [getObject] does.
  Future<T> postObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) async => fromJson(
    (await post<Map<String, dynamic>>(
          path,
          data: data,
          queryParameters: query,
          options: options,
        )).data ??
        const {},
  );

  /// PUT counterpart of [postObject].
  Future<T> putObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) async => fromJson(
    (await put<Map<String, dynamic>>(
          path,
          data: data,
          queryParameters: query,
          options: options,
        )).data ??
        const {},
  );

  /// PATCH counterpart of [postObject].
  Future<T> patchObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) async => fromJson(
    (await patch<Map<String, dynamic>>(
          path,
          data: data,
          queryParameters: query,
          options: options,
        )).data ??
        const {},
  );
}
