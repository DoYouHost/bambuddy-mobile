import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/process_option.dart';
import 'package:bambuddy_mobile/core/models/swatch_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// A field the server sends as something other than text reads as missing
/// rather than failing the whole record; blank reads as missing too.
void main() {
  group('Spool material', () {
    String material(Object? value) =>
        Spool.fromNative({'id': 1, 'material': value}).material;

    test('text is read, trimmed', () => expect(material(' PLA '), 'PLA'));
    test('missing, blank or not text is Unknown', () {
      expect(material(null), 'Unknown');
      expect(material('  '), 'Unknown');
      expect(material(42), 'Unknown');
    });
  });

  group('SwatchCode material', () {
    String material(Object? value) =>
        SwatchCode.fromJson({'code': 'A1', 'material': value}).material;

    test('text is read, trimmed', () => expect(material(' PETG '), 'PETG'));
    test('missing, blank or not text is Unknown', () {
      expect(material(null), 'Unknown');
      expect(material(''), 'Unknown');
      expect(material(true), 'Unknown');
    });
  });

  group('ProcessOption label', () {
    String? label(Object? value) => ProcessOption.tryFromJson('wall_loops', {
      'type': 'coInt',
      'label': value,
    })?.label;

    test('text is read', () => expect(label('Wall loops'), 'Wall loops'));
    test('missing, blank or not text falls back to the key', () {
      expect(label(null), 'wall_loops');
      expect(label(' '), 'wall_loops');
      expect(label(3), 'wall_loops');
    });
  });
}
