import 'package:bambuddy_mobile/core/models/archive_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchiveCapabilities', () {
    test('fromJson parses flags correctly', () {
      final json = {
        'has_model': true,
        'has_gcode': true,
        'has_source': false,
      };

      final caps = ArchiveCapabilities.fromJson(json);

      expect(caps.hasModel, isTrue);
      expect(caps.hasGcode, isTrue);
      expect(caps.hasSource, isFalse);
      expect(caps.sliceable, isTrue);
    });

    test('sliceable is true when hasSource is true even if hasModel is false', () {
      const caps = ArchiveCapabilities(hasSource: true, hasModel: false);
      expect(caps.sliceable, isTrue);
    });

    test('sliceable is false when neither hasSource nor hasModel is true', () {
      const caps = ArchiveCapabilities(hasGcode: true);
      expect(caps.sliceable, isFalse);
    });

    test('fromJson defaults missing flags to false', () {
      final caps = ArchiveCapabilities.fromJson(const {});

      expect(caps.hasModel, isFalse);
      expect(caps.hasGcode, isFalse);
      expect(caps.hasSource, isFalse);
      expect(caps.sliceable, isFalse);
    });
  });
}
