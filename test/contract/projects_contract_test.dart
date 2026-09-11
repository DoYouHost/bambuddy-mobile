import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('projects contract', skip: contractSkipReason, () {
    late Dio dio;
    late ProjectsRepository repo;
    final createdProjectIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = ProjectsRepository(dio);
    });

    tearDownAll(() async {
      for (final id in createdProjectIds) {
        try {
          await repo.delete(id);
        } catch (_) {}
      }
    });

    test('GET /projects/ and /projects/templates decode into ProjectListResponse', () async {
      final projects = await repo.list();
      expect(projects, isA<List<ProjectListResponse>>());
      for (final p in projects) {
        expect(p.id, greaterThan(0));
        expect(p.name, isNotEmpty);
      }

      final templates = await repo.listTemplates();
      expect(templates, isA<List<ProjectListResponse>>());
    });

    test('project lifecycle: create, get, update, sub-resources and delete', () async {
      final name = 'contract-proj-${DateTime.now().millisecondsSinceEpoch}';
      final createBody = ProjectCreate(
        name: name,
        description: 'Contract test project',
        priority: 'high',
        targetCount: 5,
      );

      final created = await repo.create(createBody);
      createdProjectIds.add(created.id);
      expect(created.id, greaterThan(0));
      expect(created.name, name);
      expect(created.description, 'Contract test project');

      // GET detail
      final detail = await repo.get(created.id);
      expect(detail.id, created.id);
      expect(detail.name, name);
      expect(detail.stats, isNotNull);

      // PATCH update
      final updatedName = '$name-updated';
      final updated = await repo.update(
        created.id,
        ProjectUpdate(name: updatedName, description: 'Updated desc'),
      );
      expect(updated.id, created.id);
      expect(updated.name, updatedName);

      // Sub-resources
      final bom = await repo.bom(created.id);
      expect(bom, isA<List<BomItem>>());

      // Add a BOM item
      final bomInput = BomItemInput(
        name: 'M3x10 Screw',
        quantityNeeded: 10,
        unitPrice: 0.15,
      );
      await repo.addBomItem(created.id, bomInput);
      final updatedBom = await repo.bom(created.id);
      expect(updatedBom.any((b) => b.name == 'M3x10 Screw'), isTrue);

      final timeline = await repo.timeline(created.id);
      expect(timeline, isA<List<TimelineEvent>>());

      final folders = await repo.linkedFolders(created.id);
      expect(folders, isA<List<dynamic>>());

      final files = await repo.files(created.id);
      expect(files, isA<List<dynamic>>());

      // DELETE
      await repo.delete(created.id);
      createdProjectIds.remove(created.id);

      final remaining = await repo.list();
      expect(remaining.any((p) => p.id == created.id), isFalse);
    });
  });
}
