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

  /// Body is a bare JSON array of `identify_id` values (`[683]`). Success =
  /// returns without exception; 403 → [AuthException(forbidden)].
  Future<void> skip(int printerId, List<int> objectIds) => guard(
        () => _dio.post<dynamic>(
          Endpoints.printSkipObjects(printerId),
          data: objectIds,
        ),
      );
}
