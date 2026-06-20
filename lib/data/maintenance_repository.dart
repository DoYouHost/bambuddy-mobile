import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/maintenance.dart';

/// REST-owe źródło danych o konserwacji drukarek (M7): przegląd stanu per
/// drukarka, oznaczanie czynności jako wykonanej (reset licznika) i historia.
///
/// Auth dokłada `AuthInterceptor` na współdzielonym Dio. Parsowanie list jest
/// defensywne (zły wpis pomijamy), a [fetchPrinter] degraduje się do `null`
/// przy błędach innych niż auth — pojedyncza nieosiągalna drukarka nie może
/// wywrócić przypomnienia po wydruku.
class MaintenanceRepository {
  MaintenanceRepository(this._dio);

  final Dio _dio;

  /// `GET /maintenance/overview` — wszystkie aktywne drukarki. Pojedynczy
  /// niesparsowalny wpis pomijamy.
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async {
    final List<dynamic> body;
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.maintenanceOverview);
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseOverviews(body);
  }

  /// `GET /maintenance/printers/{id}` — jedna drukarka. Auth wypływa
  /// (UI → /setup); reszta degraduje się do `null`.
  Future<PrinterMaintenanceOverview?> fetchPrinter(int printerId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.maintenancePrinter(printerId),
      );
      final data = res.data;
      return data == null ? null : PrinterMaintenanceOverview.fromJson(data);
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

  /// `POST /maintenance/items/{id}/perform` — reset licznika. Body
  /// `{"notes": notes}`. 403 (brak uprawnień) → [AuthException(forbidden)].
  Future<void> perform(int itemId, {String? notes}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.maintenancePerform(itemId),
        data: {'notes': notes},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /maintenance/items/{id}/history` — historia wykonania.
  Future<List<MaintenanceHistoryEntry>> fetchHistory(int itemId) async {
    final List<dynamic> body;
    try {
      final res = await _dio
          .get<List<dynamic>>(Endpoints.maintenanceHistory(itemId));
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final entries = <MaintenanceHistoryEntry>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        entries.add(MaintenanceHistoryEntry.fromJson(item));
      } on Object {
        continue;
      }
    }
    return entries;
  }

  List<PrinterMaintenanceOverview> _parseOverviews(List<dynamic> body) {
    final out = <PrinterMaintenanceOverview>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        out.add(PrinterMaintenanceOverview.fromJson(item));
      } on Object {
        continue;
      }
    }
    return out;
  }
}
