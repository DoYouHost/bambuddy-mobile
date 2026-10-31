import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/external_link.dart';

/// The server's sidebar links and the counts their apps report —
/// `GET /external-links/`. Read only: the one write that touches a count is for
/// the app behind a link, and the rest of the router is administration.
class ExternalLinksRepository {
  ExternalLinksRepository(this._dio);

  final Dio _dio;

  /// Empty for a server without the route (404) and for a session the server
  /// refuses (403): both mean "nothing to show". The list handler looks up no
  /// row by id, so a 404 can only mean the route is absent. Anything else is an
  /// error, and one row that is not an object is dropped rather than failing the
  /// list.
  Future<List<ExternalLink>> fetch() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.externalLinks);
      return [
        for (final row in res.data ?? const [])
          if (row is Map<String, dynamic>) ExternalLink.fromJson(row),
      ];
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 403) return const [];
      throw mapDioException(e);
    }
  }
}
