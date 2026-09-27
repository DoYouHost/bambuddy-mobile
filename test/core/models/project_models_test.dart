import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectListResponse', () {
    test('fromJson parses summary and counts with tolerant numbers', () {
      final json = {
        'id': 1,
        'name': 'Chess Set',
        'description': '3D printed chess set',
        'color': '#FF8800',
        'status': 'active',
        'target_count': '32',
        'target_sets': 1,
        'budget': '45.50',
        'archive_count': 10,
        'total_items': '12',
        'completed_count': 8,
        'failed_count': 1,
        'queue_count': 3,
        'progress_percent': '75.5',
      };

      final proj = ProjectListResponse.fromJson(json);

      expect(proj.id, 1);
      expect(proj.name, 'Chess Set');
      expect(proj.description, '3D printed chess set');
      expect(proj.color, '#FF8800');
      expect(proj.status, 'active');
      expect(proj.targetCount, 32);
      expect(proj.targetSets, 1);
      expect(proj.budget, 45.50);
      expect(proj.archiveCount, 10);
      expect(proj.totalItems, 12);
      expect(proj.completedCount, 8);
      expect(proj.failedCount, 1);
      expect(proj.queueCount, 3);
      expect(proj.progressPercent, 75.5);
    });
  });

  group('ProjectStats', () {
    test('fromJson parses stats with defaults and tolerant conversion', () {
      final json = {
        'total_archives': '5',
        'total_items': 8,
        'completed_prints': 6,
        'failed_prints': 1,
        'queued_prints': 1,
        'total_print_time_hours': '14.5',
        'total_filament_grams': 350.0,
        'progress_percent': 75.0,
        'estimated_cost': '24.99',
      };

      final stats = ProjectStats.fromJson(json);

      expect(stats.totalArchives, 5);
      expect(stats.totalItems, 8);
      expect(stats.completedPrints, 6);
      expect(stats.failedPrints, 1);
      expect(stats.queuedPrints, 1);
      expect(stats.totalPrintTimeHours, 14.5);
      expect(stats.totalFilamentGrams, 350.0);
      expect(stats.progressPercent, 75.0);
      expect(stats.estimatedCost, 24.99);
    });
  });

  group('completeSetsFor', () {
    test('returns 0 when fileIds is empty', () {
      final sets = completeSetsFor([], [
        const ProjectFileProgress(fileId: 1, completedCount: 5),
      ]);
      expect(sets, 0);
    });

    test('returns the smallest completed count across all required files', () {
      final progress = [
        const ProjectFileProgress(fileId: 1, completedCount: 10),
        const ProjectFileProgress(fileId: 2, completedCount: 3),
        const ProjectFileProgress(fileId: 3, completedCount: 7),
      ];

      final sets = completeSetsFor([1, 2, 3], progress);
      expect(sets, 3);
    });

    test('returns 0 if any required file has not been completed yet', () {
      final progress = [
        const ProjectFileProgress(fileId: 1, completedCount: 10),
        const ProjectFileProgress(fileId: 2, completedCount: 5),
        // file 3 is missing from progress entirely
      ];

      final sets = completeSetsFor([1, 2, 3], progress);
      expect(sets, 0);
    });

    test('returns 0 if any required file has completedCount of 0', () {
      final progress = [
        const ProjectFileProgress(fileId: 1, completedCount: 10),
        const ProjectFileProgress(fileId: 2, completedCount: 0),
      ];

      final sets = completeSetsFor([1, 2], progress);
      expect(sets, 0);
    });
  });
}
