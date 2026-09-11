import 'package:bambuddy_mobile/core/models/printer_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('printer_capabilities', () {
    group('supportsChamberHeater', () {
      test('returns true for models with active chamber heater', () {
        expect(supportsChamberHeater('H2C'), isTrue);
        expect(supportsChamberHeater('H2D'), isTrue);
        expect(supportsChamberHeater('H2DPRO'), isTrue);
        expect(supportsChamberHeater('H2S'), isTrue);
        expect(supportsChamberHeater('X2D'), isTrue);
        expect(supportsChamberHeater('N6'), isTrue);
        expect(supportsChamberHeater('O1C'), isTrue);
      });

      test('normalizes case and surrounding whitespace', () {
        expect(supportsChamberHeater('  h2d  '), isTrue);
        expect(supportsChamberHeater('h2c'), isTrue);
        expect(supportsChamberHeater('x2d'), isTrue);
      });

      test('returns false for models without active chamber heater', () {
        expect(supportsChamberHeater('X1C'), isFalse);
        expect(supportsChamberHeater('P1S'), isFalse);
        expect(supportsChamberHeater('A1'), isFalse);
        expect(supportsChamberHeater('A1_MINI'), isFalse);
        expect(supportsChamberHeater(''), isFalse);
        expect(supportsChamberHeater(null), isFalse);
      });
    });

    group('supportsAirduct', () {
      test('returns true for models with airduct flap', () {
        expect(supportsAirduct('P2S'), isTrue);
        expect(supportsAirduct('X2D'), isTrue);
        expect(supportsAirduct('H2C'), isTrue);
        expect(supportsAirduct('H2D'), isTrue);
        expect(supportsAirduct('N7'), isTrue);
        expect(supportsAirduct('N6'), isTrue);
      });

      test('normalizes case and surrounding whitespace', () {
        expect(supportsAirduct('  p2s  '), isTrue);
        expect(supportsAirduct('h2d'), isTrue);
      });

      test('returns false for models without airduct flap', () {
        expect(supportsAirduct('X1C'), isFalse);
        expect(supportsAirduct('P1S'), isFalse);
        expect(supportsAirduct('A1'), isFalse);
        expect(supportsAirduct(null), isFalse);
      });
    });
  });
}
