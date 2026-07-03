import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
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
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.maintenanceOverview);
      return res.data ?? const [];
    });
    return parseJsonList(body, PrinterMaintenanceOverview.fromJson);
  }

  /// `GET /maintenance/printers/{id}` — one printer. Auth errors bubble up
  /// (UI → /setup); other errors degrade to `null`.
  Future<PrinterMaintenanceOverview?> fetchPrinter(int printerId) => guardOrNull(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.maintenancePrinter(printerId),
        );
        final data = res.data;
        return data == null ? null : PrinterMaintenanceOverview.fromJson(data);
      });

  /// `POST /maintenance/items/{id}/perform` — reset counter. Body `{"notes": notes}`.
  /// 403 (no permission) → [AuthException(forbidden)].
  Future<void> perform(int itemId, {String? notes}) => guard(() => _dio.post<dynamic>(
        Endpoints.maintenancePerform(itemId),
        data: {'notes': notes},
      ));

  /// `GET /maintenance/items/{id}/history` — execution history.
  Future<List<MaintenanceHistoryEntry>> fetchHistory(int itemId) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.maintenanceHistory(itemId));
      return res.data ?? const [];
    });
    return parseJsonList(body, MaintenanceHistoryEntry.fromJson);
  }
}
