import 'dart:io';

import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/demo/demo_http_adapter.dart';
import 'package:bambuddy_mobile/core/demo/demo_ws.dart';
import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/core/models/archive_media.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/cloud_repository.dart';
import 'package:bambuddy_mobile/data/firmware_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/core/models/location_sensor.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/location_sensors_repository.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_presets.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
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
      // Five, not four: the second X1C exists so a pipeline can target the X1C
      // *class* and have more than one candidate — see `_statusSecondX1c`.
      expect(all, hasLength(5));
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

    test('plates: one demo print is multi-plate, the rest are not', () async {
      final repo = ArchiveRepository(dio);
      final list = await repo.list();
      final multi = list.where((a) => a.plateId != null).toList();
      final single = list.where((a) => a.plateId == null).first;

      expect(multi, hasLength(1),
          reason: 'the demo needs one, to have a plate picker to show');
      final plates = await repo.plates(multi.single.id);
      expect(plates.isMultiPlate, isTrue);
      expect(plates.plates.map((p) => p.index), [1, 2, 3]);
      expect(plates.byIndex(multi.single.plateId), isNotNull,
          reason: 'the plate the print ran on has to be one of the choices');

      expect((await repo.plates(single.id)).isMultiPlate, isFalse);
    });

    test('printer media: the three outcomes the sheet has to render', () async {
      final repo = ArchiveRepository(dio);
      final printed =
          (await repo.list()).where((a) => a.printerId != null).toList();
      final media = [
        for (final a in printed) (await repo.printerMedia(a.id))!,
      ];

      // Nothing the demo server keeps: a viewer row would open onto
      // `http://demo`, which resolves nowhere.
      expect(media.every((m) => m.localTimelapse == null), isTrue);

      // All three faces of the printer section, so browsing the archive list
      // shows each of them rather than the same answer every time.
      expect(
        media.where((m) => m.remoteFiles.isEmpty && m.warnings.isEmpty),
        isNotEmpty,
        reason: 'a print whose card has been cleared since',
      );
      expect(
        media.where((m) =>
            m.remoteFiles.any((f) => f.kind == ArchiveMediaKind.ipcam)),
        isNotEmpty,
        reason: 'a print with the camera chunks still there',
      );
      expect(
        media.where(
            (m) => m.warnings.contains(ArchiveMediaWarning.ipcamUnavailable)),
        isNotEmpty,
        reason: 'a printer with camera recording turned off',
      );

      expect(
        media.expand((m) => m.remoteFiles).every((f) => f.size > 0),
        isTrue,
        reason: 'sizes are all-or-nothing on the way to the download job',
      );
    });

    test('a video the sheet offers is the one the file manager lists',
        () async {
      // The two views are generated from the same prints, so a file named in
      // one has to be findable in the other — otherwise the demo teaches a
      // relationship the real server does not have.
      final archives = ArchiveRepository(dio);
      final files = PrinterFilesRepository(dio);
      final print = (await archives.list())
          .firstWhere((a) => a.printerId != null && a.id % 3 == 1);
      final offered = (await archives.printerMedia(print.id))!.remoteFiles;
      expect(offered, isNotEmpty);

      for (final file in offered) {
        final dir = file.path.substring(0, file.path.lastIndexOf('/'));
        final listed = await files.listFiles(print.printerId!, dir);
        final match =
            listed.files.where((f) => f.path == file.path).singleOrNull;
        expect(match, isNotNull, reason: '${file.path} is not in $dir');
        expect(match!.size, file.size);
      }
    });

    test('no-3mf nudge: the demo has nothing to complain about', () async {
      // Unrouted in the demo backend, which answers 404 — the same answer an
      // older server gives, and the same "no banner" for both.
      expect((await ArchiveRepository(dio).no3mfWarning()).hasFallback, isFalse);
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

  group('slicer pipelines', () {
    test('two bundles, one targeted at a class and one not yet', () async {
      final list = await PipelinesRepository(dio).list();

      expect(list, hasLength(2));
      final targeted = list.firstWhere((p) => p.name == 'Gridfinity PETG');
      expect(targeted.targetKind, PipelineTargetKind.printerClass);
      expect(targeted.targetModelClass, 'X1C');
      expect(targeted.isRunnable, isTrue);

      // What every bundle saved from the slice form looks like — the create
      // schema carries no target — and the only way to reach the amber
      // "set a target" line and the edit screen behind it.
      final fresh = list.firstWhere((p) => p.name == 'Nightly ASA brackets');
      expect(fresh.isRunnable, isFalse);
    });

    test('the stored preset refs resolve against /slicer/presets', () async {
      // The same catalogue the slice form's pickers read, or every row of the card would
      // read "No longer in the catalog".
      final presets = await SlicerRepository(dio).presets();
      final pipeline = (await PipelinesRepository(dio).list()).first;

      for (final ref in [
        pipeline.printerPreset,
        pipeline.processPreset,
        ...pipeline.filamentPresets,
      ]) {
        final slot = ref == pipeline.printerPreset
            ? PresetSlot.printer
            : ref == pipeline.processPreset
                ? PresetSlot.process
                : PresetSlot.filament;
        expect(isUnresolved(resolvePresetRef(presets, ref, slot)), isFalse,
            reason: '${ref.source}/${ref.id} is missing from the catalogue');
      }
    });

    test('a class pre-flight reports every candidate, and why each fails',
        () async {
      // The reason the fleet carries two X1Cs. Printer 1 holds PETG and
      // printer 5 holds PLA only, so the mismatch is computed off the fixture
      // rather than fabricated.
      final report = await PipelinesRepository(dio)
          .checkEligibility(1, source: const PipelineSource.libraryFile(6));

      expect(report.ok, isTrue, reason: 'one candidate passing is enough');
      expect(report.printerReports, hasLength(2));
      expect(report.eligibleCount, 1);
      expect(report.issues, isEmpty,
          reason: 'on the class path every problem belongs to a printer');

      final bad = report.printerReports.firstWhere((r) => !r.ok);
      expect(bad.printerName, 'X1 Carbon #2');
      expect(bad.issues.single.kind,
          EligibilityIssueKind.filamentTypeMismatch);
      expect(bad.issues.single.expected, 'PETG');
      expect(bad.issues.single.actual, 'PLA');
    });

    test('an untargeted pipeline is refused before it can spend anything',
        () async {
      final report = await PipelinesRepository(dio)
          .checkEligibility(2, source: const PipelineSource.libraryFile(6));

      expect(report.ok, isFalse);
      expect(report.issues.single.kind, EligibilityIssueKind.classNotSet);
    });

    test('running it unforced is refused with the report itself', () async {
      // The 409 whose body *is* the pre-flight, which is what lets one widget
      // render both answers.
      await expectLater(
        PipelinesRepository(dio)
            .run(2, source: const PipelineSource.libraryFile(6)),
        throwsA(isA<PipelineNotEligible>()),
      );
    });

    test('a forced run dispatches, and records that it was forced', () async {
      final run = await PipelinesRepository(dio)
          .run(2, source: const PipelineSource.libraryFile(6), force: true);

      expect(run.status, PipelineRunStatus.dispatching);
      expect(run.eligibilityOverridden, isTrue);
      expect(run.jobs, hasLength(1));
    });

    test('copies spread over the class per the fanout strategy', () async {
      final run = await PipelinesRepository(dio)
          .run(1, source: const PipelineSource.libraryFile(6), copies: 3);

      expect(run.copies, 3);
      // `max_parallel` pins nothing: the scheduler hands each copy to whichever
      // matching printer frees up first, so no copy carries a printer yet.
      expect(run.jobs.every((j) => j.assignedPrinterName == null), isTrue);
    });

    test('the copies ceiling comes from the server, not a built-in', () async {
      final settings = await SlicerRepository(dio).serverSettings();

      expect(settings['pipeline_max_copies'], 12,
          reason: 'deliberately not the server default of 50');
    });
  });

  group('pipeline runs', () {
    test('the list pages, and says how many the filter matched', () async {
      final repo = PipelinesRepository(dio);
      final first = await repo.runs();

      expect(first.runs, hasLength(25), reason: 'one page');
      expect(first.total, greaterThan(25), reason: 'so "load more" appears');

      final second = await repo.runs(offset: 25);
      expect(second.runs, isNotEmpty);
      expect(
        {...first.runs.map((r) => r.id)}
            .intersection({...second.runs.map((r) => r.id)}),
        isEmpty,
        reason: 'the second page does not repeat the first',
      );
    });

    test('every state the card renders differently is present', () async {
      final runs = (await PipelinesRepository(dio).runs()).runs;
      final byStatus = {for (final r in runs) r.status};

      expect(byStatus, containsAll([
        PipelineRunStatus.inProgress,
        PipelineRunStatus.partialFailure,
        PipelineRunStatus.failed,
        PipelineRunStatus.completed,
      ]));
    });

    test('a run whose source was deleted offers no retry', () async {
      // `ondelete="SET NULL"` empties both source columns while the run stays,
      // and `retry-failed` then answers 400 — so the button has to be absent.
      // Selected by the state, not by a null name: this file's backend is one
      // shared instance, so the runs the tests above dispatched are in the list
      // too and a looser finder would pick one of those.
      final runs = (await PipelinesRepository(dio).runs()).runs;
      final orphan = runs.firstWhere(
          (r) => r.hasRetryableCopies && r.sourceLibraryFileId == null);

      expect(orphan.hasRetryableCopies, isTrue,
          reason: 'it did fail — this is not the "nothing to retry" case');
      expect(orphan.canRetry, isFalse);
      await expectLater(
        PipelinesRepository(dio).retryFailed(orphan.id),
        throwsA(isA<AppApiException>()),
        reason: 'and the server agrees, with a 400',
      );
    });

    test('retry-failed opens a new run linked to the one it re-attempts',
        () async {
      final repo = PipelinesRepository(dio);
      final parent = (await repo.runs())
          .runs
          .firstWhere((r) => r.canRetry && r.copiesFailed == 1);

      final retry = await repo.retryFailed(parent.id);

      expect(retry.id, isNot(parent.id));
      expect(retry.parentRunId, parent.id);
      expect(retry.copies, 1, reason: 'one copy failed, one is re-attempted');
    });

    test('cancelling is idempotent, and stops the copies not yet sent',
        () async {
      final repo = PipelinesRepository(dio);
      final live = (await repo.runs())
          .runs
          .firstWhere((r) => r.status == PipelineRunStatus.inProgress);

      final cancelled = await repo.cancel(live.id);
      expect(cancelled.status, PipelineRunStatus.cancelled);

      // Pressed twice: a terminal run comes back untouched rather than refused.
      final again = await repo.cancel(live.id);
      expect(again.status, PipelineRunStatus.cancelled);
    });

    test('clearing drops the finished runs and keeps the live ones', () async {
      final repo = PipelinesRepository(dio);
      final before = await repo.runs();
      final live = before.runs
          .where((r) => !r.status.isTerminal)
          .map((r) => r.id)
          .toSet();

      final deleted = await repo.clearTerminalRuns();
      expect(deleted, greaterThan(0));

      final after = await repo.runs();
      expect(after.runs.every((r) => !r.status.isTerminal), isTrue);
      expect(after.runs.map((r) => r.id).toSet(), live);
    });
  });

  group('maintenance', () {
    test('overview, types, perform resets counters', () async {
      final repo = MaintenanceRepository(dio);
      final overview = await repo.fetchOverview();
      expect(overview, hasLength(5), reason: 'one row per printer in the fleet');
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
      final locations = await source.fetchLocations();
      expect(locations.map((l) => l.name), contains('Dry box'));
      // The id is what the location's sensors are keyed by, so a catalog row
      // that arrives without one takes the storage-conditions pills with it.
      expect(locations.every((l) => l.id > 0), isTrue);
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

  group('storage-location sensors', () {
    test('bindings and readings parse, with all three pill states', () async {
      final repo = LocationSensorsRepository(dio, ServerVersionService(dio));
      expect(await repo.supportsLocationSensors(), isTrue);

      final bindings = await repo.listBindings();
      expect(bindings, hasLength(3));
      // All on "Dry box", the one demo location the reading is about.
      expect(bindings.every((b) => b.locationId == 3), isTrue);
      expect(bindings.every((b) => b.showOnCard), isTrue);

      final readings = await repo.readings(3);
      expect(
        readings.map((r) => r.category),
        [
          LocationSensorCategory.temperature,
          LocationSensorCategory.humidity,
          LocationSensorCategory.battery,
        ],
      );
      expect(readings.map((r) => r.formattedValue), ['24.4°C', '47.2%', '78%']);
      // The three states the pills draw differently: plain, over threshold,
      // and last-known because the poller could not reach it.
      expect(readings.map((r) => r.alerting), [false, true, false]);
      expect(readings.map((r) => r.reachable), [true, true, false]);

      // A location nobody measures answers with nothing, not a 404.
      expect(await repo.readings(1), isEmpty);
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
      // The four un-sliced sources; every sliced output sits in a folder.
      expect(rootFiles, hasLength(4));
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
      expect(settings['use_slicer_api'], isTrue,
          reason: 'the flag that gates every Slice button in the app');
    });

    test('printer files + storage + AMS history', () async {
      final listing = await PrinterFilesRepository(dio).listFiles(1, '/');
      expect(listing.files, isNotEmpty);
      expect(listing.files.any((f) => f.isDirectory), isTrue);
      expect(listing.printerUnavailable, isFalse);
      final storage = await PrinterFilesRepository(dio).fetchStorage(1);
      expect(storage.hasData, isTrue);

      // Downloading is served, not faked with a fallback: a single file comes
      // back as bytes, capped at 2 MB so a demo download stays a download rather
      // than a memory test, and the bundle as a ZIP a tool can open.
      final dir = Directory.systemTemp.createTempSync('demo-printer-files');
      addTearDown(() => dir.deleteSync(recursive: true));
      final one = '${dir.path}/one.3mf';
      await PrinterFilesRepository(dio)
          .downloadFileTo(1, '/cache/Benchy.gcode.3mf', one);
      // The listing claims 2 108 509 bytes for this one; the cap is what lands.
      expect(File(one).lengthSync(), 2 * 1024 * 1024);

      final small = '${dir.path}/small.3mf';
      await PrinterFilesRepository(dio)
          .downloadFileTo(1, '/cache/Cable clips x8.gcode.3mf', small);
      expect(File(small).lengthSync(), 1524736);

      final zip = '${dir.path}/bundle.zip';
      await PrinterFilesRepository(dio).downloadZipTo(
        1,
        const ['/cache/Benchy.gcode.3mf', '/cache/Cable clips x8.gcode.3mf'],
        zip,
      );
      // The 22 bytes of an empty archive, starting with the ZIP signature.
      expect(File(zip).readAsBytesSync().take(4), [0x50, 0x4B, 0x05, 0x06]);

      final history = await AmsHistoryRepository(dio).fetch(1, 0, hours: 6);
      expect(history.points, isNotEmpty);
    });

    test('a download the server prepares first runs end to end', () async {
      final repo = PrinterFilesRepository(dio);
      final paths = const [
        '/cache/Benchy.gcode.3mf',
        '/cache/Cable clips x8.gcode.3mf',
      ];

      final started = await repo.startDownloadJob(
        1,
        paths: paths,
        sizes: const {},
        filename: 'X1-files.zip',
      );
      expect(started, isNotNull);
      expect(started!.state, PrinterDownloadJobState.preparing);
      expect(started.requested, 2);

      // Polling is the demo's clock: one file is staged per poll, so the
      // counter on screen moves and the bundle is ready on the second.
      final half = await repo.downloadJob(1, started.jobId);
      expect(half!.successful, 1);
      expect(half.state, PrinterDownloadJobState.preparing);
      final ready = await repo.downloadJob(1, started.jobId);
      expect(ready!.state, PrinterDownloadJobState.ready);
      expect(ready.token, isNotNull);

      final dir = Directory.systemTemp.createTempSync('demo-prepared');
      addTearDown(() => dir.deleteSync(recursive: true));
      final zip = '${dir.path}/bundle.zip';
      await repo.downloadPreparedTo(
        1,
        token: ready.token!,
        filename: ready.filename ?? 'X1-files.zip',
        savePath: zip,
      );
      expect(File(zip).readAsBytesSync().take(4), [0x50, 0x4B, 0x05, 0x06]);

      // Single-use, as on the real server: the token is spent and the job is
      // gone with it.
      await expectLater(
        repo.downloadPreparedTo(
          1,
          token: ready.token!,
          filename: 'X1-files.zip',
          savePath: '${dir.path}/again.zip',
        ),
        throwsA(isA<AppApiException>()),
      );
      expect(await repo.downloadJob(1, started.jobId), isNull);
    });

    test('a prepared download can be called off', () async {
      final repo = PrinterFilesRepository(dio);
      final started = await repo.startDownloadJob(
        1,
        paths: const ['/cache/Benchy.gcode.3mf'],
        sizes: const {},
        filename: 'Benchy.gcode.3mf',
        asZip: false,
      );

      await repo.cancelDownloadJob(1, started!.jobId);

      expect(await repo.downloadJob(1, started.jobId), isNull);
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

  group('server-side slicing (files the slice in — keep last)', () {
    late SlicerRepository slicer;
    setUp(() => slicer = SlicerRepository(dio));

    // Ids from the fixture: the plain un-sliced 3MF, the two-tone one, the
    // STL and the CAD export no slicer can load.
    const plain = 6, twoTone = 7, stl = 8, step = 9;

    Future<Map<String, dynamic>> slice(int fileId, {String process = 'q-020-std'}) =>
        Future.value({
          'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
          'process_preset': {'source': 'local', 'id': process},
          'filament_preset': {'source': 'local', 'id': 'f-petg-white'},
        });

    test('a 3MF names the presets it was designed with; an STL names none',
        () async {
      final designed =
          await LibraryRepository(dio).plates(plain).then((p) => p.embedded);
      expect(designed.isAvailable, isTrue);
      expect(designed.matchesPrinter('X1C 0.4 nozzle'), isTrue,
          reason: 'spelled as /slicer/presets spells it, or the switch never '
              'appears');

      final none =
          await LibraryRepository(dio).plates(stl).then((p) => p.embedded);
      expect(none.isAvailable, isFalse);
      expect(none.serverSupportsAsDesigned, isFalse,
          reason: 'no design_overrides key at all on a non-3MF');
    });

    test('full_slots offers every project slot, flagging the spare ones',
        () async {
      final slots = await slicer.filamentRequirements(
          id: twoTone, isArchive: false, plateId: 1);
      expect(slots, hasLength(4));
      expect(anyUnused(slots), isTrue,
          reason: 'the form can only mark spare slots when some are spare');
      expect(slots.where((s) => s.usedInPlate).map((s) => s.slotId), [1, 2]);
    });

    test('which slots are spare depends on the plate asked about', () async {
      final second = await slicer.filamentRequirements(
          id: twoTone, isArchive: false, plateId: 2);
      expect(second.where((s) => s.usedInPlate).map((s) => s.slotId), [3, 4]);
    });

    test('a source with no filament table falls back to one generic slot',
        () async {
      expect(
        await slicer.filamentRequirements(id: stl, isArchive: false),
        isEmpty,
      );
    });

    test('a local process preset resolves; the standard tier says why not',
        () async {
      final local = await slicer.presetValues(
          const SlicerPreset(source: 'local', id: 'q-028-draft', name: ''));
      expect(local?.resolved, isTrue);
      expect(local?.values['layer_height'], '0.28',
          reason: 'a string, as a process JSON spells it — a number would read '
              'as user-modified the moment the panel opened');

      final standard = await slicer.presetValues(const SlicerPreset(
          source: 'standard', id: '0.20mm Standard @BBL X1C', name: ''));
      expect(standard?.resolved, isFalse);
      expect(standard?.cause, PresetValuesCause.sidecarOutdated);
    });

    test('STEP is refused before anything is read, in its own words', () async {
      await expectLater(
        slicer.sliceLibraryFile(step, await slice(step)),
        throwsA(isA<AppApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.detail, 'detail', contains('STEP'))),
        reason: 'the detail has to survive the repository, or the sentence the '
            'server wrote is replaced by "error 400"',
      );
    });

    test('only the archive that kept its source can be re-sliced', () async {
      final archives = await ArchiveRepository(dio).list();
      final benchy = archives.firstWhere((a) => a.printName == 'Benchy');
      final other = archives.firstWhere((a) => a.printName != 'Benchy');
      expect((await slicer.archiveCapabilities(benchy.id)).sliceable, isTrue);
      expect((await slicer.archiveCapabilities(other.id)).sliceable, isFalse);
    });

    test('a job runs through its stages and then stops moving', () async {
      DemoBackend.sliceSeconds = 1;
      addTearDown(() => DemoBackend.sliceSeconds = 9);

      final jobId = await slicer.sliceLibraryFile(plain, await slice(plain));
      expect((await slicer.job(jobId)).status, 'pending',
          reason: 'the sidecar publishes nothing for the first moment, which '
              'is what puts the dialog on an indeterminate bar');

      await Future<void>.delayed(const Duration(milliseconds: 1300));
      final done = await slicer.job(jobId);
      expect(done.isCompleted, isTrue);
      expect(done.result?.libraryFileId, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      final again = await slicer.job(jobId);
      expect(again.result?.libraryFileId, done.result!.libraryFileId,
          reason: 'the output is filed once, not once per poll');
    });

    test('a running job reports a stage and a percentage', () async {
      DemoBackend.sliceSeconds = 4;
      addTearDown(() => DemoBackend.sliceSeconds = 9);

      final jobId = await slicer.sliceLibraryFile(twoTone, await slice(twoTone));
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final running = await slicer.job(jobId);
      expect(running.status, 'running');
      expect(running.progress?.stage, isNotEmpty);
      expect(running.progress?.fraction, inExclusiveRange(0, 1));
    });

    test('the output lands in the library beside its source', () async {
      DemoBackend.sliceSeconds = 1;
      addTearDown(() => DemoBackend.sliceSeconds = 9);
      final library = LibraryRepository(dio);
      final before = (await library.listAllFiles()).length;

      final jobId = await slicer.sliceLibraryFile(twoTone, await slice(twoTone));
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      final result = (await slicer.job(jobId)).result!;

      final after = await library.listAllFiles();
      expect(after, hasLength(before + 1));
      final output = after.firstWhere((f) => f.id == result.libraryFileId);
      expect(output.filename, result.name);
      expect(output.isPrintable, isTrue,
          reason: 'the whole point of slicing it');
      expect(output.slicedForModel, 'X1C',
          reason: 'the printer that was picked, not the source it came from');
    });

    test('a re-sliced archive keeps the source estimate and the picked printer',
        () async {
      DemoBackend.sliceSeconds = 1;
      addTearDown(() => DemoBackend.sliceSeconds = 9);
      final archives = ArchiveRepository(dio);
      final benchy = (await archives.list())
          .firstWhere((a) => a.printName == 'Benchy');

      final jobId = await slicer.sliceArchive(benchy.id, {
        'printer_preset': {'source': 'local', 'id': 'p-p1s-04'},
        'process_preset': {'source': 'local', 'id': 'q-020-std'},
        'filament_preset': {'source': 'local', 'id': 'f-petg-white'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      final result = (await slicer.job(jobId)).result!;

      expect(result.printTimeSeconds, benchy.printTimeSeconds,
          reason: 'same layer height as the source, so the same estimate — an '
              'archive knows what it costs and need not be guessed at');
      final resliced = (await archives.list())
          .firstWhere((a) => a.printName == 'Benchy (re-sliced)');
      expect(resliced.slicedForModel, 'P1S');
      expect(resliced.completedAt, isNull,
          reason: 'sliced, never printed');
      expect(resliced.runCount, 0);
    });
  });
}
