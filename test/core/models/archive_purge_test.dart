import 'package:bambuddy_mobile/core/models/archive_purge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchivePurgePreview', () {
    test('fromJson parses count, size, olderThanDays and sample filenames', () {
      final json = {
        'count': 15,
        'total_bytes': 104857600,
        'sample_filenames': ['benchy_1.3mf', 'stand.3mf'],
        'older_than_days': 30,
      };

      final preview = ArchivePurgePreview.fromJson(json);

      expect(preview.count, 15);
      expect(preview.totalBytes, 104857600);
      expect(preview.sampleFilenames, ['benchy_1.3mf', 'stand.3mf']);
      expect(preview.olderThanDays, 30);
      expect(preview.isEmpty, isFalse);
    });

    test('fromJson accepts tolerant numeric formats (doubles and strings)', () {
      final json = {
        'count': 5.0,
        'total_bytes': '2048',
        'sample_filenames': null,
        'older_than_days': '14',
      };

      final preview = ArchivePurgePreview.fromJson(json);

      expect(preview.count, 5);
      expect(preview.totalBytes, 2048);
      expect(preview.sampleFilenames, isEmpty);
      expect(preview.olderThanDays, 14);
      expect(preview.isEmpty, isFalse);
    });

    test('isEmpty is true when count is 0', () {
      const empty = ArchivePurgePreview(count: 0, totalBytes: 0);
      expect(empty.isEmpty, isTrue);
    });
  });
}
