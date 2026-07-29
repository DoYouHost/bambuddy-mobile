import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
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
void main() {
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

  test('an endpoint with nothing in it parses to nothing, not to an error',
      () async {
    // Both of these came back as `[]` from the live server: an empty library and
    // a queue with nothing waiting. Worth pinning — an empty list is the shape
    // the app spends most of its time rendering.
    mock('/api/v1/queue/', 'queue_pending.json');

    expect(await QueueRepository(dio).fetch(status: 'pending'), isEmpty);
  });
}
