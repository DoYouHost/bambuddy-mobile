import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/smart_plug.dart';

/// Action controlling a smart plug — maps 1:1 to the `action` field in
/// `POST /smart-plugs/{id}/control` body.
enum SmartPlugAction {
  on,
  off,
  toggle;

  String get wire => name;
}

/// REST data source for smart plugs (M7): list (with printer assignment), live
/// status (power/energy), and on/off control.
///
/// Auth adds [AuthInterceptor] to the shared Dio. List parsing is defensive
/// (skip bad entries), and [fetchStatus] degrades to `null` on non-auth errors —
/// unreachable plug won't break dashboard.
class SmartPlugsRepository {
  SmartPlugsRepository(this._dio);

  final Dio _dio;

  /// `GET /smart-plugs/` — all plugs with config (including `printer_id`).
  /// Skip unparseable entries.
  Future<List<SmartPlug>> fetchPlugs() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.smartPlugs);
      return res.data ?? const [];
    });
    return parseJsonList(body, SmartPlug.fromJson);
  }

  /// `GET /smart-plugs/{id}/status` — live state + measurement. Auth errors bubble up
  /// (UI → /setup); others degrade to `null` (plug unreachable).
  Future<SmartPlugStatus?> fetchStatus(int plugId) => guardOrNull(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(Endpoints.smartPlugStatus(plugId));
        final body = res.data;
        return body == null ? null : SmartPlugStatus.fromJson(body);
      });

  /// `POST /smart-plugs/{id}/control` — body `{"action":...}`. Success =
  /// return without exception; 403 (no permission) → [AuthException(forbidden)].
  Future<void> control(int plugId, SmartPlugAction action) => guard(() => _dio.post<dynamic>(
        Endpoints.smartPlugControl(plugId),
        data: {'action': action.wire},
      ));
}
