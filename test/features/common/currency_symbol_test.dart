import 'package:bambuddy_mobile/features/common/currency_symbol.dart';
import 'package:flutter_test/flutter_test.dart';

/// The currency code comes from the server's settings, so it is input: it can
/// be absent, blank, lower-case, or a code this table has never heard of.
void main() {
  group('currencySymbol', () {
    test('known codes resolve, whatever case they arrive in', () {
      expect(currencySymbol('USD'), r'$');
      expect(currencySymbol('pln'), 'zł');
      expect(currencySymbol(' eur '), '€');
    });

    test('no code at all resolves to nothing', () {
      // Empty rather than a guessed dollar: a bare number is ambiguous, a wrong
      // symbol is wrong.
      expect(currencySymbol(null), '');
      expect(currencySymbol(''), '');
      expect(currencySymbol('   '), '');
    });

    test('an unknown code is shown as itself', () {
      expect(currencySymbol('XPF'), 'XPF');
    });
  });

  group('formatMoney', () {
    test('a glyph goes before the amount, a word after it', () {
      expect(formatMoney(r'$', '12.50'), r'$12.50');
      expect(formatMoney('€', '12.50'), '€12.50');
      expect(formatMoney('zł', '12.50'), '12.50 zł');
      expect(formatMoney('Kč', '12.50'), '12.50 Kč');
    });

    test('an unknown code lands on the alphabetic side', () {
      expect(formatMoney('XPF', '12.50'), '12.50 XPF');
    });

    test('no symbol leaves the amount alone', () {
      expect(formatMoney('', '12.50'), '12.50');
    });
  });
}
