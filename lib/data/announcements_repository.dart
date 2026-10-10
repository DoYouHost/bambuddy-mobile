import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/announcement.dart';

/// Announcements from the Bambuddy maintainers. Shares the authenticated Dio.
class AnnouncementsRepository {
  AnnouncementsRepository(this._dio);

  final Dio _dio;

  /// [AnnouncementFeed.hidden] on a server without the route (404). The
  /// handler raises no 404 of its own, so that answer only means "absent".
  Future<AnnouncementFeed> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.announcements);
      return AnnouncementFeed.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return AnnouncementFeed.hidden;
      throw mapDioException(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post<void>(Endpoints.announcementRead(id));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
