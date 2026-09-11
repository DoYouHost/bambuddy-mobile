import 'package:bambuddy_mobile/core/models/queue_item.dart';
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

    setUpAll(() async {
      dio = await authenticatedDio();
      printers = PrintersRepository(dio);
      queue = QueueRepository(dio);
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
  });
}
