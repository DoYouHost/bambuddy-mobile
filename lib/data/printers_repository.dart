import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/models/available_filament.dart';
import '../core/models/printer.dart';
import '../core/models/printer_create.dart';
import '../core/models/printer_diagnostic.dart';
import '../core/models/printer_status.dart';

/// Why creating a printer failed — mapped to a localized message in the UI.
/// Kept separate from [AppErrorCode] because the create flow needs the server's
/// response body (`detail.code`), which the generic [mapDioException] discards.
enum CreatePrinterFailure {
  connectionFailed,
  duplicateSerial,
  forbidden,
  generic,
}

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
/// A slot's bound spool as the mapping names it.
typedef SlotSpool = ({String? name, String? colorName});

/// [PrintersRepository.fetchInventoryRemain]'s answer.
typedef SlotInventory = ({Map<int, double> grams, Map<int, SlotSpool> spools});

class PrintersRepository {
  PrintersRepository(this._dio);

  final Dio _dio;

  /// Whether the server holds the jobs of a user without
  /// `queue:start_unreviewed` for review (#1620). Every daily of the cycle
  /// reports `1.2.6b1`, so no version can answer, and nothing on the queue
  /// routes changed shape. `wear_cost_per_hour` (#694) landed on every printer
  /// row the day after #1620 was merged, so a row carrying it proves the
  /// gate. A row without it reads as no gate, which is wrong only for the day
  /// between the two, where the refusal still reaches the user as a sentence.
  ///
  /// Probed, because the queue screen that reads it never lists printers
  /// itself. No printer to read (an empty fleet, no `printers:read`) leaves it
  /// unobserved, so the gate reads no until a later listing carries a row.
  late final reviewGateCapability = ObservedCapability.unversioned(
    whenUnknown: false,
    probe: fetchPrinters,
  );

  Future<List<Printer>> fetchPrinters() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.printers);
      return res.data ?? const [];
    });
    reviewGateCapability.observeKey(body.firstOrNull, 'wear_cost_per_hour');
    return parseJsonList(body, Printer.fromJson);
  }

  /// Auth must bubble up (UI redirects to config); others degrade to
  /// "status unavailable" card instead of breaking dashboard.
  Future<PrinterStatus?> fetchStatus(int printerId) => guardOrNull(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.printerStatus(printerId),
    );
    final body = res.data;
    return body == null ? null : PrinterStatus.fromJson(body);
  });

  /// What the inventory knows of [printerId]'s slots
  /// ([Endpoints.printerInventoryRemain]), by global tray id: grams left on
  /// each bound spool that is loaded, and the bound spool's name and colour
  /// for every binding (`slot_materials`). Empty on any failure short of a
  /// lost session, a 403 included — it only orders and names slots, as the
  /// web's query.
  Future<SlotInventory> fetchInventoryRemain(int printerId) async {
    final body = await guardOrNullAllowingForbidden(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerInventoryRemain(printerId),
      );
      return res.data;
    });
    final grams = <int, double>{};
    if (body?['inventory_remain_g'] case final Map<String, dynamic> raw) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final id = int.tryParse(key);
        final g = toDoubleOrNull(value);
        if (id != null && g != null) grams[id] = g;
      }
    }
    final spools = <int, SlotSpool>{};
    if (body?['slot_materials'] case final List<dynamic> slots) {
      for (final slot in slots.whereType<Map<String, dynamic>>()) {
        final id = toIntOrNull(slot['global_tray_id']);
        final spool = slot['spool'];
        if (id == null || spool is! Map<String, dynamic>) continue;
        // Brand, material, subtype — the web's `spoolDisplayName`.
        final name = [
          for (final k in const ['brand', 'material', 'subtype'])
            if (toStringOrNull(spool[k]) case final part? when part.isNotEmpty)
              part,
        ].join(' ');
        spools[id] = (
          name: name.isEmpty ? null : name,
          colorName: toStringOrNull(spool['color_name'])?.trim(),
        );
      }
    }
    return (grams: grams, spools: spools);
  }

  /// Filaments loaded on active printers of [model] (optionally filtered by
  /// [location]) — options for model-based filament overrides. Degrades to an
  /// empty list on failure (the override UI just shows no alternatives).
  Future<List<AvailableFilament>> fetchAvailableFilaments(
    String model, {
    String? location,
  }) => guard(() async {
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
      if (body == null) {
        throw const CreatePrinterException(CreatePrinterFailure.generic);
      }
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
  /// `PATCH /printers/{id}` — needs `printers:update`, which no API key holds.
  Future<Printer> updatePrinter(int id, PrinterUpdate data) => guard(() async {
    final res = await _dio.patch<Map<String, dynamic>>(
      Endpoints.printer(id),
      data: data.toJson(),
    );
    return Printer.fromJson(res.data!);
  });

  Future<PrinterDiagnosticResult> diagnose({
    required String ipAddress,
    String? serialNumber,
    String? accessCode,
  }) => guard(() async {
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
      return const CreatePrinterException(
        CreatePrinterFailure.connectionFailed,
      );
    }
    if (detail is String && detail.toLowerCase().contains('serial number')) {
      return const CreatePrinterException(CreatePrinterFailure.duplicateSerial);
    }
    return const CreatePrinterException(CreatePrinterFailure.generic);
  }

  /// List and statuses fetched in parallel.
  Future<List<PrinterWithStatus>> fetchAll() async {
    final printers = await fetchPrinters();
    final statuses = await Future.wait(printers.map((p) => fetchStatus(p.id)));
    return [
      for (var i = 0; i < printers.length; i++)
        PrinterWithStatus(printer: printers[i], status: statuses[i]),
    ];
  }
}
