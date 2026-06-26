import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.printers);
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final printers = <Printer>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        printers.add(Printer.fromJson(item));
      } on Object {
        continue;
      }
    }
    return printers;
  }

  Future<PrinterStatus?> fetchStatus(int printerId) async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.printerStatus(printerId));
      final body = res.data;
      return body == null ? null : PrinterStatus.fromJson(body);
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      // Auth must bubble up (UI redirects to config); others degrade to
      // "status unavailable" card instead of breaking dashboard.
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

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
