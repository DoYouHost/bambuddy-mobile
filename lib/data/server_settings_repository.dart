import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/models/json_utils.dart';

/// The server's own `AppSettings` — configuration every user of that server
/// shares, as opposed to the preferences this phone keeps for itself.
class ServerSettingsRepository {
  ServerSettingsRepository(this._dio);

  final Dio _dio;

  /// Unversioned because `PUT /settings/` is as old as the server: the only
  /// question left to watch is the permission, and a 403 is what answers it.
  final _writable = ObservedCapability.unversioned();

  /// Best-effort: most callers are feature gates on screens that render anyway.
  Future<Map<String, dynamic>> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.appSettings);
      final data = res.data;
      return data == null ? const {} : asJsonRecord(data);
    } on DioException {
      return const {};
    }
  }

  /// Partial write: the body is dumped `exclude_unset=True`, so keys not named
  /// keep their rows. Answers the settings the server holds afterwards.
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) =>
      _writable.watching(() async {
        final res = await _dio.put<Map<String, dynamic>>(
          Endpoints.appSettingsUpdate,
          data: changes,
        );
        final data = res.data;
        return data == null ? const <String, dynamic>{} : asJsonRecord(data);
      });

  /// Whether a write has been refused — what `/auth/me` cannot answer.
  Future<bool> writable() => _writable.supported;
}
