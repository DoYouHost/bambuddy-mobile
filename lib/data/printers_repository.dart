import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/available_filament.dart';
import '../core/models/printer.dart';
import '../core/models/printer_create.dart';
import '../core/models/printer_diagnostic.dart';
import '../core/models/printer_status.dart';

/// Why creating a printer failed — mapped to a localized message in the UI.
/// Kept separate from [AppErrorCode] because the create flow needs the server's
/// response body (`detail.code`), which the generic [mapDioException] discards.
enum CreatePrinterFailure { connectionFailed, duplicateSerial, forbidden, generic }

/// Thrown by [PrintersRepository.createPrinter]. Auth (401) still bubbles as an
/// [AuthException] so the app redirects to setup as usual.
class CreatePrinterException implements Exception {
  const CreatePrinterException(this.reason);

  final CreatePrinterFailure reason;

  @override
  String toString() => 'CreatePrinterException($reason)';
}

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

  /// Add a printer (`POST /printers/`). The server verifies the MQTT connection
  /// before persisting, so a bad access code / unreachable IP surfaces here as
  /// [CreatePrinterFailure.connectionFailed] and nothing is created.
  ///
  /// Not routed through [guard]: the failure reason lives in the response body
  /// (`detail.code` / message), which [mapDioException] drops. Auth (401) is
  /// re-mapped so it bubbles as an [AuthException] like every other call.
  Future<Printer> createPrinter(PrinterCreate data) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.printers,
        data: data.toJson(),
      );
      final body = res.data;
      if (body == null) throw const CreatePrinterException(CreatePrinterFailure.generic);
      return Printer.fromJson(body);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) throw mapDioException(e);
      if (status == 403) {
        throw const CreatePrinterException(CreatePrinterFailure.forbidden);
      }
      if (status == 400) throw _classify400(e.response?.data);
      throw const CreatePrinterException(CreatePrinterFailure.generic);
    }
  }

  /// Run a pre-save connection diagnostic (`POST /printers/diagnostic`). Returns
  /// the full result (individual checks can be "fail"/"warn" while the call
  /// itself succeeds). Serial/access code are optional — supplying both also
  /// probes the MQTT credentials.
  Future<PrinterDiagnosticResult> diagnose({
    required String ipAddress,
    String? serialNumber,
    String? accessCode,
  }) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.printersDiagnostic,
          data: {
            'ip_address': ipAddress,
            if (serialNumber != null && serialNumber.isNotEmpty)
              'serial_number': serialNumber,
            if (accessCode != null && accessCode.isNotEmpty)
              'access_code': accessCode,
          },
        );
        return PrinterDiagnosticResult.fromJson(res.data ?? const {});
      });

  /// Map a 400 body to a failure reason. FastAPI sends either
  /// `{detail: {code, message}}` (connection test) or `{detail: "…"}` (plain
  /// string, e.g. duplicate serial).
  CreatePrinterException _classify400(dynamic body) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is Map && detail['code'] == 'printer_connection_failed') {
      return const CreatePrinterException(CreatePrinterFailure.connectionFailed);
    }
    if (detail is String && detail.toLowerCase().contains('serial number')) {
      return const CreatePrinterException(CreatePrinterFailure.duplicateSerial);
    }
    return const CreatePrinterException(CreatePrinterFailure.generic);
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
