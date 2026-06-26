import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/maintenance.dart';

/// REST data source for printer maintenance (M7): status overview per printer,
/// mark task as done (reset counter), and history.
///
/// Auth adds `AuthInterceptor` to the shared Dio. List parsing is defensive
/// (skip bad entries), and [fetchPrinter] degrades to `null` on non-auth errors —
/// a single unreachable printer won't break post-print reminders.
class MaintenanceRepository {
  MaintenanceRepository(this._dio);

  final Dio _dio;

  /// `GET /maintenance/overview` — all active printers. Skip unparseable entries.
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

  /// `GET /maintenance/printers/{id}` — one printer. Auth errors bubble up
  /// (UI → /setup); other errors degrade to `null`.
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

  /// `POST /maintenance/items/{id}/perform` — reset counter. Body `{"notes": notes}`.
  /// 403 (no permission) → [AuthException(forbidden)].
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

  /// `GET /maintenance/items/{id}/history` — execution history.
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
