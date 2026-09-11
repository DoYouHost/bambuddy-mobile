import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/ams_history.dart';
import 'package:bambuddy_mobile/core/models/available_filament.dart';
import 'package:bambuddy_mobile/core/models/heater_history.dart';
import 'package:bambuddy_mobile/core/models/printable_object.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_diagnostic.dart';
import 'package:bambuddy_mobile/core/models/printer_file.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/skip_objects_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('printers contract', skip: contractSkipReason, () {
    late Dio dio;
    late PrintersRepository printers;
    late PrinterFilesRepository filesRepo;
    late AmsHistoryRepository amsHistory;
    late HeaterHistoryRepository heaterHistory;
    late SkipObjectsRepository skipObjects;

    setUpAll(() async {
      dio = await authenticatedDio();
      printers = PrintersRepository(dio);
      filesRepo = PrinterFilesRepository(dio);
      amsHistory = AmsHistoryRepository(dio);
      heaterHistory = HeaterHistoryRepository(dio);
      skipObjects = SkipObjectsRepository(dio);
    });

    test('GET /printers/ decodes printer list into Printer models', () async {
      final list = await printers.fetchPrinters();

      expect(list, isA<List<Printer>>());
      if (list.isNotEmpty) {
        final p = list.first;
        expect(p.id, greaterThan(0));
        expect(p.name, isNotEmpty);
        expect(p.model, isNotEmpty);
        expect(p.ipAddress, isNotEmpty);
      }
    });

    test('POST /printers/diagnostic executes connection probe', () async {
      final diag = await printers.diagnose(ipAddress: '127.0.0.1');

      expect(diag, isA<PrinterDiagnosticResult>());
      expect(diag.ipAddress, isNotEmpty);
      expect(diag.overall, anyOf('ok', 'warnings', 'problems'));
      expect(diag.checks, isA<List<DiagnosticCheck>>());
    });

    test('GET /printers/available-filaments returns filaments for known model', () async {
      final filaments = await printers.fetchAvailableFilaments('X1C');

      expect(filaments, isA<List<AvailableFilament>>());
      for (final f in filaments) {
        expect(f.type, isNotEmpty);
        expect(f.color, isNotEmpty);
      }
    });

    test('per-printer endpoints decode status, storage, sensors and objects', () async {
      final list = await printers.fetchPrinters();
      if (list.isEmpty) return;

      final printer = list.first;

      // 1. Status
      final status = await printers.fetchStatus(printer.id);
      expect(status, isA<PrinterStatus?>());
      if (status != null) {
        expect(status.state, isNotNull);
        expect(status.temperatures, isA<Map<String, double>?>());
      }

      // 2. Storage
      final storage = await filesRepo.fetchStorage(printer.id);
      expect(storage, isA<PrinterStorage>());

      // 3. AMS history
      final ams = await amsHistory.fetch(printer.id, 0, hours: 1);
      expect(ams, isA<AmsHistory>());
      expect(ams.printerId, printer.id);

      // 4. Heater history
      final heaters = await heaterHistory.fetch(printer.id, hours: 1);
      expect(heaters, isA<HeaterHistory>());
      expect(heaters.printerId, printer.id);

      // 5. Printable objects
      final objects = await skipObjects.fetchObjects(printer.id);
      expect(objects, isA<PrintableObjects>());
    });

    test('POST /printers/camera/stream-token or /auth/media-token returns usable token', () async {
      // Either camera token or media token must succeed depending on server generation
      var obtainedToken = false;
      try {
        final res = await dio.post<Map<String, dynamic>>(Endpoints.cameraStreamToken);
        final token = res.data?['token'];
        if (token is String && token.isNotEmpty) obtainedToken = true;
      } on DioException catch (e) {
        // Servers >= 1.2.5.5 prefer media-token or cameraStreamToken requires camera:view
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          rethrow;
        }
      }

      if (!obtainedToken) {
        try {
          final res = await dio.post<Map<String, dynamic>>(Endpoints.mediaToken);
          final token = res.data?['token'];
          if (token is String && token.isNotEmpty) obtainedToken = true;
        } on DioException catch (e) {
          if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
            rethrow;
          }
        }
      }

      expect(obtainedToken, isTrue, reason: 'At least one media/camera stream token route must work');
    });

    test('POST /printers/{id}/refresh-status asks printer to publish whole state', () async {
      final list = await printers.fetchPrinters();
      if (list.isEmpty) return;

      final printer = list.first;
      try {
        final res = await dio.post<dynamic>(Endpoints.printerRefreshStatus(printer.id));
        expect(res.statusCode, anyOf(200, 204));
      } on DioException catch (e) {
        // 400 when printer MQTT is disconnected in mock environments
        expect(e.response?.statusCode, anyOf(200, 204, 400));
      }
    });
  });
}
