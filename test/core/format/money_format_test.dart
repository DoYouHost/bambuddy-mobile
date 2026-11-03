import 'package:bambuddy_mobile/core/format/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoneyValue', () {
    test('puts a glyph symbol before two decimals', () {
      expect(formatMoneyValue(r'$', 2.5), r'$2.50');
      expect(formatMoneyValue(r'$', 1234.5), r'$1234.50');
    });

    test('puts a symbol that is written after the amount after it', () {
      expect(formatMoneyValue('zł', 2.5), '2.50 zł');
    });

    test('zero keeps both decimals', () {
      expect(formatMoneyValue(r'$', 0), r'$0.00');
    });

    test('an empty symbol gives the bare amount', () {
      expect(formatMoneyValue('', 2.5), '2.50');
    });

    test('a negative amount keeps the sign after the symbol', () {
      expect(formatMoneyValue(r'$', -1.5), r'$-1.50');
    });

    test('rounds on the exact binary value, not the decimal it looks like', () {
      expect(formatMoneyValue(r'$', 1.005), r'$1.00');
      expect(formatMoneyValue(r'$', 2.675), r'$2.67');
    });
  });
}
