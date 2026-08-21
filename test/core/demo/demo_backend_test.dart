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
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
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
      expect(await version.supportsTriStateCalibration(), isTrue);
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
}
