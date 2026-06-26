import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.smartPlugs);
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final plugs = <SmartPlug>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        plugs.add(SmartPlug.fromJson(item));
      } on Object {
        continue;
      }
    }
    return plugs;
  }

  /// `GET /smart-plugs/{id}/status` — live state + measurement. Auth errors bubble up
  /// (UI → /setup); others degrade to `null` (plug unreachable).
  Future<SmartPlugStatus?> fetchStatus(int plugId) async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.smartPlugStatus(plugId));
      final body = res.data;
      return body == null ? null : SmartPlugStatus.fromJson(body);
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

  /// `POST /smart-plugs/{id}/control` — body `{"action":...}`. Success =
  /// return without exception; 403 (no permission) → [AuthException(forbidden)].
  Future<void> control(int plugId, SmartPlugAction action) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.smartPlugControl(plugId),
        data: {'action': action.wire},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
