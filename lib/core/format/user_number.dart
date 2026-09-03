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
/// "1.234,5" are the same number and both read as 1234.5. A space is grouping
/// too, so "1 234,5" is settled the same way.
///
/// What is left is genuinely ambiguous and is **refused**: a lone comma with
/// exactly three digits after it and nothing else to go on. "1,000" is one
/// thousand to an English writer and one to a Polish one, and these fields
/// carry values where both readings are plausible — a 1000 g spool, a
/// four-figure cost. There is no locale to ask here, and of the two ways to be
/// wrong, refusing shows the user a field they can correct while guessing
/// stores a number nobody typed. Any other comma is a decimal point.
///
/// Blank or null text answers null as well. Every field here means the same
/// thing by an empty box — "unset" — and each already decides for itself
/// whether that is a value or a mistake, so telling the two apart is the
/// caller's business and not this function's.
double? parseUserDecimal(String? text) {
  if (text == null) return null;
  final raw = text.trim();
  // A space inside the number is the user's own grouping mark, which settles
  // what any comma left in it must be.
  final spaceGrouped = RegExp(r'\s').hasMatch(raw);
  // Dart's `\s` covers the non-breaking space.
  var cleaned = raw.replaceAll(RegExp(r'\s'), '');
  if (cleaned.contains('.') && cleaned.contains(',')) {
    cleaned = cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')
        ? cleaned.replaceAll('.', '')
        : cleaned.replaceAll(',', '');
  } else if (!spaceGrouped && RegExp(r'\d,\d{3}$').hasMatch(cleaned)) {
    return null;
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
/// A decimal is not one, so it answers null — the refusal `int.tryParse` gave,
/// with the separators sorted out first. Where a whole number is what the field
/// means, silently rounding what the user typed is picking a different value
/// for them; the empty field they get back says something is wrong with it.
int? parseUserInt(String? text) {
  final value = parseUserDecimal(text);
  return value == null || value != value.roundToDouble()
      ? null
      : _wholeNumber(value);
}

/// [parseUserInt] for a field whose own validator lets a decimal through.
///
/// The spool form's weights: every numeric field there is checked as a decimal,
/// so "1000.5" is accepted on screen and refusing it here would drop a value
/// the user typed and watched pass. Only for a field validated that way — see
/// [parseUserInt] for why it is not the default.
int? parseUserRoundedInt(String? text) {
  final value = parseUserDecimal(text);
  return value == null ? null : _wholeNumber(value);
}

/// Null past 2^53, where a double no longer holds consecutive integers and
/// rounding one means nothing. `round()` saturates at the platform's largest
/// int rather than failing, so without this the field would send that number on
/// as if somebody had typed it.
int? _wholeNumber(double value) =>
    value.abs() > 9007199254740992.0 ? null : value.round();
