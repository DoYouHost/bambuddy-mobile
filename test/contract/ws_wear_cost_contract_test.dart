import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_create.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Printer wear (#694) as the server writes it: a rate on the printer, a run
/// through the stand-in printer, and the wear that run was charged read back
/// by the app's own parsers from the print log, the slim archive list and the
/// period totals.
///
/// On a server before #694 the same parsers must read "nothing recorded" — the
/// keys are absent there, and a zero or a throw would both be wrong.
///
/// **This file moves the seeded printer off its running job**, so it is named
/// to sort last with the other `ws_` files.
void main() {
  group('printer wear cost', skip: brokerSkipReason, () {
    late Dio dio;
    late PrintersRepository printers;
    late Printer printer;
    late String serial;
    late bool served;

    setUpAll(() async {
      dio = await authenticatedDio();
      printers = PrintersRepository(dio);
      printer = (await printers.fetchPrinters()).first;
      serial = printer.serialNumber!;
      served = printer.servesWearCost;
    });

    /// The edit form's save, as it would go out for [printer] with [rate].
    Future<Printer> saveRate(double? rate) => printers.updatePrinter(
      printer.id,
      PrinterUpdate(
        name: printer.name,
        ipAddress: printer.ipAddress!,
        autoArchive: printer.autoArchive ?? true,
        isActive: printer.isActive ?? true,
        model: printer.model,
        location: printer.location,
        wearCostPerHour: rate,
        sendWearCost: printer.servesWearCost,
      ),
    );

    test('the edit form saves a printer back unchanged', () async {
      final saved = await saveRate(printer.wearCostPerHour);
      expect(saved.name, printer.name);
      expect(saved.ipAddress, printer.ipAddress);
      expect(saved.location, printer.location);
      expect(saved.autoArchive, printer.autoArchive);
      expect(saved.isActive, printer.isActive);
      expect(saved.servesWearCost, served);
    });

    test('the rate the edit form sends is the rate the server keeps', () async {
      if (!served) return markTestSkipped('the server predates #694');
      expect((await saveRate(2.5)).wearCostPerHour, 2.5);
      // Zero is how the web turns it off; the server stores that as null.
      expect((await saveRate(0)).wearCostPerHour, isNull);
    });

    test('an older server leaves every wear figure blank', () async {
      if (served) return markTestSkipped('the server has #694');
      final stats = await StatsRepository(dio).fetch();
      expect(stats.totalWearCost, 0);
      final slim = await StatsRepository(dio).fetchSlim();
      expect(slim.map((a) => a.wearCost), everyElement(isNull));
    });

    test(
      'a run on a printer with a rate is charged its wear',
      () async {
        if (!served) return markTestSkipped('the server predates #694');
        // 36 an hour is a cent a second, so even a run of a few seconds
        // rounds to something above zero at the server's three decimals.
        await saveRate(36);
        addTearDown(() => saveRate(null));
        // Saving the address reconnects the printer, as the web's save does;
        // a report before it is back is lost.
        await pollUntil(
          'the printer back on its broker',
          () async =>
              (await printers.fetchStatus(printer.id))?.connected == true
              ? true
              : null,
          within: const Duration(minutes: 1),
          every: const Duration(seconds: 1),
        );

        const name = 'wear-probe.3mf';
        await publishReport(serial, {
          'gcode_state': 'FINISH',
          'mc_percent': 100,
        });
        await Future<void>.delayed(const Duration(seconds: 3));
        await publishReport(serial, {
          'gcode_state': 'RUNNING',
          'mc_percent': 5,
          'subtask_name': name,
          'gcode_file': name,
        });
        // The archive appears once the server has given up on the stand-in's
        // FTP; a finish before that has no run to close.
        await pollUntil(
          'the probe archive',
          () async {
            final rows = (await dio.get<List<dynamic>>(
              Endpoints.archives,
            )).data!;
            return rows.whereType<Map<String, dynamic>>().any(
                  (r) => '${r['print_name']}'.startsWith('wear-probe'),
                )
                ? true
                : null;
          },
          within: const Duration(minutes: 2),
          every: const Duration(seconds: 2),
        );
        await Future<void>.delayed(const Duration(seconds: 5));
        await publishReport(serial, {
          'gcode_state': 'FINISH',
          'mc_percent': 100,
          'subtask_name': name,
          'gcode_file': name,
        });

        final run = await pollUntil(
          'a logged run with its wear',
          () async {
            final page = await PrintLogRepository(
              dio,
            ).list(search: 'wear-probe');
            return page.items.where((e) => e.wearCost != null).firstOrNull;
          },
          within: const Duration(minutes: 1),
          every: const Duration(seconds: 2),
        );
        expect(run.wearCost, greaterThan(0));
        // The rate times the run's own duration, as `wear_cost_for_run` has it.
        expect(run.wearCost, closeTo(run.durationSeconds! / 3600 * 36, 0.001));

        final slim = await StatsRepository(dio).fetchSlim();
        expect(
          slim
              .where((a) => (a.printName ?? '').startsWith('wear-probe'))
              .map((a) => a.wearCost),
          contains(run.wearCost),
        );
        final stats = await StatsRepository(dio).fetch();
        expect(stats.totalWearCost, greaterThanOrEqualTo(run.wearCost!));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('project totals carry the wear key on a server that has it', () async {
      final created = (await dio.post<Map<String, dynamic>>(
        Endpoints.projects,
        data: {'name': 'wear-probe-project'},
      )).data!;
      final id = created['id'] as int;
      addTearDown(() => dio.delete<dynamic>(Endpoints.project(id)));
      final raw = (await dio.get<Map<String, dynamic>>(
        Endpoints.project(id),
      )).data!;
      final stats = raw['stats'] as Map<String, dynamic>;
      expect(stats.containsKey('total_wear_cost'), served);
      expect(ProjectStats.fromJson(stats).totalWearCost, 0);
    });
  });
}
