import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// What `POST /printers/{id}/hms/clear` really does to a fault the printer
/// keeps reporting (#56): the server empties its own list and sends
/// `clean_print_error`, but rebuilds the list from the next `hms` push.
void main() {
  group('HMS clear', skip: brokerSkipReason, () {
    late Dio dio;
    late int printerId;
    late String serial;

    // AMS A slot 1 feed resistance, the fault from the report.
    const fault = {'attr': 0x07002000, 'code': 0x00020025};

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

    Future<List<HmsError>> errors() async {
      final status = PrinterStatus.fromJson(
        (await dio.get<Map<String, dynamic>>(
          Endpoints.printerStatus(printerId),
        )).data!,
      );
      return status.hmsErrors ?? const <HmsError>[];
    }

    test(
      'a fault the printer keeps reporting comes back after a 200',
      () async {
        await publishReport(serial, {
          'hms': [fault],
        });
        await pollUntil(
          'the fault on the printer status',
          () async => (await errors()).isEmpty ? null : true,
          within: const Duration(seconds: 30),
          every: const Duration(milliseconds: 500),
        );

        final cleared = await dio.post<Map<String, dynamic>>(
          Endpoints.hmsClear(printerId),
        );
        expect(cleared.statusCode, 200);
        expect(cleared.data!['success'], isTrue);
        expect(await errors(), isEmpty, reason: 'the server empties its list');

        // The stand-in printer, like the real one, goes on reporting the fault.
        await publishReport(serial, {
          'hms': [fault],
        });
        final back = await pollUntil(
          'the fault reported again',
          () async {
            final e = await errors();
            return e.isEmpty ? null : e;
          },
          within: const Duration(seconds: 30),
          every: const Duration(milliseconds: 500),
        );
        expect(back.single.code, '0x20025');
      },
    );
  });
}
