// The server waits for the printer's status after every page, so a job is
// seconds a label — more than the default 30 s allows.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsd/nsd.dart';

import 'contract_harness.dart';

/// The label print server (DoYouHost/brother-ql-print-server), for real: the
/// server process, not a mock of what its README says.
///
/// `LABEL_PRINTER_CONTRACT_URL` is where it listens. `LABEL_PRINTER_CONTRACT_OUT`
/// is the file it was started to print into (`PRINTER_IDENTIFIER=file://…`), so
/// a test can look at what would have reached the printer; with
/// `LABEL_PRINTER_CONTRACT_CONTAINER` the file is inside that container and is
/// read through `docker exec`, as the stand-in printer's broker is. Labels come from the
/// bambuddy of the other contract tests, so the PDF that is printed is the PDF
/// the app really sends. `LABEL_PRINTER_CONTRACT_MDNS=1` adds the discovery
/// half, which needs `avahi-browse` and the server announced through Avahi.
void main() {
  final url = Platform.environment['LABEL_PRINTER_CONTRACT_URL'];
  final out = Platform.environment['LABEL_PRINTER_CONTRACT_OUT'];
  final container = Platform.environment['LABEL_PRINTER_CONTRACT_CONTAINER'];
  final skip = (url ?? '').isEmpty
      ? 'LABEL_PRINTER_CONTRACT_URL is unset — no label print server'
      : null;

  group('label print server contract', skip: skip, () {
    late LabelPrinterRepository repo;
    late Dio bambuddy;
    late NativeInventorySource source;
    late Uint8List label;
    final spoolIds = <int>[];

    setUpAll(() async {
      repo = LabelPrinterRepository(createLabelPrinterDio(url!));
      if (contractSkipReason != null) return;
      bambuddy = await authenticatedDio();
      source = NativeInventorySource(bambuddy);
      final spool = await source.createSpool(
        const SpoolDraft(
          material: 'PLA',
          brand: 'Printer contract',
          colorName: 'Teal',
          labelWeight: 1000,
        ),
      );
      spoolIds.add(spool.id);
      label = await source.renderLabels(
        SpoolLabelRequest(
          spoolIds: spoolIds,
          template: SpoolLabelTemplate.box62x29,
        ),
      );
    });

    tearDownAll(() async {
      if (contractSkipReason != null) return;
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await bambuddy.delete<dynamic>(
          Endpoints.inventorySpool(id),
          options: quiet,
        );
      }
    });

    Future<void> emptyPrinterFile() async {
      if ((container ?? '').isEmpty) {
        await File(out!).writeAsBytes(const []);
        return;
      }
      final r = await Process.run('docker', [
        'exec',
        container!,
        'sh',
        '-c',
        ': > $out',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    Future<Uint8List> readPrinterFile() async {
      if ((container ?? '').isEmpty) return File(out!).readAsBytes();
      final r = await Process.run('docker', [
        'exec',
        container!,
        'cat',
        out!,
      ], stdoutEncoding: null);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return Uint8List.fromList(r.stdout as List<int>);
    }

    /// What the printer was sent for one job.
    Future<Uint8List> printed({
      Uint8List? pdf,
      int copies = 1,
      bool cutAtEnd = true,
      int cutEvery = 0,
    }) async {
      await emptyPrinterFile();
      await repo.printPdf(
        pdf ?? label,
        filename: 'labels.pdf',
        copies: copies,
        cutAtEnd: cutAtEnd,
        cutEvery: cutEvery,
      );
      return readPrinterFile();
    }

    final needsPrinterFile = out == null || out.isEmpty
        ? 'LABEL_PRINTER_CONTRACT_OUT is unset'
        : contractSkipReason;

    test('/info reads as the app expects', () async {
      final info = await repo.info();

      expect(info, isNotNull);
      expect(info!.model, isNotEmpty);
      expect(info.connected, isTrue);
      // Which templates the app defaults to the printer for — and the ones it
      // does not, which the server then refuses (see the 40 x 30 test below).
      expect(info.takes(SpoolLabelTemplate.box62x29), isTrue);
      expect(info.takes(SpoolLabelTemplate.box40x30), isFalse);
    });

    test('the copy limit the stepper uses is the server\'s', () async {
      // A server that raised or lowered `MAX_COPIES` would leave the stepper
      // offering a number it refuses, or hiding one it takes.
      expect((await repo.info())!.maxCopies, labelPrinterMaxCopies);
    });

    test('bambuddy is not taken for a label print server', () async {
      // The mistake a typed address makes: right host, wrong service.
      if (contractSkipReason case final reason?) {
        markTestSkipped(reason);
        return;
      }
      final wrong = LabelPrinterRepository(
        createLabelPrinterDio(contractBaseUrl),
      );
      expect(await wrong.info(), isNull);
    });

    test('nothing listening is not a label print server either', () async {
      final nothing = LabelPrinterRepository(
        createLabelPrinterDio('http://127.0.0.1:1'),
      );
      expect(await nothing.info(), isNull);
    });

    test('an address typed without a scheme or port reaches it', () async {
      final typed = normalizeLabelPrinterUrl(
        '${Uri.parse(url!).host}:${Uri.parse(url).port}',
      );
      final info = await LabelPrinterRepository(
        createLabelPrinterDio(typed),
      ).info();
      expect(info, isNotNull);
    });

    test('the 62 x 29 labels bambuddy renders are printed', () async {
      final sent = await printed();
      expect(sent, isNotEmpty);
    }, skip: needsPrinterFile);

    test('the same job prints the same bytes every time', () async {
      // The baseline the next comparisons stand on.
      expect(await printed(), await printed());
    }, skip: needsPrinterFile);

    test('copies multiply what the printer is sent', () async {
      final one = (await printed()).length;
      final three = (await printed(copies: 3)).length;

      expect(three / one, closeTo(3, 0.1));
    }, skip: needsPrinterFile);

    test('the cutter options change what the printer is sent', () async {
      final base = await printed();

      expect(await printed(cutAtEnd: false), isNot(base));

      // `cut_every` counts labels across the job, and the last one is the end
      // cut's to decide — so a single label cannot show it, two can.
      final two = await printed(copies: 2);
      expect(await printed(copies: 2, cutEvery: 1), isNot(two));
      expect(await printed(cutEvery: 1), base);
    }, skip: needsPrinterFile);

    test(
      'a label of another shape is refused with the reason',
      () async {
        // 40 x 30 mm is 4 : 3, which is not the loaded 62 : 29 stock.
        final other = await source.renderLabels(
          SpoolLabelRequest(
            spoolIds: spoolIds,
            template: SpoolLabelTemplate.box40x30,
          ),
        );

        await expectLater(
          printed(pdf: other),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 400)
                .having((e) => e.detail, 'detail', isNotNull),
          ),
        );
      },
      skip: needsPrinterFile,
    );

    test('more copies than the server takes is refused', () async {
      await expectLater(
        repo.printPdf(
          Uint8List(0),
          filename: 'labels.pdf',
          copies: labelPrinterMaxCopies + 1,
        ),
        throwsA(isA<ApiException>()),
      );
    }, skip: needsPrinterFile);
  });

  final mdns = Platform.environment['LABEL_PRINTER_CONTRACT_MDNS'] == '1'
      ? null
      : 'LABEL_PRINTER_CONTRACT_MDNS is not 1';

  group('label print server discovery contract', skip: skip ?? mdns, () {
    /// The announcement as Avahi resolves it: one `=` line per interface and
    /// address family, TXT records last.
    Future<List<Service>> browse() async {
      final result = await Process.run('avahi-browse', [
        '-rpt',
        labelPrinterServiceType,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      String unescape(String s) => s.replaceAllMapped(
        RegExp(r'\\(\d{3})'),
        (m) => String.fromCharCode(int.parse(m[1]!)),
      );
      return [
        for (final line in (result.stdout as String).split('\n'))
          if (line.startsWith('=') && line.split(';')[2] == 'IPv4')
            () {
              final f = line.split(';');
              final txt = <String, Uint8List?>{
                for (final m in RegExp(
                  r'"([^"]*)"',
                ).allMatches(f.sublist(9).join(';')))
                  m[1]!.split('=').first: Uint8List.fromList(
                    m[1]!.substring(m[1]!.indexOf('=') + 1).codeUnits,
                  ),
              };
              return Service(
                name: unescape(f[3]),
                type: f[4],
                host: f[6],
                port: int.parse(f[8]),
                addresses: [InternetAddress(f[7])],
                txt: txt,
              );
            }(),
      ];
    }

    test(
      'what the server announces is what the app turns into an address',
      () async {
        final services = await browse();
        expect(services, isNotEmpty, reason: 'nothing announced on the LAN');

        final found = [for (final s in services) ?labelPrinterFromService(s)];
        final port = Uri.parse(url!).port;
        final mine = found.where((p) => p.baseUrl.endsWith(':$port'));
        expect(mine, isNotEmpty);

        final p = mine.first;
        // A number, not `<host>.local`: Android does not resolve those
        // reliably, which the server's README warns about, and a desktop would
        // not notice.
        expect(
          Uri.parse(p.baseUrl).host,
          matches(RegExp(r'^\d{1,3}(\.\d{1,3}){3}$')),
        );

        // The address the app would store works, and the announcement agrees
        // with `/info` — the server's own promise that the two never disagree.
        final info = await LabelPrinterRepository(
          createLabelPrinterDio(p.baseUrl),
        ).info();
        expect(info, isNotNull, reason: 'cannot reach ${p.baseUrl}');
        expect(p.model, info!.model);
        expect(p.labelId, info.labelId);
      },
    );
  });
}
