import 'dart:ui';

import 'package:bambuddy_mobile/features/common/hex_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rgbFromHex', () {
    test('reads both the web and the inventory spelling of a colour', () {
      expect(rgbFromHex('#FF8040'), (0xFF, 0x80, 0x40));
      expect(rgbFromHex('FF8040'), (0xFF, 0x80, 0x40));
      // The inventory stores RGBA — the alpha rides along and is ignored.
      expect(rgbFromHex('FF804000'), (0xFF, 0x80, 0x40));
      expect(rgbFromHex('  #ff8040  '), (0xFF, 0x80, 0x40));
    });

    test('refuses what is not a colour', () {
      expect(rgbFromHex(null), isNull);
      expect(rgbFromHex(''), isNull);
      expect(rgbFromHex('#FFF'), isNull);
      expect(rgbFromHex('ZZZZZZ'), isNull);
    });
  });

  group('colorDistance', () {
    test('is zero for the same colour, whatever its spelling', () {
      expect(colorDistance('#FF8040', 'FF8040FF'), 0);
    });

    test('grows with the difference', () {
      expect(
        colorDistance('#000000', '#101010'),
        lessThan(colorDistance('#000000', '#FFFFFF')),
      );
    });

    test('a colour nobody knows loses to any known one', () {
      expect(colorDistance(null, '#FFFFFF'), double.maxFinite);
      expect(colorDistance('#FFFFFF', 'nonsense'), double.maxFinite);
    });
  });

  group('colorFromHex', () {
    test('paints the named colour, opaque, whatever the alpha said', () {
      expect(colorFromHex('#FF8040'), const Color(0xFFFF8040));
      // The inventory's RGBA: a fully transparent spool colour is still drawn.
      expect(colorFromHex('FF804000'), const Color(0xFFFF8040));
    });

    test('gives back null for anything that is not a colour', () {
      expect(colorFromHex(null), isNull);
      expect(colorFromHex('#GGG'), isNull);
    });
  });
}
