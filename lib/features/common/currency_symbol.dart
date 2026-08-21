/// Symbols for the currency codes bambuddy offers in its settings, taken from
/// `frontend/src/utils/currency.ts` so the two clients name a currency the same
/// way. Where the symbol goes is deliberately not copied — see [formatMoney].
///
/// An unknown code falls back to the code itself, which is what the web does
/// and is still an answer: "12.50 XPF" says more than a bare 12.50.
const _symbols = <String, String>{
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'CHF': 'Fr.',
  'JPY': '¥',
  'CNY': '¥',
  'CAD': r'$',
  'AUD': r'$',
  'INR': '₹',
  'HKD': r'HK$',
  'KRW': '₩',
  'SEK': 'kr',
  'NOK': 'kr',
  'DKK': 'kr',
  'PLN': 'zł',
  'BRL': r'R$',
  'TWD': r'NT$',
  'SGD': r'S$',
  'NZD': r'NZ$',
  'MXN': r'MX$',
  'BZD': r'BZ$',
  'MYR': 'RM',
  'CZK': 'Kč',
  'THB': '฿',
  'ZAR': 'R',
  'TRY': '₺',
  'RUB': '₽',
  'HUF': 'Ft',
  'ILS': '₪',
  'UAH': '₴',
  'IDR': 'Rp',
  'PHP': '₱',
};

/// The symbol for [code] as the server spelled it, or `''` when the server has
/// not said which currency it keeps prices in.
///
/// Empty rather than a guessed `$`: a bare number is ambiguous, a wrong symbol
/// is wrong.
String currencySymbol(String? code) {
  final key = code?.trim().toUpperCase();
  if (key == null || key.isEmpty) return '';
  return _symbols[key] ?? key;
}

/// [amount] with the server's currency symbol on the side that currency puts
/// it — `$12.50`, but `12.50 zł`.
///
/// **Deliberately unlike the web**, which renders `{symbol}{amount}` for every
/// currency and so writes `zł12.50` — a spelling no Polish price uses. This app
/// is translated and read in the locale it prices in, so it follows the
/// currency rather than the other client; the figures are identical either way.
///
/// The side is decided by the symbol's own first character rather than by a
/// second table: every symbol here that is written after the amount is
/// alphabetic (`zł`, `kr`, `Kč`, `Ft`, `RM`, `Fr.`), and every glyph one
/// (`$`, `€`, `£`, `¥`, `₹`, `₺`…) is written before it. An unknown code falls
/// out on the alphabetic side, which is where a bare code belongs anyway.
String formatMoney(String symbol, String amount) {
  if (symbol.isEmpty) return amount;
  return _startsWithLetter(symbol) ? '$amount $symbol' : '$symbol$amount';
}

bool _startsWithLetter(String value) =>
    RegExp(r'^\p{L}', unicode: true).hasMatch(value);
