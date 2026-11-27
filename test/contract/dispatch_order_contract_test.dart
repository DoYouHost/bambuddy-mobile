import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_create.dart';
import 'package:bambuddy_mobile/core/models/queue_settings.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// The order an "Any model" job picks its printer in, and the per-printer
/// priority it can follow (server #2915, 1.3.2): what the app reads, what it
/// sends, and what the server keeps.
///
/// Both halves are silent drops below 1.3.2 — `AppSettingsUpdate` and
/// `PrinterUpdate` take an unknown field and say nothing — so the same file
/// proves the app offers neither where they would vanish. Written to pass on
/// the newest server and on the last release alike.
void main() {
  group('any-model dispatch order', skip: contractSkipReason, () {
    late Dio dio;
    late ServerSettingsRepository settings;
    late PrintersRepository printers;
    late Printer printer;
    late bool served;
    String? originalOrder;

    setUpAll(() async {
      dio = await authenticatedDio();
      settings = ServerSettingsRepository(dio);
      printers = PrintersRepository(dio);
      printer = (await printers.fetchPrinters()).first;
      final map = await settings.fetch();
      served = map.containsKey('model_dispatch_order');
      originalOrder = map['model_dispatch_order'] as String?;
    });

    tearDownAll(() async {
      if (originalOrder != null) {
        await settings.update({'model_dispatch_order': originalOrder});
      }
      await _savePriority(printers, printer, printer.dispatchPriority);
    });

    test('both halves appear together or not at all', () async {
      expect(
        printer.servesDispatchPriority,
        served,
        reason:
            'the setting and the printer field came in one server commit; a '
            'server with one and not the other would show a field that drops',
      );
      expect(
        QueueSettings.fromSettings(
          await settings.fetch(),
        ).known.contains(QueueSetting.dispatchOrder),
        served,
      );
    });

    test('every order the app can write is kept and read back', () async {
      if (!served) return markTestSkipped('the server predates #2915');
      for (final order in ModelDispatchOrder.values) {
        final fresh = await settings.update(
          QueueSettings.patch(QueueSetting.dispatchOrder, order),
        );

        expect(fresh['model_dispatch_order'], order.wire);
        expect(
          QueueSettings.fromSettings(await settings.fetch()).dispatchOrder,
          order,
        );
      }
    });

    test('the server refuses a string outside the four', () async {
      if (!served) return markTestSkipped('the server predates #2915');
      final res = await dio.put<dynamic>(
        Endpoints.appSettingsUpdate,
        data: {'model_dispatch_order': 'most_wear'},
        options: Options(validateStatus: (_) => true),
      );

      expect(
        res.statusCode,
        422,
        reason: 'it is a Literal, which is why the app offers only a choice',
      );
    });

    test('a priority is kept, zero is a priority, empty clears it', () async {
      if (!served) return markTestSkipped('the server predates #2915');

      expect((await _savePriority(printers, printer, 7)).dispatchPriority, 7);
      expect((await _savePriority(printers, printer, 0)).dispatchPriority, 0);
      final cleared = await _savePriority(printers, printer, null);
      expect(cleared.dispatchPriority, isNull);
      expect(
        cleared.servesDispatchPriority,
        isTrue,
        reason: 'a cleared priority is still a null the key carries',
      );
    });

    test('the save the edit form sends is stored and read back', () async {
      if (!served) return markTestSkipped('the server predates #2915');
      final [answer] = await replayWrites(
        dio,
        recordedWrites('printer_dispatch_priority_save'),
        item: printer.id,
        // The recording is the demo's X1 Carbon; the rest of the body is this
        // server's own printer, so the replay changes only the priority.
        ids: {
          'name': printer.name,
          'ip_address': printer.ipAddress,
          'model': printer.model,
          'location': printer.location,
          'auto_archive': printer.autoArchive,
          'is_active': printer.isActive,
          'wear_cost_per_hour': printer.wearCostPerHour,
        },
      );
      expect(answer.statusCode, 200, reason: '${answer.data}');

      final row = (await printers.fetchPrinters()).firstWhere(
        (p) => p.id == printer.id,
      );
      expect(row.dispatchPriority, 0);
    });

    test('the write the settings row sends is stored and read back', () async {
      if (!served) return markTestSkipped('the server predates #2915');
      final [answer] = await replayWrites(
        dio,
        recordedWrites('dispatch_order_save'),
      );
      expect(answer.statusCode, 200, reason: '${answer.data}');

      expect(
        QueueSettings.fromSettings(await settings.fetch()).dispatchOrder,
        ModelDispatchOrder.priority,
      );
    });

    test(
      'the ceiling the app clamps to is accepted, one above is not',
      () async {
        if (!served) return markTestSkipped('the server predates #2915');

        final top = await _savePriority(
          printers,
          printer,
          PrinterUpdate.maxDispatchPriority,
        );
        expect(top.dispatchPriority, PrinterUpdate.maxDispatchPriority);

        final over = await dio.patch<dynamic>(
          Endpoints.printer(printer.id),
          data: {'dispatch_priority': PrinterUpdate.maxDispatchPriority + 1},
          options: Options(validateStatus: (_) => true),
        );
        expect(over.statusCode, 422);
      },
    );

    test('saving the printer without the field leaves the priority', () async {
      if (!served) return markTestSkipped('the server predates #2915');
      await _savePriority(printers, printer, 4);

      // What an editor does on a server that does not know the field.
      final saved = await printers.updatePrinter(
        printer.id,
        saveOf(printer, served: const {}),
      );

      expect(saved.dispatchPriority, 4);
    });

    test(
      'an older server shows neither key, so the app offers neither',
      () async {
        if (served) return markTestSkipped('the server knows #2915');

        final map = await settings.fetch();
        expect(map.containsKey('model_dispatch_order'), isFalse);
        expect(printer.servesDispatchPriority, isFalse);
        expect(printer.dispatchPriority, isNull);
      },
    );
  });
}

/// The edit form's save for [printer] with [priority], on a server that serves it.
Future<Printer> _savePriority(
  PrintersRepository printers,
  Printer printer,
  int? priority,
) => printers.updatePrinter(
  printer.id,
  saveOf(printer, dispatchPriority: priority),
);
