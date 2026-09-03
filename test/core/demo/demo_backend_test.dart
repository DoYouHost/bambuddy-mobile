import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/demo/demo_http_adapter.dart';
import 'package:bambuddy_mobile/core/demo/demo_ws.dart';
import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/cloud_repository.dart';
import 'package:bambuddy_mobile/data/firmware_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract test: every repository the app uses must parse DemoBackend's
/// responses into non-empty, sensible models. Guards the fabricated dataset
/// against drifting away from the real parsers.
void main() {
  final dio = Dio(BaseOptions(baseUrl: DemoConfig.baseUrl))
    ..httpClientAdapter = DemoHttpClientAdapter(latency: Duration.zero);

  group('printers', () {
    test('list + statuses parse; simulated print is running', () async {
      final all = await PrintersRepository(dio).fetchAll();
      expect(all, hasLength(4));
      final printing = all.firstWhere((p) => p.printer.id == 1).status;
      expect(printing, isNotNull);
      expect(printing!.isPrinting, isTrue);
      expect(printing.progress, greaterThan(0));
      expect(printing.ams, isNotEmpty);
      final idle = all.firstWhere((p) => p.printer.id == 2).status;
      expect(idle!.state, 'IDLE');
      final offline = all.firstWhere((p) => p.printer.id == 3).status;
      expect(offline!.connected, isFalse);
      // The P2S carries both accessory fan kits — the four-tile layout.
      final p2s = all.firstWhere((p) => p.printer.id == 4).status;
      expect(p2s!.leftAuxFanSpeed, isNotNull);
      expect(p2s.usesExhaustFanLabel, isTrue);
      expect(p2s.chamberFanAvailable, isTrue);
    });
  });

  group('queue + archives + stats', () {
    test('queue has pending items', () async {
      final items = await QueueRepository(dio).fetch();
      expect(items.length, greaterThanOrEqualTo(2));
      expect(items.first.statusKind, QueueItemStatusKind.pending);
    });

    test('kolejka mówi kontraktem 1.2.5, razem z auto', () async {
      // Demo jest jedynym miejscem, w którym trójstanowe kalibracje da się
      // przejść bez serwera 1.2.5 — nasz chodzi na 0.2.5b2 i wysyła booleany.
      // Gdyby ten payload wrócił kiedyś do booleanów, demo przestałoby łapać
      // regresję, dla której zostało zmienione (docs/plans/07), i to w ciszy.
      final items = await QueueRepository(dio).fetch();

      expect(
        items.map((i) => i.bedLevelling),
        everyElement(CalibrationOption.auto),
      );
      expect(items.first.flowCali, CalibrationOption.off);
      expect(items.first.nozzleOffsetCali, CalibrationOption.auto);
      expect(items.first.vibrationCali, isTrue,
          reason: 'te trzy nie migrowały i zostają boolem');
    });

    test('demo raportuje wersję, która obsługuje trójstan', () async {
      // Bez tego formularz druku pokazałby w demo dwa stany nad
      // trójstanowymi danymi — payload i sonda muszą mówić to samo.
      final version = ServerVersionService(dio);

      expect(await version.reportedVersion(), isNotNull);
      expect(await version.supports(ServerFeature.triStateCalibration), isTrue);
    });

    test('the reported version matches what this backend actually serves',
        () async {
      // A version claiming less than the payload hides a control over data that
      // is there; claiming more shows one over data that is not. Both read as
      // "the app is broken", so the two are pinned together here.
      final version = ServerVersionService(dio);

      expect(await version.supports(ServerFeature.printLogCostEnergy), isTrue,
          reason: 'the print log serves cost, energy and sorting');
      expect(await version.supports(ServerFeature.crossModelVariants), isTrue,
          reason: 'library variant groups are served below');
    });

    test('archive list, search and purge preview', () async {
      final repo = ArchiveRepository(dio);
      final list = await repo.list();
      expect(list.length, greaterThanOrEqualTo(10));
      expect(list.first.printName, isNotNull);
      final found = await repo.search('benchy');
      expect(found, isNotEmpty);
      final preview = await repo.purgePreview(olderThanDays: 5);
      expect(preview.count, greaterThan(0));
    });

    test('stats, slim, failures, users', () async {
      final repo = StatsRepository(dio);
      final stats = await repo.fetch();
      expect(stats.totalPrints, greaterThanOrEqualTo(10));
      expect(stats.printsByFilamentType, isNotEmpty);
      expect(stats.printsByPrinter, isNotEmpty);
      final slim = await repo.fetchSlim();
      expect(slim.length, stats.totalPrints);
      final failures = await repo.fetchFailures(days: 30);
      expect(failures.failedPrints, greaterThan(0));
      expect(failures.failuresByReason, isNotEmpty);
      final users = await repo.fetchUsers();
      expect(users, hasLength(1));
    });
  });

  group('print log', () {
    final repo = PrintLogRepository(dio);

    test('the page carries the runs, the orphans among them', () async {
      final page = await repo.list();
      expect(page.items, isNotEmpty);
      expect(page.total, greaterThanOrEqualTo(page.items.length));
      // The runs whose archive is gone are the half of this table nothing else
      // in the app can reach — a demo without them misrepresents the screen.
      expect(page.items.where((e) => e.isOrphan), isNotEmpty);
      expect(page.items.first.printerName, isNotNull);
    });

    test('filters narrow it the way the server does', () async {
      final failed = await repo.list(status: 'failed');
      expect(failed.items, isNotEmpty);
      expect(failed.items.every((e) => e.status == 'failed'), isTrue);

      final searched = await repo.list(search: 'benchy');
      expect(searched.items, hasLength(1));
      expect(searched.total, 1);
    });

    test('cost and energy come through, and a plugless run stays null',
        () async {
      final page = await repo.list();
      final withPlug = page.items.firstWhere((e) => e.energyKwh != null);

      expect(withPlug.cost, isNotNull);
      expect(withPlug.energyCost, isNotNull);
      // Null, not zero: "no smart plug behind this printer" has to read
      // differently from a run that drew nothing.
      expect(page.items.any((e) => e.energyKwh == null), isTrue);
    });

    test('sorting is applied, not accepted and ignored', () async {
      final cheapest = await repo.list(
        sort: PrintLogSort.filamentUsed,
        descending: false,
      );
      final heaviest = await repo.list(sort: PrintLogSort.filamentUsed);

      final light = cheapest.items.map((e) => e.filamentUsedGrams).nonNulls;
      final heavy = heaviest.items.map((e) => e.filamentUsedGrams).nonNulls;
      expect(light.first, lessThanOrEqualTo(light.last));
      expect(heavy.first, greaterThanOrEqualTo(heavy.last));
    });

    test('paging walks the log without repeating a row', () async {
      final first = await repo.list(limit: 3, offset: 0);
      final second = await repo.list(limit: 3, offset: 3);
      expect(first.items, hasLength(3));
      expect(first.total, second.total);
      expect(
        first.items.map((e) => e.id).toSet().intersection(
              second.items.map((e) => e.id).toSet(),
            ),
        isEmpty,
      );
    });
  });

  group('smart plugs', () {
    test('list + status + control round-trip', () async {
      final repo = SmartPlugsRepository(dio);
      final plugs = await repo.fetchPlugs();
      expect(plugs, hasLength(2));
      expect(plugs.first.printerId, 1);
      final status = await repo.fetchStatus(1);
      expect(status!.isOn, isTrue);
      expect(status.powerW, greaterThan(0));
      await repo.control(1, SmartPlugAction.off);
      final off = await repo.fetchStatus(1);
      expect(off!.isOn, isFalse);
      await repo.control(1, SmartPlugAction.on);
    });
  });

  group('maintenance', () {
    test('overview, types, perform resets counters', () async {
      final repo = MaintenanceRepository(dio);
      final overview = await repo.fetchOverview();
      expect(overview, hasLength(4));
      final x1c = overview.firstWhere((o) => o.printerId == 1);
      expect(x1c.dueCount, greaterThan(0));
      final dueItem = x1c.maintenanceItems.firstWhere((i) => i.isDue);

      final types = await repo.fetchTypes();
      expect(types.length, greaterThanOrEqualTo(4));

      await repo.perform(dueItem.id);
      final after = await repo.fetchPrinter(1);
      expect(after!.maintenanceItems.firstWhere((i) => i.id == dueItem.id).isDue, isFalse);
      final history = await repo.fetchHistory(dueItem.id);
      expect(history, isNotEmpty);
    });
  });

  group('inventory (native)', () {
    final source = NativeInventorySource(dio);

    test('spools, assignments, reference data', () async {
      final spools = await source.fetchSpools();
      expect(spools.length, greaterThanOrEqualTo(7));
      expect(spools.every((s) => !s.isArchived), isTrue);
      final withArchived = await source.fetchSpools(includeArchived: true);
      expect(withArchived.length, spools.length + 1);

      final assignments = await source.fetchAssignments();
      expect(assignments, isNotEmpty);

      final usage = await source.fetchUsage(spools.first.id);
      expect(usage, isNotEmpty);

      expect(await source.fetchCoreWeights(), isNotEmpty);
      expect(await source.fetchColors(), isNotEmpty);
      expect(await source.fetchFilamentPresets(), isNotEmpty);
      expect(await source.fetchLocations(), contains('Dry box'));
    });

    test('the consumed counter is a separate number from remaining', () async {
      final spools = await source.fetchSpools();
      // One demo spool has had its counter reset before, so the two numbers
      // must not be reconstructible from each other.
      final reset = spools.firstWhere((s) => s.weightUsedBaseline > 0);
      expect(reset.consumedWeight, lessThan(reset.weightUsed));
      expect(spools.map((s) => s.consumedWeight).reduce((a, b) => a + b),
          greaterThan(0),
          reason: 'the shelf total the list header shows');

      // Resetting zeroes the counter and leaves the spool as empty as it was.
      final target = spools.firstWhere((s) => s.consumedWeight > 0);
      await source.resetUsage(target.id);
      final after = (await source.fetchSpools())
          .firstWhere((s) => s.id == target.id);
      expect(after.consumedWeight, 0);
      expect(after.remainingWeight, target.remainingWeight);
    });

    test('spool CRUD round-trip', () async {
      const draft = SpoolDraft(
        material: 'PLA',
        brand: 'Test',
        colorName: 'Cyan',
        rgba: '00FFFFFF',
        labelWeight: 1000,
      );
      final created = await source.createSpool(draft);
      expect(created.material, 'PLA');
      expect(created.rgba, '00FFFFFF');

      final updated = await source.updateSpool(
        created.id,
        const SpoolDraft(material: 'PLA', note: 'edited'),
      );
      expect(updated.note, 'edited');

      await source.archiveSpool(created.id);
      await source.restoreSpool(created.id);
      await source.resetUsage(created.id);
      await source.deleteSpool(created.id);
      final after = await source.fetchSpools(includeArchived: true);
      expect(after.any((s) => s.id == created.id), isFalse);
    });

    test('bulk operations on a selection round-trip', () async {
      // Spools of its own, deleted at the end, so the counts the first test
      // asserts stay true whatever order the group runs in.
      final ids = <int>[
        for (var i = 0; i < 3; i++)
          (await source.createSpool(
            SpoolDraft(material: 'PLA', colorName: 'Bulk $i'),
          )).id,
      ];
      const unknown = 999999;

      final updated =
          await source.bulkUpdate([...ids, unknown], const SpoolBulkPatch(
        brand: 'Bulked',
        note: 'mass edit',
      ));
      expect((updated.ok, updated.failed), (3, 1));
      expect(updated.notFound, [unknown]);
      final shelf = await source.fetchSpools(includeArchived: true);
      final touched = shelf.where((s) => ids.contains(s.id));
      expect(touched.every((s) => s.brand == 'Bulked'), isTrue);
      expect(touched.every((s) => s.note == 'mass edit'), isTrue);

      final archived = await source.bulkArchive(ids);
      expect((archived.ok, archived.skipped), (3, 0));
      // Asking twice is not a failure — the shelf already reads as intended.
      final again = await source.bulkArchive(ids);
      expect((again.ok, again.skipped, again.failed), (0, 3, 0));

      final restored = await source.bulkRestore(ids);
      expect((restored.ok, restored.skipped), (3, 0));

      final reset = await source.bulkResetUsage([...ids, unknown]);
      // The route answers with a count and nothing else, so the unknown id
      // shows up only as the gap against what was asked for.
      expect((reset.ok, reset.failed), (3, 1));

      final deleted = await source.bulkDelete(ids);
      expect((deleted.ok, deleted.failed), (3, 0));
      final after = await source.fetchSpools(includeArchived: true);
      expect(after.any((s) => ids.contains(s.id)), isFalse);
    });

    test('an empty selection and an empty edit are refused', () async {
      // Posted raw: the source short-circuits both before they leave the
      // phone, so going through it would assert the client guard and never
      // reach the refusal these routes actually answer with.
      Matcher rejects(int status) => throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', status));

      await expectLater(
        dio.post<dynamic>(
          '/api/v1/inventory/spools/bulk-archive',
          data: {'ids': <int>[]},
        ),
        rejects(400),
      );
      await expectLater(
        dio.post<dynamic>(
          '/api/v1/inventory/spools/bulk-update',
          data: {'ids': [1], 'update': <String, dynamic>{}},
        ),
        rejects(400),
      );
    });

    // Last in the group on purpose: it registers a spool and pins it to a
    // slot, and the counts asserted above are taken before that.
    test('registering an AMS slot creates the spool and pins it there',
        () async {
      // P1S slot 3 holds a tagged Bambu spool the shelf has never seen — the
      // state the affordance exists for.
      final id = await source.createSpoolFromSlot(
        printerId: 2,
        amsId: 0,
        trayId: 2,
      );
      expect(id, isNotNull);

      final spools = await source.fetchSpools();
      final created = spools.firstWhere((s) => s.id == id);
      expect(created.material, 'PLA');
      expect(created.subtype, 'Basic');
      expect(created.rgba, '00AE42FF');
      expect(normalizeTagUid(created.tagUid), 'B7A21C0439E5D168');

      final assignments = await source.fetchAssignments();
      final pinned = assignments.firstWhere((a) => a.spoolId == id);
      expect(pinned.printerId, 2);
      expect(pinned.amsId, 0);
      expect(pinned.trayId, 2);
    });

    test('a slot without a tag is refused, not silently duplicated', () async {
      // X1C slot 3 runs a third-party PETG: filament, but no identity.
      await expectLater(
        () => source.createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 2),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('an empty slot is refused too', () async {
      await expectLater(
        () => source.createSpoolFromSlot(printerId: 2, amsId: 0, trayId: 3),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)),
      );
    });
  });

  group('projects', () {
    test('list, detail, bom, timeline', () async {
      final repo = ProjectsRepository(dio);
      final list = await repo.list();
      expect(list, hasLength(2));
      expect(list.first.archives, isNotEmpty);
      final detail = await repo.get(1);
      expect(detail.stats, isNotNull);
      expect(detail.stats!.totalArchives, greaterThan(0));
      final bom = await repo.bom(1);
      expect(bom, hasLength(2));
      expect(await repo.timeline(1), isEmpty);
    });
  });

  group('library', () {
    test('files, folders, stats, trash', () async {
      final repo = LibraryRepository(dio);
      final rootFiles = await repo.listFiles();
      expect(rootFiles, hasLength(1)); // only the unfiled file at root
      final all = await repo.listAllFiles();
      expect(all.length, greaterThanOrEqualTo(6));
      final folderFiles = await repo.listFiles(folderId: 1);
      expect(folderFiles, hasLength(3));
      expect(await repo.listFolders(), hasLength(2));
      final stats = await repo.stats();
      expect(stats.totalFiles, all.length);
      expect(await repo.listTrash(), isEmpty);
    });
  });

  group('misc endpoints', () {
    test('firmware, makerworld, cloud, settings', () async {
      final fw = await FirmwareRepository(dio).fetchUpdates();
      expect(fw.updates, hasLength(3));
      expect(fw.updatesAvailable, 1);

      final mw = await MakerWorldRepository(dio).status();
      expect(mw.canDownload, isFalse);

      final cloud = await CloudRepository(dio).status();
      expect(cloud.isAuthenticated, isFalse);

      final settings = await SlicerRepository(dio).serverSettings();
      expect(settings['require_plate_clear'], isFalse);
      expect(settings['use_slicer_api'], isFalse);
    });

    test('printer files + storage + AMS history', () async {
      final files = await PrinterFilesRepository(dio).listFiles(1, '/');
      expect(files, isNotEmpty);
      expect(files.any((f) => f.isDirectory), isTrue);
      final storage = await PrinterFilesRepository(dio).fetchStorage(1);
      expect(storage.hasData, isTrue);

      final history = await AmsHistoryRepository(dio).fetch(1, 0, hours: 6);
      expect(history.points, isNotEmpty);
    });
  });

  group('websocket', () {
    test('demo connection emits parseable printer_status frames', () async {
      final conn = DemoWsConnection();
      final frames = await conn.stream.take(2).toList();
      await conn.close();
      final messages = [for (final f in frames) parseWsMessage(f as String)];
      expect(messages.whereType<WsPrinterStatus>(), hasLength(2));
      final status =
          messages.whereType<WsPrinterStatus>().first.status;
      expect(status.id, isPositive);
    });
  });

  group('AMS slot configuration', () {
    final repo = AmsSlotConfigRepository(dio);

    test('the picker has a built-in tier and imported presets', () async {
      // No cloud login in the demo, which the sheet is built to survive: the
      // other two tiers are what it falls back to.
      expect(repo.cloudFilaments(),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', AppErrorCode.unauthorized)));

      final builtin = await repo.builtinFilaments();
      expect(builtin, isNotEmpty);
      expect(builtin.map((p) => p.id), contains('GFA00'),
          reason: 'the id the demo trays report, so a slot can be named');

      final local = await repo.localFilaments();
      expect(local, isNotEmpty);
      expect(local.first.filamentType, isNotNull);
      expect(local.first.compatiblePrinters, isNotNull,
          reason: 'the printer filter needs something to filter on');
    });

    test('the printer-model registry resolves the demo printers', () async {
      final models = await repo.printerModels();
      expect(models['Bambu Lab X1 Carbon'], 'X1C');
    });

    test('K profiles come back filtered by nozzle', () async {
      final fine = await repo.kProfiles(1, nozzleDiameter: '0.4');
      expect(fine, isNotEmpty);
      expect(fine.every((p) => p.nozzleDiameter == '0.4'), isTrue);

      final coarse = await repo.kProfiles(1, nozzleDiameter: '0.6');
      expect(coarse.map((p) => p.slotId),
          isNot(anyElement(isIn(fine.map((p) => p.slotId)))));
    });

    test('configuring a slot shows on the card, and clearing it undoes that',
        () async {
      const preset = AmsFilamentPreset(
        source: AmsPresetSource.builtin,
        id: 'GFB99',
        name: 'Generic ABS',
      );
      await repo.configureSlot(
        1,
        amsId: 0,
        trayId: 3,
        configuration: SlotConfiguration.forPreset(
          preset: preset,
          colourHex: '1A1A1A',
          nozzleDiameter: '0.4',
        ),
      );
      await repo.saveSlotPreset(1, amsId: 0, trayId: 3,
          preset: preset, presetName: preset.name);

      var tray = (await PrintersRepository(dio).fetchStatus(1))!
          .ams!
          .first
          .trays!
          .firstWhere((t) => t.id == 3);
      expect(tray.trayType, 'ABS', reason: 'the empty slot now holds something');
      expect(tray.trayColor, '1A1A1AFF');
      expect(tray.trayInfoIdx, 'GFB99');
      expect((await repo.slotPreset(1, amsId: 0, trayId: 3))?.presetName,
          'Generic ABS');

      await repo.resetSlot(1, amsId: 0, trayId: 3);

      tray = (await PrintersRepository(dio).fetchStatus(1))!
          .ams!
          .first
          .trays!
          .firstWhere((t) => t.id == 3);
      expect(tray.trayType, isNull);
      expect(await repo.slotPreset(1, amsId: 0, trayId: 3), isNull,
          reason: 'the reset drops the mapping too');
    });
  });

  group('printer commands (mutate simulation — keep last)', () {
    final commands = PrinterCommandsRepository(dio);
    final printers = PrintersRepository(dio);

    test('light, speed, pause/resume, stop', () async {
      await commands.setChamberLight(1, on: false);
      await commands.setPrintSpeed(1, 3);
      var status = await printers.fetchStatus(1);
      expect(status!.chamberLight, isFalse);
      expect(status.speedLevel, 3);

      await commands.pause(1);
      status = await printers.fetchStatus(1);
      expect(status!.state, 'PAUSE');

      await commands.resume(1);
      status = await printers.fetchStatus(1);
      expect(status!.state, 'RUNNING');

      await commands.stop(1);
      status = await printers.fetchStatus(1);
      expect(status!.state, 'IDLE');
    });
  });

  group('library variant groups', () {
    final library = LibraryRepository(dio);

    test('a group across two models, then dissolved again', () async {
      final files = await library.listAllFiles();
      final x1c = files.firstWhere((f) => f.slicedForModel == 'X1C');
      final p1s = files.firstWhere((f) => f.slicedForModel == 'P1S');

      final group = await library.createVariantGroup([x1c.id, p1s.id]);
      expect(group.targetModels, ['X1C', 'P1S'],
          reason: 'selection order is the priority order');

      // The listing has to show it too, or the file rows would not know they
      // are grouped.
      final grouped = (await library.listAllFiles())
          .firstWhere((f) => f.id == x1c.id);
      expect(grouped.variantGroupId, group.id);
      expect(grouped.hasVariants, isTrue);

      expect((await library.variantGroupForFile(p1s.id))?.id, group.id);

      await library.deleteVariantGroup(group.id);
      final ungrouped = (await library.listAllFiles())
          .firstWhere((f) => f.id == x1c.id);
      expect(ungrouped.variantGroupId, isNull);
      expect(await library.variantGroupForFile(p1s.id), isNull);
    });

    test('two files sliced for the same printer are refused', () async {
      // The refusal is the point of the feature: a group is a choice between
      // printers, and two X1C files express none.
      final files = await library.listAllFiles();
      final sameModel =
          files.where((f) => f.slicedForModel == 'X1C').take(2).toList();

      await expectLater(
        library.createVariantGroup([for (final f in sameModel) f.id]),
        throwsA(isA<AppApiException>()),
      );
    });
  });

  group('print log edits (empties the fake log — keep last)', () {
    final repo = PrintLogRepository(dio);

    test('classify, refuse a value off the list, delete, clear', () async {
      final target = (await repo.list(status: 'failed')).items.first;

      final classified =
          await repo.updateEntry(target.id, failureReason: 'layerShift');
      expect(classified.failureReason, 'layerShift');

      final cleared =
          await repo.updateEntry(target.id, clearFailureReason: true);
      expect(cleared.failureReason, isNull);

      // The demo refuses what the real server refuses; an editor that looked
      // like it accepted anything would hide the 400 until a real server.
      await expectLater(
        repo.updateEntry(target.id, failureReason: 'nonsense'),
        throwsA(isA<ApiException>()),
      );

      final before = await repo.list();
      await repo.deleteEntry(target.id);
      final after = await repo.list();
      expect(after.total, before.total - 1);
      expect(after.items.map((e) => e.id), isNot(contains(target.id)));

      expect(await repo.clearAll(), after.total);
      expect((await repo.list()).items, isEmpty);
    });
  });
}
