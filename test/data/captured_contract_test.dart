import 'dart:io';

import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// The contract, held against what a live bambuddy actually answers.
///
/// Every fixture here was captured with `tool/capture_fixtures.sh` from a real
/// server (see test/fixtures/README.md), so these tests fail when the server
/// changes a field the app casts hard — which is the failure that otherwise
/// arrives as a screen that renders nothing and a 200 in the log.
///
/// They deliberately go through the repositories rather than the models: the
/// tolerant list parsing that hides a broken record lives there, so a record
/// silently dropped would pass a model test and fail here.
///
/// `test/fixtures/captured/` is **untracked** — the payloads carry the server
/// owner's own data (see test/fixtures/README.md), so they live on the machine
/// that captured them and nowhere else. Without them this file has nothing to
/// hold the contract against, and it says so out loud rather than passing on an
/// empty set: a green run that checked nothing is worse than a skip that names
/// the command to fix it.
void main() {
  final captures = Directory('test/fixtures/captured');
  final missing = captures.existsSync() && captures.listSync().isNotEmpty
      ? null
      : 'brak test/fixtures/captured — zrób zrzut z własnego serwera: '
          'tool/capture_fixtures.sh https://twój.serwer';

  if (missing != null) {
    // One named skip instead of eleven identical ones, and nothing below is
    // registered — a test that cannot reach its fixture has no assertion to make.
    test('kontrakt na przechwyconych payloadach', () {}, skip: missing);
    return;
  }

  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
  });

  /// Answers [path] with a captured fixture and reports how many records it held,
  /// so every test below can assert "nothing was dropped" against the file.
  int mock(String path, String fixture) {
    final payload = readFixture('captured/$fixture');
    adapter.onGet(path, (server) => server.reply(200, payload));
    return payload is List ? payload.length : 1;
  }

  test('printers list parses whole, with the fields the dashboard reads', () async {
    final count = mock('/api/v1/printers/', 'printers_list.json');

    final printers = await PrintersRepository(dio).fetchPrinters();

    expect(printers, hasLength(count));
    expect(printers.first.name, isNotEmpty);
    expect(printers.first.model, 'X2D');
  });

  test('printer status parses, including AMS, temperatures and HMS', () async {
    mock('/api/v1/printers/1/status', 'printer_status.json');

    final status = await PrintersRepository(dio).fetchStatus(1);

    expect(status, isNotNull);
    expect(status!.state, isNotNull);
    // The dashboard card is built out of these; a type change in any of them
    // empties the card while the request still answers 200.
    expect(status.progress, isNotNull);
    expect(status.temperatures, isNotNull);
    expect(status.temperatures!['nozzle'], isNotNull);
    expect(status.temperatures!['bed'], isNotNull);
    expect(status.ams, isNotNull);
    expect(status.ams!.first.trays, isNotEmpty);
  });

  test('archives list parses whole', () async {
    final count = mock('/api/v1/archives/', 'archives_list.json');

    final archives = await ArchiveRepository(dio).list();

    expect(archives, hasLength(count));
    expect(archives.first.printName, isNotEmpty);
    expect(archives.first.status, isNotEmpty);
  });

  test('archive stats parse', () async {
    mock('/api/v1/archives/stats', 'archive_stats.json');

    final stats = await StatsRepository(dio).fetch();

    expect(stats.totalPrints, greaterThan(0));
    expect(stats.printsByPrinter, isNotEmpty);
  });

  // Older capture sets predate the print-log endpoint. Skipping by name beats
  // failing on a missing file: the rest of the captures still hold the
  // contract, and the message says what to re-run.
  final printLogCapture = File('test/fixtures/captured/print_log.json');

  test('print log page parses whole, with the fields a row shows', () async {
    // The page is an object, not a list, so the record count comes from
    // `items` rather than from `mock`'s return.
    final payload =
        readFixture('captured/print_log.json') as Map<String, dynamic>;
    adapter.onGet(
      '/api/v1/print-log/',
      (server) => server.reply(200, payload),
    );

    final page = await PrintLogRepository(dio).list();

    expect(page.items, hasLength((payload['items'] as List).length));
    // An empty log would make every assertion below vacuous — and a capture
    // that proves nothing should say so rather than pass.
    expect(page.items, isNotEmpty, reason: 'the captured print log has no rows');
    expect(page.total, greaterThanOrEqualTo(page.items.length));
    expect(page.items.first.status, isNotEmpty);
    expect(page.items.first.createdAt.year, greaterThan(2000));
  },
      skip: printLogCapture.existsSync()
          ? null
          : 'no captured/print_log.json — re-run tool/capture_fixtures.sh');

  test('spools parse whole, with what the filament screen shows', () async {
    final count = mock('/api/v1/inventory/spools', 'inventory_spools.json');

    final spools = await NativeInventorySource(dio).fetchSpools();

    expect(spools, hasLength(count));
    expect(spools.first.material, isNotNull);
    expect(spools.first.brand, isNotNull);
  });

  test('smart plugs parse whole', () async {
    final count = mock('/api/v1/smart-plugs/', 'smart_plugs.json');

    final plugs = await SmartPlugsRepository(dio).fetchPlugs();

    expect(plugs, hasLength(count));
    expect(plugs.first.name, isNotEmpty);
  });

  test('maintenance overview parses, items included', () async {
    final count = mock('/api/v1/maintenance/overview', 'maintenance_overview.json');

    final overview = await MaintenanceRepository(dio).fetchOverview();

    expect(overview, hasLength(count));
    expect(overview.first.maintenanceItems, isNotEmpty);
  });

  test('projects list parses whole', () async {
    final count = mock('/api/v1/projects/', 'projects_list.json');

    final projects = await ProjectsRepository(dio).list();

    expect(projects, hasLength(count));
    expect(projects.first.name, isNotEmpty);
  });

  test('queue parses whole, straight off the wire', () async {
    final count = mock('/api/v1/queue/', 'queue_all.json');

    final items = await QueueRepository(dio).fetch();

    expect(items, hasLength(count));
  });

  test('the captured queue really is the tri-state contract', () async {
    // This is the shape whose arrival emptied the queue screen: bambuddy 1.2.5
    // sends the three calibrations as `off`/`on`/`auto` strings, and the
    // generated `as bool?` cast threw on every record, so a correct 200 rendered
    // as "nothing queued" (docs/plans/07-queue-cali-enum.md).
    //
    // Asserted on the raw JSON as well as on the parsed model on purpose. The
    // parsed side alone would still pass if the fixture were re-captured from an
    // older server, because the reader accepts booleans too — and then this file
    // would quietly stop covering the contract it exists for.
    final raw = readFixture('captured/queue_all.json') as List<dynamic>;
    expect(
      raw.map((r) => (r as Map)['bed_levelling']),
      everyElement(isA<String>()),
      reason: 'fixture przechwycony ze serwera starszego niż 1.2.5?',
    );
    expect(
      raw.map((r) => (r as Map)['vibration_cali']),
      everyElement(isA<bool>()),
      reason: 'to pole nie migrowało i ma zostać boolem',
    );

    mock('/api/v1/queue/', 'queue_all.json');
    final items = await QueueRepository(dio).fetch();

    // Read back exactly what the server wrote, value for value. Deliberately not
    // "this fixture contains both on and off": which states a live queue happens
    // to hold changes with every re-capture, and a test that pins the sample
    // rather than the contract fails for reasons nobody wants to chase.
    for (var i = 0; i < items.length; i++) {
      final record = raw[i] as Map;
      expect(items[i].bedLevelling.name, record['bed_levelling']);
      expect(items[i].flowCali.name, record['flow_cali']);
      expect(items[i].nozzleOffsetCali.name, record['nozzle_offset_cali']);
    }
  });

  test('an endpoint with nothing in it parses to nothing, not to an error',
      () async {
    // An empty list is the shape the app spends most of its time rendering, so
    // it is worth pinning — but not against a captured fixture. This used to read
    // `queue_pending.json`, which was `[]` only because the queue happened to be
    // empty at capture time; one queued item later the fixture had a record in it
    // and this test failed for saying something true about the wrong thing.
    // `[]` is `[]`, and needs no server to prove it.
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, <dynamic>[]));

    expect(await QueueRepository(dio).fetch(status: 'pending'), isEmpty);
  });
}
