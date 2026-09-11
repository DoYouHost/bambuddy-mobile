import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The half of the suite that needs a server with something in it.
///
/// `tool/ci/seed_bambuddy.py` walks a fresh container up to one printer that
/// reports a job in progress, one uploaded file and one queued item — over the
/// REST API and the printer's own MQTT topics, never the database. Every
/// assertion here reads that state back through the app's own repositories, so
/// a change in either the wire or our decoding of it lands as a failure with a
/// name rather than as an empty list that proves nothing.
void main() {
  group('seeded server contract', skip: contractSkipReason, () {
    late Dio dio;
    late PrintersRepository printers;
    late QueueRepository queue;
    late LibraryRepository library;

    setUpAll(() async {
      dio = await authenticatedDio();
      printers = PrintersRepository(dio);
      queue = QueueRepository(dio);
      library = LibraryRepository(dio);
    });

    test('the seeded printer decodes, and it is the seeded one', () async {
      final all = await printers.fetchPrinters();

      expect(
        all,
        isNotEmpty,
        reason:
            'no printer — the seed could not open an MQTT session against '
            'the broker, so POST /printers/ refused it and every assertion '
            'below is about an empty server',
      );
      expect(all.first.model, 'X1C');
    });

    test('a running job decodes into PrinterStatus', () async {
      // Published as a retained MQTT report, ingested by the server, handed
      // back over REST: the full path a real printer's state takes, with only
      // the hardware swapped out.
      final all = await printers.fetchPrinters();
      final status = await printers.fetchStatus(all.first.id);

      expect(status, isNotNull, reason: 'the server has no status to give');
      expect(status!.state, 'RUNNING');
      expect(
        status.progress,
        closeTo(42, 0.01),
        reason: 'mc_percent is no longer what the app reads as progress',
      );
    });

    test('PrinterStatus decodes live AMS units and trays', () async {
      final all = await printers.fetchPrinters();
      final status = await printers.fetchStatus(all.first.id);

      expect(status, isNotNull, reason: 'the server has no status to give');
      expect(status!.ams, isNotNull, reason: 'AMS payload did not make it');

      final trays = status.ams!
          .expand((u) => u.trays ?? const <AmsTray>[])
          .toList();
      expect(trays.length, 2);

      // The seed payload wrote RRGGBBAA with a full alpha byte; if that
      // vanished or shifted into a 6-char hex somewhere on the wire, the
      // app's color parser would misread it.
      expect(trays.first.trayColor, matches(RegExp(r'^[0-9A-Fa-f]{8}$')));
      expect(trays.map((t) => t.trayColor).toSet().length, 2);
      expect(trays.map((t) => t.trayType).toSet(), {'PLA'});
    });

    test('AMS trays survive the trip from the wire', () async {
      // Two slots of one material in two colours — the shape the queue
      // assertion below depends on, checked here at its source.
      final all = await printers.fetchPrinters();
      final filaments = await printers.fetchAvailableFilaments(
        all.first.model ?? 'X1C',
      );

      expect(
        filaments.length,
        2,
        reason:
            'expected both loaded trays; the endpoint deduplicates by type '
            'AND sub-brand, so two same-material trays only stay distinct '
            'while their colours do',
      );
      expect(filaments.map((f) => f.type).toSet(), {'PLA'});
      expect(
        filaments.map((f) => f.color).toSet().length,
        2,
        reason:
            'both trays reported the same colour; the AMS payload lost the '
            'per-tray distinction somewhere between publish and read',
      );
    });

    test('a queue item can carry more colours than types', () async {
      // The contract behind queue_filament_pairing_test: the app renders one
      // row per slot, and it can only do that while the server keeps sending
      // the two lists at different lengths. `services/archive.py` deduplicates
      // each list on its own, so one material in two colours collapses to a
      // single type with both colours intact.
      final items = await queue.fetch();

      expect(items, isNotEmpty, reason: 'nothing queued — seed did not finish');
      final QueueItem item = items.first;

      final types = (item.filamentType ?? '')
          .split(',')
          .where((s) => s.trim().isNotEmpty)
          .length;
      final colors = (item.filamentColor ?? '')
          .split(',')
          .where((s) => s.trim().isNotEmpty)
          .length;

      expect(types, 1, reason: 'filament_type: ${item.filamentType}');
      expect(
        colors,
        2,
        reason:
            'filament_color was ${item.filamentColor} — the server stopped '
            'sending a colour per slot, so the pairing the queue editor does '
            'is now measuring something else',
      );
      expect(
        colors,
        greaterThan(types),
        reason:
            'the lists are the same length again; if that is deliberate '
            'upstream, the both-directions handling in queue_edit_screen can '
            'be reconsidered — do not just relax this',
      );
    });

    test(
      'seeded queue item decodes metadata linked to printer and library file',
      () async {
        final items = await queue.fetch();
        final printersList = await printers.fetchPrinters();
        final files = await library.listFiles();

        expect(items, isNotEmpty, reason: 'no queue item found');
        final item = items.first;
        final printer = printersList.first;
        final file = files.firstWhere((f) => f.filename == 'contract-probe.3mf');

        expect(item.printerId, printer.id);
        expect(item.printerName, printer.name);
        expect(item.libraryFileId, file.id);
        expect(item.libraryFileName, file.filename);
        expect(item.statusKind, QueueItemStatusKind.pending);
      },
    );

    test(
      'a running job decodes extended telemetry into PrinterStatus',
      () async {
        final all = await printers.fetchPrinters();
        final status = await printers.fetchStatus(all.first.id);

        expect(status, isNotNull, reason: 'the server has no status to give');
        expect(status!.currentPrint, 'contract-probe.3mf');
        expect(status.temperatures?['nozzle'], closeTo(215.0, 0.1));
        expect(status.temperatures?['bed'], closeTo(60.0, 0.1));
        expect(status.layerNum, 30);
        expect(status.totalLayers, 120);
      },
    );

    test('the seeded library file decodes into LibraryFile', () async {
      final files = await library.listFiles();

      expect(files, isNotEmpty, reason: 'no library files found');
      final file = files.firstWhere(
        (f) => f.filename == 'contract-probe.3mf',
        orElse: () => throw StateError(
          'contract-probe.3mf missing from library: '
          '${files.map((f) => f.filename).toList()}',
        ),
      );
      expect(file.fileSize, greaterThan(0));
    });

    test('library file plates endpoint decodes through PlateList', () async {
      final files = await library.listFiles();
      final file = files.firstWhere((f) => f.filename == 'contract-probe.3mf');

      final plateList = await library.plates(file.id);
      expect(plateList.plates, isNotEmpty);
      expect(plateList.plates.first.index, 1);
    });

    test(
      'queue item options update round-trips through PATCH /api/v1/queue/{id}',
      () async {
        final items = await queue.fetch();
        expect(items, isNotEmpty, reason: 'no queue item to update');
        final item = items.first;

        await queue.updateItem(
          item.id,
          manualStart: true,
          timelapse: true,
        );

        final updated = (await queue.fetch()).firstWhere(
          (it) => it.id == item.id,
        );
        expect(updated.manualStart, isTrue);
        expect(updated.timelapse, isTrue);
      },
    );

    test(
      'queue item filament overrides round-trip in model-based mode',
      () async {
        final items = await queue.fetch();
        expect(items, isNotEmpty, reason: 'no queue item to update');
        final item = items.first;

        final overrides = [
          {
            'slot_id': 1,
            'type': 'PLA',
            'color': '#00FF00',
            'color_name': '#00FF00',
            'force_color_match': true,
          },
        ];

        await queue.updateItem(
          item.id,
          printerId: null,
          targetModel: 'X1C',
          filamentOverrides: overrides,
        );

        final updated = (await queue.fetch()).firstWhere(
          (it) => it.id == item.id,
        );
        expect(updated.printerId, isNull);
        expect(updated.targetModel, 'X1C');
        expect(updated.filamentOverrides, isNotNull);
        expect(updated.filamentOverrides!.length, 1);
        expect(updated.filamentOverrides!.first['slot_id'], 1);
        expect(updated.filamentOverrides!.first['type'], 'PLA');
        expect(updated.filamentOverrides!.first['force_color_match'], isTrue);
      },
    );
  });
}
