import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/smart_plug.dart';

/// Akcja sterująca gniazdkiem — mapuje się 1:1 na pole `action` w body
/// `POST /smart-plugs/{id}/control`.
enum SmartPlugAction {
  on,
  off,
  toggle;

  String get wire => name;
}

/// REST-owe źródło danych o smart gniazdkach (M7): lista (z przypisaniem do
/// drukarek), żywy status (moc/energia) i sterowanie on/off.
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio. Parsowanie listy jest
/// defensywne (zły wpis pomijamy), a [fetchStatus] degraduje się do `null` przy
/// błędach innych niż auth — gniazdko nieosiągalne nie może wywrócić dashboardu.
class SmartPlugsRepository {
  SmartPlugsRepository(this._dio);

  final Dio _dio;

  /// `GET /smart-plugs/` — wszystkie gniazdka z konfiguracją (w tym
  /// `printer_id`). Pojedynczy niesparsowalny wpis pomijamy.
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

  /// `GET /smart-plugs/{id}/status` — żywy stan + pomiar. Auth wypływa
  /// (UI → /setup); reszta degraduje się do `null` (gniazdko nieosiągalne).
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

  /// `POST /smart-plugs/{id}/control` — body `{"action":...}`. Sukces = zwrot
  /// bez wyjątku; 403 (brak uprawnień) → [AuthException(forbidden)].
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
