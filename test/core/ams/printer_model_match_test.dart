import 'package:bambuddy_mobile/core/ams/printer_model_match.dart';
import 'package:flutter_test/flutter_test.dart';

/// A slice of the registry `GET /slicer/printer-models` answers with.
const _models = <String, String>{
  'Bambu Lab X1 Carbon': 'X1C',
  'Bambu Lab X1': 'X1',
  'Bambu Lab P1S': 'P1S',
  'Bambu Lab A1': 'A1',
  'Bambu Lab A1 Mini': 'A1 Mini',
  'Bambu Lab A1 mini': 'A1 Mini',
  'Bambu Lab H2D': 'H2D',
};

void main() {
  group('presetPrinterModel', () {
    test('reads the short code out of a @BBL suffix', () {
      expect(presetPrinterModel('Bambu PLA Basic @BBL X1C', _models), 'X1C');
      expect(
        presetPrinterModel('Bambu PLA Basic @BBL X1C 0.4 nozzle', _models),
        'X1C',
      );
    });

    test('resolves the long form through the registry', () {
      expect(
        presetPrinterModel('SUNLU TPU 95A @Bambu Lab X1 Carbon 0.4 nozzle',
            _models),
        'X1C',
      );
    });

    test('keeps a long form the registry does not know', () {
      // Better to carry the model as written than to call the preset
      // unclassified: it still matches a printer named the same way.
      expect(
        presetPrinterModel('My PLA @Bambu Lab Q9 0.4 nozzle', _models),
        'Q9',
      );
    });

    test('finds a model written at the front, with no suffix at all', () {
      // The shape behind bambuddy #1623.
      expect(presetPrinterModel('X1C eSUN PETG-Basic Filament', _models), 'X1C');
    });

    test('does not let a short model eat a longer one', () {
      // "A1 Mini" contains "A1"; scanning shortest-first would file every A1
      // Mini profile under the A1.
      expect(presetPrinterModel('A1 Mini eSUN PLA', _models), 'A1 Mini');
    });

    test('ignores a model token that is only part of a word', () {
      expect(presetPrinterModel('Generic PA1 Blend', _models), isNull);
    });

    test('answers null when the name says nothing about a printer', () {
      expect(presetPrinterModel('Generic PLA', _models), isNull);
    });
  });

  group('matchesPrinterModel', () {
    test('matches case-insensitively', () {
      expect(matchesPrinterModel('x1c', 'X1C'), isTrue);
    });

    test('knows the A1M rename of the A1 Mini', () {
      // bambuddy #1649: the cloud started shipping "A1M" while user presets
      // kept "A1 Mini", so both name the same printer.
      expect(matchesPrinterModel('A1M', 'A1 Mini'), isTrue);
      expect(matchesPrinterModel('A1 Mini', 'A1M'), isTrue);
    });

    test('keeps genuinely different printers apart', () {
      expect(matchesPrinterModel('A1', 'A1 Mini'), isFalse);
      expect(matchesPrinterModel('X1', 'X1C'), isFalse);
    });
  });

  group('fullPrinterPresetName', () {
    test('builds the name an imported preset lists as compatible', () {
      expect(
        fullPrinterPresetName('X1C', _models, '0.4'),
        'Bambu Lab X1 Carbon 0.4 nozzle',
      );
    });

    test('answers null for a model the registry does not carry', () {
      expect(fullPrinterPresetName('Q9', _models, '0.4'), isNull);
    });
  });

  group('normalisePrinterPresetName', () {
    test('ignores the slicer clone prefix, case and spacing', () {
      // A preset cloned from a printer must not read as incompatible with that
      // same printer.
      expect(
        normalisePrinterPresetName('#  Bambu Lab  X1 Carbon 0.4 nozzle'),
        normalisePrinterPresetName('bambu lab x1 carbon 0.4 nozzle'),
      );
    });
  });
}
