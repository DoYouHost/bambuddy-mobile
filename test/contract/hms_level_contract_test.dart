import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The HMS level as the app reads it, off faults the stand-in printer raises.
///
/// `severity` changed meaning in #2728 — the part byte before it, the level
/// after — so the app reads the level from `code`, which every server sends the
/// same way. This pins that `code` keeps carrying it on both generations, and
/// that a print-stopping fault reaches the notification rule as one.
void main() {
  group('HMS level', skip: brokerSkipReason, () {
    late Dio dio;
    late int printerId;
    late String serial;

    setUpAll(() async {
      dio = await authenticatedDio();
      final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      final first = printers.first as Map;
      printerId = first['id'] as int;
      serial = first['serial_number'] as String;
    });

    tearDownAll(() async {
      await publishReport(serial, {'hms': <Object>[], 'print_error': 0});
    });

    test('code carries the level of both kinds of fault', () async {
      // An hms[] fault at level 1 (task stopped) and a print_error runout,
      // whose 0x8xxx error is a pause.
      await publishReport(serial, {
        'hms': [
          {'attr': 0x05000500, 'code': 0x00010007},
        ],
        'print_error': 0x03008004,
      });

      final errors = await pollUntil(
        'both faults on the printer status',
        () async {
          final status = PrinterStatus.fromJson(
            (await dio.get<Map<String, dynamic>>(
              Endpoints.printerStatus(printerId),
            )).data!,
          );
          final errors = status.hmsErrors ?? const <HmsError>[];
          return errors.length >= 2 ? errors : null;
        },
        within: const Duration(seconds: 30),
        every: const Duration(milliseconds: 500),
      );

      final hms = errors.singleWhere((e) => e.isHmsChannel);
      final printError = errors.singleWhere((e) => !e.isHmsChannel);
      expect(hms.level, 1);
      expect(printError.level, 2);
      expect(
        hmsIsNotifiable(hms, description: 'described'),
        isTrue,
        reason: 'a fault that stops the print must be able to alert',
      );
    });
  });
}
