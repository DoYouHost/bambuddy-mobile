import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/dio_json.dart';
import '../core/api/endpoints.dart';
import '../core/models/announcement.dart';

/// Announcements from the Bambuddy maintainers. Shares the authenticated Dio.
class AnnouncementsRepository {
  AnnouncementsRepository(this._dio);

  final Dio _dio;

  /// [AnnouncementFeed.hidden] on a server without the route (404). The
  /// handler raises no 404 of its own, so that answer only means "absent".
  Future<AnnouncementFeed> fetch() => guardAbsent(() async {
    return _dio.getObject(Endpoints.announcements, AnnouncementFeed.fromJson);
  }, AnnouncementFeed.hidden);

  Future<void> markRead(String id) => guard(() async {
    await _dio.post<void>(Endpoints.announcementRead(id));
  });
}
