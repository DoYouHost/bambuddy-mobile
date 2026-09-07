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
      expect(
        parseUserDecimal('1 234'),
        1234.0,
        reason: 'the non-breaking space a formatted number groups with',
      );
    });

    // Both conventions write the same number, and a paste is how either gets
    // into a field. The rightmost separator is the decimal mark in both.
    test('two separators are a grouped number, whichever way round', () {
      expect(parseUserDecimal('1,234.5'), 1234.5);
      expect(parseUserDecimal('1.234,5'), 1234.5);
      expect(parseUserDecimal('1 234 567,25'), 1234567.25);
    });

    // The case that cannot be got right without a locale, and where both
    // readings are plausible in these fields: "1,000" is a thousand to an
    // English writer and one to a Polish one, and a 1000 g spool and a
    // four-figure cost are both ordinary. Refused rather than guessed — the
    // user sees a field to correct instead of a number nobody typed.
    test('a lone comma over exactly three digits is refused, not guessed', () {
      expect(parseUserDecimal('1,000'), isNull);
      expect(parseUserDecimal('1,234'), isNull);
      expect(parseUserDecimal('12,345'), isNull);
    });

    // Only that shape is ambiguous. Anything else the comma can only be a
    // decimal point in.
    test('every other comma is a decimal point', () {
      expect(parseUserDecimal('1,23'), 1.23);
      expect(parseUserDecimal('1,2345'), 1.2345);
      expect(parseUserDecimal(',5'), 0.5);
      // The space already said which mark groups, so the comma is the other.
      expect(parseUserDecimal('1 234,567'), 1234.567);
    });

    // Nothing is grouped below a thousand, so a leading zero settles it — and
    // half a gram is exactly what these fields are for.
    test('a number under one is never a grouped thousand', () {
      expect(parseUserDecimal('0,500'), 0.5);
      expect(parseUserDecimal('0,125'), 0.125);
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
    test('a whole number is itself, separators and all', () {
      expect(parseUserInt('1000'), 1000);
      expect(parseUserInt('1 000'), 1000);
    });

    // Where the field means a whole number, rounding what the user typed is
    // choosing a different value for them without saying so.
    test('a decimal is refused, the way int.tryParse refused it', () {
      expect(parseUserInt('2.5'), isNull);
      expect(parseUserInt('40,6'), isNull);
    });

    test('an empty field is still nothing', () {
      expect(parseUserInt(''), isNull);
      expect(parseUserInt(null), isNull);
    });
  });

  group('parseUserRoundedInt', () {
    // For the spool form, where every numeric field is validated as a decimal:
    // "1000.5" is accepted on screen, so refusing it on the way out drops a
    // value the user typed and watched pass.
    test('a decimal is rounded rather than dropped', () {
      expect(parseUserRoundedInt('1000.5'), 1001);
      expect(parseUserRoundedInt('1000,4'), 1000);
    });

    // `round()` saturates at the largest platform int rather than failing, so
    // without the guard the field would quietly send 9223372036854775807.
    test('a number too large to be a whole one is refused', () {
      expect(parseUserRoundedInt('1e20'), isNull);
      expect(parseUserRoundedInt('99999999999999999999'), isNull);
      expect(parseUserInt('1e20'), isNull);
    });
  });
}
