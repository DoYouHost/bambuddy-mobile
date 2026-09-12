import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('smart plugs and maintenance contract', skip: contractSkipReason, () {
    late Dio dio;
    late SmartPlugsRepository plugsRepo;
    late MaintenanceRepository maintRepo;
    final createdTypeIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      plugsRepo = SmartPlugsRepository(dio);
      maintRepo = MaintenanceRepository(dio);
    });

    tearDownAll(() async {
      for (final id in createdTypeIds) {
        try {
          await maintRepo.deleteType(id);
        } catch (_) {}
      }
    });

    test('GET /smart-plugs/ decodes into List<SmartPlug>', () async {
      final plugs = await plugsRepo.fetchPlugs();
      expect(plugs, isA<List<SmartPlug>>());
      for (final p in plugs) {
        expect(p.id, greaterThan(0));
      }
    });

    test('GET /maintenance/overview decodes into List<PrinterMaintenanceOverview>', () async {
      final overview = await maintRepo.fetchOverview();
      expect(overview, isA<List<PrinterMaintenanceOverview>>());
      for (final p in overview) {
        expect(p.printerId, greaterThan(0));
        expect(p.printerName, isNotEmpty);
      }
    });

    test('GET /maintenance/types decodes into List<MaintenanceType>', () async {
      final types = await maintRepo.fetchTypes();
      expect(types, isA<List<MaintenanceType>>());
      for (final t in types) {
        expect(t.id, greaterThan(0));
        expect(t.name, isNotEmpty);
        expect(t.defaultIntervalHours, greaterThan(0));
      }
    });

    test('maintenance type lifecycle: create, update and delete', () async {
      final typeName = 'Contract-Maint-${DateTime.now().millisecondsSinceEpoch}';
      final draft = MaintenanceTypeDraft(
        name: typeName,
        description: 'Contract test maintenance task',
        defaultIntervalHours: 150,
        intervalType: 'hours',
      );

      final created = await maintRepo.createType(draft);
      createdTypeIds.add(created.id);
      expect(created.id, greaterThan(0));
      expect(created.name, typeName);
      expect(created.defaultIntervalHours, 150);

      final updateDraft = MaintenanceTypeDraft(
        name: '$typeName-renamed',
        defaultIntervalHours: 200,
      );
      await maintRepo.updateType(created.id, updateDraft);

      final typesAfterUpdate = await maintRepo.fetchTypes();
      final updated = typesAfterUpdate.firstWhere((t) => t.id == created.id);
      expect(updated.name, '$typeName-renamed');
      expect(updated.defaultIntervalHours, 200);

      await maintRepo.deleteType(created.id);
      createdTypeIds.remove(created.id);

      final currentTypes = await maintRepo.fetchTypes();
      // By name, not id: SQLite gives a deleted row's id to the next insert,
      // so the id alone may already belong to someone else's type.
      expect(currentTypes.any((t) => t.name == '$typeName-renamed'), isFalse);
    });

    test('POST /maintenance/types/restore-defaults restores system default types', () async {
      await maintRepo.restoreDefaults();
      final types = await maintRepo.fetchTypes();
      expect(types.any((t) => t.isSystem), isTrue);
    });
  });
}
