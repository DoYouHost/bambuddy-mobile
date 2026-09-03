import 'package:bambuddy_mobile/core/format/user_number.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a number out of a text field. The comma is the case this exists for:
/// it is the decimal key on a Polish keyboard, `double.tryParse` refuses it,
/// and a field that refuses it drops the value with nothing on screen to
/// explain why.
void main() {
  group('parseUserDecimal', () {
    test('an ordinary number is itself', () {
      expect(parseUserDecimal('42'), 42.0);
      expect(parseUserDecimal('12.5'), 12.5);
      expect(parseUserDecimal('0'), 0.0);
      expect(parseUserDecimal('-3.5'), -3.5);
    });

    test('a comma is a decimal point', () {
      expect(parseUserDecimal('12,5'), 12.5);
      expect(parseUserDecimal('0,25'), 0.25);
    });

    test('spaces around and inside the number are not part of it', () {
      expect(parseUserDecimal('  42  '), 42.0);
      expect(parseUserDecimal('1 234,5'), 1234.5);
      expect(parseUserDecimal('1 234'), 1234.0,
          reason: 'the non-breaking space a formatted number groups with');
    });

    // Both conventions write the same number, and a paste is how either gets
    // into a field. The rightmost separator is the decimal mark in both.
    test('two separators are a grouped number, whichever way round', () {
      expect(parseUserDecimal('1,234.5'), 1234.5);
      expect(parseUserDecimal('1.234,5'), 1234.5);
      expect(parseUserDecimal('1 234 567,25'), 1234567.25);
    });

    // Deliberate, and the one case that cannot be got right without a locale:
    // a lone comma is the decimal key of the language the app is used in.
    test('a lone comma is a decimal point, not a thousands mark', () {
      expect(parseUserDecimal('1,234'), 1.234);
    });

    test('an empty field is not a number', () {
      expect(parseUserDecimal(''), isNull);
      expect(parseUserDecimal('   '), isNull);
      expect(parseUserDecimal(null), isNull);
    });

    test('what is not a number answers null', () {
      for (final text in ['abc', '.', '-', '1,2,3', '1.2.3', '4-5']) {
        expect(parseUserDecimal(text), isNull, reason: '"$text"');
      }
    });

    // Both parse in Dart, and a paste or a hardware keyboard is all it takes to
    // get one into a field whose only guard is a numeric soft layout.
    test('infinity and NaN are not numbers a field can mean', () {
      expect(parseUserDecimal('Infinity'), isNull);
      expect(parseUserDecimal('-Infinity'), isNull);
      expect(parseUserDecimal('NaN'), isNull);
    });
  });

  group('parseUserInt', () {
    test('a whole number is itself', () {
      expect(parseUserInt('1000'), 1000);
      expect(parseUserInt('1 000'), 1000);
    });

    // The reason it is not `int.tryParse`: a numeric field's own validator
    // accepts "1000.5", so refusing it here loses a value the user was told
    // was fine.
    test('a decimal is rounded, not refused', () {
      expect(parseUserInt('1000.5'), 1001);
      expect(parseUserInt('1000,4'), 1000);
    });

    test('an empty field is still nothing', () {
      expect(parseUserInt(''), isNull);
      expect(parseUserInt(null), isNull);
    });

    // `round()` saturates at the largest platform int rather than failing, so
    // without this the field would quietly send 9223372036854775807.
    test('a number too large to be a whole one is refused', () {
      expect(parseUserInt('1e20'), isNull);
      expect(parseUserInt('99999999999999999999'), isNull);
    });
  });
}
