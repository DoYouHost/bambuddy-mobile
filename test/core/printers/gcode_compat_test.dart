import 'package:bambuddy_mobile/core/printers/gcode_compat.dart';
import 'package:flutter_test/flutter_test.dart';

// The cases of the server's `test_scheduler_model_mismatch.py` and
// `test_printer_model_codes.py`, so a drift between the two guards shows here.
void main() {
  group('same model', () {
    test('is compatible', () {
      expect(isGcodeCompatible('X1C', 'X1C'), isTrue);
      expect(isGcodeCompatible('H2D', 'H2D'), isTrue);
    });
  });

  group('the X1 / P1 family', () {
    test('is interchangeable both ways', () {
      expect(isGcodeCompatible('X1C', 'P1S'), isTrue);
      expect(isGcodeCompatible('X1C', 'P1P'), isTrue);
      expect(isGcodeCompatible('P1S', 'X1E'), isTrue);
      expect(isGcodeCompatible('X1', 'P1P'), isTrue);
      expect(isGcodeCompatible('P1P', 'X1'), isTrue);
    });
  });

  group('across families', () {
    test('is blocked', () {
      expect(isGcodeCompatible('X1C', 'H2D'), isFalse);
      expect(isGcodeCompatible('P1S', 'H2D'), isFalse);
      expect(isGcodeCompatible('H2D', 'P1S'), isFalse);
      expect(isGcodeCompatible('X1C', 'A1'), isFalse);
      expect(isGcodeCompatible('A1', 'A1 Mini'), isFalse);
      expect(isGcodeCompatible('H2D', 'H2S'), isFalse);
      expect(isGcodeCompatible('X1C', 'P2S'), isFalse);
    });

    test('a model next to a similar one is not the same model', () {
      expect(isGcodeCompatible('H2D', 'H2D Pro'), isFalse);
    });
  });

  group('unknown models', () {
    test('are compatible, on either side', () {
      expect(isGcodeCompatible(null, 'H2D'), isTrue);
      expect(isGcodeCompatible('X1C', null), isTrue);
      expect(isGcodeCompatible(null, null), isTrue);
      expect(isGcodeCompatible('', 'H2D'), isTrue);
      expect(isGcodeCompatible('X1C', ''), isTrue);
    });

    test('a blank model is unknown, not a model of its own', () {
      expect(isGcodeCompatible('   ', 'H2D'), isTrue);
      expect(isGcodeCompatible('H2D', '\t'), isTrue);
    });

    test('a model nobody listed only matches itself', () {
      expect(isGcodeCompatible('Z9', 'Z9'), isTrue);
      expect(isGcodeCompatible('Z9', 'X1C'), isFalse);
      expect(isGcodeCompatible('X1C', 'Z9'), isFalse);
    });
  });

  group('normalisation', () {
    test('ignores case, spaces and hyphens', () {
      expect(isGcodeCompatible('x1c', 'X1C'), isTrue);
      expect(isGcodeCompatible('A1 Mini', 'A1-MINI'), isTrue);
      expect(isGcodeCompatible('H2D Pro', 'H2DPRO'), isTrue);
    });

    test('ignores whitespace around the name', () {
      expect(isGcodeCompatible('P1S ', ' P1S'), isTrue);
      expect(isGcodeCompatible(' C12 ', 'P1S'), isTrue);
    });
  });

  group('internal codes', () {
    test('resolve to their short names', () {
      expect(isGcodeCompatible('BL-P001', 'X1C'), isTrue);
      expect(isGcodeCompatible('C11', 'P1P'), isTrue);
      expect(isGcodeCompatible('N7', 'P2S'), isTrue);
      expect(isGcodeCompatible('O1D', 'H2D'), isTrue);
      expect(isGcodeCompatible('O1C2', 'H2C'), isTrue);
    });

    test('keep their family', () {
      expect(isGcodeCompatible('C11', 'X1C'), isTrue);
      expect(isGcodeCompatible('BL-P001', 'P1S'), isTrue);
      expect(isGcodeCompatible('C11', 'H2D'), isFalse);
      expect(isGcodeCompatible('BL-P001', 'H2D'), isFalse);
    });

    test('are looked up before the hyphen is stripped', () {
      // "BL-P001" is a key of the table; "BLP001" is nothing.
      expect(isGcodeCompatible('BL-P001', 'X1C'), isTrue);
      expect(isGcodeCompatible('BLP001', 'X1C'), isFalse);
    });

    test('a printer that reports a code takes a file with the short name', () {
      expect(isGcodeCompatible('P2S', 'N7'), isTrue);
      expect(isGcodeCompatible('H2D', 'O1D'), isTrue);
      expect(isGcodeCompatible('H2D', 'C12'), isFalse);
    });
  });

  group('3MF display names', () {
    test('resolve to their short names', () {
      expect(isGcodeCompatible('Bambu Lab X1 Carbon', 'X1C'), isTrue);
      expect(isGcodeCompatible('Bambu Lab A1 mini', 'A1 Mini'), isTrue);
      expect(isGcodeCompatible('Bambu Lab H2D', 'O1D'), isTrue);
    });

    test('keep their family', () {
      expect(isGcodeCompatible('Bambu Lab X1 Carbon', 'P1S'), isTrue);
      expect(isGcodeCompatible('Bambu Lab P1S', 'H2D'), isFalse);
    });
  });

  group('nonsense input', () {
    test('does not throw and is not compatible with a real model', () {
      expect(isGcodeCompatible('???', 'X1C'), isFalse);
      expect(isGcodeCompatible('X1C', '---'), isFalse);
      expect(isGcodeCompatible('\u{1F5A8}', 'P1S'), isFalse);
    });
  });
}
