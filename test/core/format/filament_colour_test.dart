import 'package:bambuddy_mobile/core/format/filament_colour.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sixHexDigits', () {
    test('reads every spelling a colour arrives in', () {
      expect(sixHexDigits('#aabbcc'), 'AABBCC');
      expect(sixHexDigits('aabbcc'), 'AABBCC');
      expect(sixHexDigits('  #AaBbCc  '), 'AABBCC');
    });

    test('drops the alpha the printer appends', () {
      expect(sixHexDigits('AABBCCFF'), 'AABBCC');
      expect(sixHexDigits('AABBCC00'), 'AABBCC');
    });

    test('refuses what is not a colour', () {
      expect(sixHexDigits(null), isNull);
      expect(sixHexDigits(''), isNull);
      expect(sixHexDigits('#ABC'), isNull);
      expect(sixHexDigits('unknown'), isNull);
      expect(sixHexDigits('#GGHHII'), isNull);
    });
  });

  group('filamentColourTokens', () {
    test('a single-material print is one token', () {
      expect(filamentColourTokens('#AABBCC'), ['#AABBCC']);
    });

    test('a multi-material print keeps every token, in order', () {
      expect(filamentColourTokens('#AABBCC,#112233'), ['#AABBCC', '#112233']);
    });

    test('tokens stay verbatim, so the archive filter keeps matching', () {
      // Neither the `#` nor the case is touched: the swatch the filter compares
      // against was collected from this same field.
      expect(filamentColourTokens('aabbcc, #ddeeff'), ['aabbcc', '#ddeeff']);
    });

    test('nothing recorded is an empty list, not a token', () {
      expect(filamentColourTokens(null), isEmpty);
      expect(filamentColourTokens(''), isEmpty);
      expect(filamentColourTokens(' , '), isEmpty);
    });
  });

  group('filamentTypeTokens', () {
    test('a multi-material list splits however the server spelled it', () {
      expect(filamentTypeTokens('PLA, PETG'), ['PLA', 'PETG']);
      expect(filamentTypeTokens('PLA,PETG'), ['PLA', 'PETG']);
      expect(filamentTypeTokens('PLA, PETG '), ['PLA', 'PETG']);
    });

    test('a single material is one token', () {
      expect(filamentTypeTokens('PETG'), ['PETG']);
    });

    test('nothing recorded is an empty list, not a token', () {
      expect(filamentTypeTokens(null), isEmpty);
      expect(filamentTypeTokens(''), isEmpty);
      expect(filamentTypeTokens(' , '), isEmpty);
    });
  });

  group('primaryFilamentColour', () {
    test('the first token stands for the print, normalized', () {
      expect(primaryFilamentColour('#aabbcc,#112233'), '#AABBCC');
      expect(primaryFilamentColour('aabbccff'), '#AABBCC');
    });

    test('a value that is not a colour drops out instead of becoming one', () {
      // Reading six characters off the front without checking them turned
      // `unknown` into the colour `#UNKNOW` and gave the statistics a bucket
      // that no filament was ever printed in.
      expect(primaryFilamentColour('unknown'), isNull);
      expect(primaryFilamentColour('#ABC'), isNull);
      expect(primaryFilamentColour(null), isNull);
      expect(primaryFilamentColour(''), isNull);
    });
  });
}
