import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/printable_object.dart';

/// Skip-objects data source: read the current print's printable objects and
/// skip selected ones. Skipping needs `can_control_printer` — a 403 surfaces as
/// [AuthException(forbidden)] via [guard]/[mapDioException].
class SkipObjectsRepository {
  SkipObjectsRepository(this._dio);

  final Dio _dio;

  Future<PrintableObjects> fetchObjects(int printerId, {bool reload = false}) =>
      guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.printObjects(printerId),
          queryParameters: reload ? const {'reload': true} : null,
        );
        final body = res.data;
        return body == null
            ? const PrintableObjects()
            : PrintableObjects.fromJson(body);
      });

  /// Raw PNG of the slicer's object-ID mask for the current print
  /// (`cover?view=pick`) — the outlines the plate overlay draws and hit-tests.
  /// Auth is the camera stream token in the query, like every other cover view.
  ///
  /// Null when the server has no mask to give: a 3MF without `pick_N.png`, or a
  /// server old enough not to know the view. Both are a fallback for the caller,
  /// not an error to show.
  Future<Uint8List?> fetchPickMask(int printerId, String token) async {
    try {
      final res = await _dio.get<List<int>>(
        Endpoints.printerCover(printerId),
        queryParameters: {'view': 'pick', 'token': token},
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw mapDioException(e);
    }
  }

  /// Body is a bare JSON array of `identify_id` values (`[683]`). Content-type
  /// is set explicitly because Dio's implicit-type inference only covers
  /// `FormData`/`Map`/`String`, not a bare `List<int>` — left unset, some
  /// networks mislabel the body and the server's Pydantic model then sees a
  /// raw string instead of a list (422 `list_type`, issue #22). Success =
  /// returns without exception; 403 → [AuthException(forbidden)].
  Future<void> skip(int printerId, List<int> objectIds) => guard(
        () => _dio.post<dynamic>(
          Endpoints.printSkipObjects(printerId),
          data: objectIds,
          options: Options(contentType: Headers.jsonContentType),
        ),
      );
}
