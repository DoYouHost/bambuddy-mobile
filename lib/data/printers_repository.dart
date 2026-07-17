import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/available_filament.dart';
import '../core/models/printer.dart';
import '../core/models/printer_status.dart';

/// Printer with status (status may be unavailable independently from the list —
/// e.g., printer offline or single endpoint down).
class PrinterWithStatus {
  const PrinterWithStatus({required this.printer, this.status});

  final Printer printer;
  final PrinterStatus? status;
}

/// REST data source for printers. M2 will add WebSocket merging — this path
/// remains as backfill on resume and fallback.
class PrintersRepository {
  PrintersRepository(this._dio);

  final Dio _dio;

  Future<List<Printer>> fetchPrinters() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.printers);
      return res.data ?? const [];
    });
    return parseJsonList(body, Printer.fromJson);
  }

  /// Auth must bubble up (UI redirects to config); others degrade to
  /// "status unavailable" card instead of breaking dashboard.
  Future<PrinterStatus?> fetchStatus(int printerId) => guardOrNull(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(Endpoints.printerStatus(printerId));
        final body = res.data;
        return body == null ? null : PrinterStatus.fromJson(body);
      });

  /// Filaments loaded on active printers of [model] (optionally filtered by
  /// [location]) — options for model-based filament overrides. Degrades to an
  /// empty list on failure (the override UI just shows no alternatives).
  Future<List<AvailableFilament>> fetchAvailableFilaments(
    String model, {
    String? location,
  }) =>
      guard(() async {
        final res = await _dio.get<List<dynamic>>(
          Endpoints.printersAvailableFilaments,
          queryParameters: <String, dynamic>{
            'model': model,
            if (location != null && location.isNotEmpty) 'location': location,
          },
        );
        return AvailableFilament.parseList(res.data ?? const []);
      });

  /// List and statuses fetched in parallel.
  Future<List<PrinterWithStatus>> fetchAll() async {
    final printers = await fetchPrinters();
    final statuses =
        await Future.wait(printers.map((p) => fetchStatus(p.id)));
    return [
      for (var i = 0; i < printers.length; i++)
        PrinterWithStatus(printer: printers[i], status: statuses[i]),
    ];
  }
}
