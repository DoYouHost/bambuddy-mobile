import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/printer.dart';
import '../core/models/printer_status.dart';

/// Drukarka razem ze statusem (status bywa niedostępny niezależnie
/// od listy — np. drukarka odłączona albo pojedynczy endpoint padł).
class PrinterWithStatus {
  const PrinterWithStatus({required this.printer, this.status});

  final Printer printer;
  final PrinterStatus? status;
}

/// REST-owe źródło danych o drukarkach. W M2 dojdzie scalanie z WS —
/// ta ścieżka zostaje na zawsze jako backfill po wznowieniu i fallback.
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
        // Pojedynczy niesparsowalny wpis nie może zabić całej listy.
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
      // Auth musi wypłynąć (UI odsyła do konfiguracji); reszta degraduje
      // się do karty „status niedostępny" zamiast wywracać dashboard.
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

  /// Lista + statusy pobierane równolegle.
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
