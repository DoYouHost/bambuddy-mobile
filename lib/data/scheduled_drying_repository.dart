import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/json_utils.dart';
import '../core/models/scheduled_drying.dart';

/// REST data source for delayed AMS drying runs — `GET/POST/DELETE
/// /scheduled-dryings` (server #2638).
///
/// Auth adds the shared [AuthInterceptor]; [DioException] is mapped to
/// [AppApiException].
class ScheduledDryingRepository {
  ScheduledDryingRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsScheduling] until the listing has.
  final ServerVersionService? _serverVersion;

  /// Whether the server can schedule a drying run at all.
  ///
  /// Unknown → not offered: the sheet's "Later" modes ask the user to fill in a
  /// delay or a time, and a form that ends in a 404 is worse than one mode
  /// fewer. The listing runs whenever a printer card with a drying-capable AMS
  /// is built, so the observation lands before the user can open the sheet.
  late final _scheduling = ObservedCapability(
    ServerFeature.scheduledDryings,
    _serverVersion,
  );

  Future<bool> supportsScheduling() => _scheduling.supported;

  /// The `pending` / `running` / `failed` rows, newest start first — the whole
  /// fleet, or one printer when [printerId] is given.
  ///
  /// A 404 (no such route) answers with an empty list rather than throwing:
  /// every caller is a card that has nothing to say about an older server, and
  /// the latch above has already recorded why.
  Future<List<ScheduledDrying>> list({int? printerId}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.scheduledDryings,
        queryParameters: {'printer_id': ?printerId},
      );
      _scheduling.observe(present: true);
      return parseJsonList(res.data, ScheduledDrying.fromJson);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      _scheduling.observeFailure(status);
      if (status == 404 || status == 403) return const [];
      throw mapDioException(e);
    }
  }

  /// Schedule a run. [startAfter] null means "as soon as the printer is idle";
  /// the server refuses an instant that is not in the future.
  ///
  /// [filament] may be empty — the scheduler fills it from the loaded tray at
  /// dispatch, which is also what the immediate `drying/start` does.
  Future<ScheduledDrying> create({
    required int printerId,
    required int amsId,
    required int temp,
    required int durationHours,
    String filament = '',
    bool rotateTray = false,
    DateTime? startAfter,
  }) async {
    final start = startAfter == null ? null : instantToJson(startAfter);
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.scheduledDryings,
        data: {
          'printer_id': printerId,
          'ams_id': amsId,
          'temp': temp,
          'duration_hours': durationHours,
          'filament': filament,
          'rotate_tray': rotateTray,
          // Naive UTC: the column is naive and the schema's validator only
          // strips an offset it is given, so this is the spelling that cannot
          // be re-interpreted on the way in. Absent = start as soon as the
          // printer is idle.
          'start_after': ?start,
        },
      );
      _scheduling.observe(present: true);
      return ScheduledDrying.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      _scheduling.observeFailure(e.response?.statusCode);
      throw mapDioException(e);
    }
  }

  /// Cancel a pending or running run, or dismiss a failed one.
  Future<void> cancel(int id) async {
    try {
      await _dio.delete<Map<String, dynamic>>(Endpoints.scheduledDrying(id));
      _scheduling.observe(present: true);
    } on DioException catch (e) {
      _scheduling.observeFailure(e.response?.statusCode);
      throw mapDioException(e);
    }
  }
}
