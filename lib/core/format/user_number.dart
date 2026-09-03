/// A number the way a person types it, or null when there is no number in it.
///
/// `double.tryParse` is the wire parser: it takes exactly what JSON writes. A
/// text field is the other direction, and two things a user does routinely make
/// that parser answer null —
///
/// - **the comma.** It is the decimal separator in Polish, and the key the
///   phone's own numeric layout offers there. A field parsed with
///   `double.tryParse` refuses what the keyboard produced and says nothing the
///   user can act on: the value simply never arrives.
/// - **spaces**, the non-breaking one included, which is how a locale-formatted
///   number groups its thousands and what comes back when one is pasted in.
///
/// Where both separators appear the rightmost one is the decimal mark and the
/// other groups digits, which is true of both conventions — "1,234.5" and
/// "1.234,5" are the same number and both read as 1234.5. A **lone** comma is
/// read as a decimal point — "1,234" is one and a bit, not a thousand. There is
/// no locale to ask here, and of the app's two languages only one groups
/// thousands that way, while the other writes every decimal that way.
///
/// Blank or null text answers null as well. Every field here means the same
/// thing by an empty box — "unset" — and each already decides for itself
/// whether that is a value or a mistake, so telling the two apart is the
/// caller's business and not this function's.
double? parseUserDecimal(String? text) {
  if (text == null) return null;
  // Dart's `\s` covers the non-breaking space.
  var cleaned = text.replaceAll(RegExp(r'\s'), '');
  if (cleaned.contains('.') && cleaned.contains(',')) {
    cleaned = cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')
        ? cleaned.replaceAll('.', '')
        : cleaned.replaceAll(',', '');
  }
  cleaned = cleaned.replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  // `Infinity` and `NaN` parse — they are what a paste, or a hardware keyboard
  // on a field whose only guard is a numeric soft layout, can put in.
  return value == null || !value.isFinite ? null : value;
}

/// [parseUserDecimal] for a field that stores a whole number.
///
/// Rounds rather than refusing a decimal: "1000.5" passes a numeric field's own
/// validation, so `int.tryParse` answering null there drops a value the user
/// typed and watched be accepted. The rule comes from the spool form, where
/// what went missing was a spool's label weight.
int? parseUserInt(String? text) {
  final value = parseUserDecimal(text);
  if (value == null) return null;
  // Past 2^53 a double no longer holds consecutive integers, so rounding one
  // means nothing — and `round()` saturates at the platform's largest int
  // instead of failing, which would send that absurd number to the server.
  return value.abs() > 9007199254740992.0 ? null : value.round();
}
