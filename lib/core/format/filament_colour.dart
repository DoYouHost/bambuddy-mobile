/// Reading the colour a print recorded: the server's `filament_color`, a hex
/// token for a single-material print and a comma-separated list for a
/// multi-material one (`#AABBCC,#112233`).
///
/// What callers want out of it differs — the archive filter compares tokens
/// verbatim, the statistics bucket by one normalized colour — which is why
/// both readings live here instead of being re-derived per screen.
library;

/// Hoisted out of [sixHexDigits]: the statistics call it once per archived
/// run, and a `RegExp(...)` in the body recompiles the pattern every time.
final _sixHexDigits = RegExp(r'^[0-9A-F]{6}$');

/// Six upper-case hex digits from any of the spellings a colour arrives in
/// (`#RRGGBB`, `RRGGBB`, `RRGGBBAA`), or null when it is not a colour at all.
///
/// The alpha is dropped rather than kept: the catalogue writes `#RRGGBB` and
/// the printer writes `RRGGBBAA`, and the two have to compare equal — while a
/// slot's `00` alpha means *empty*, which must never become a picked colour.
String? sixHexDigits(String? raw) {
  final hex = raw?.trim().replaceFirst('#', '');
  if (hex == null || hex.length < 6) return null;
  final rgb = hex.substring(0, 6).toUpperCase();
  return _sixHexDigits.hasMatch(rgb) ? rgb : null;
}

/// The colour tokens of a print, in the order the server listed them, kept
/// exactly as they came — a leading `#` included.
///
/// Verbatim on purpose: the archive colour filter compares these against the
/// values it collected from the same field, so normalizing here would make a
/// chosen swatch stop matching the rows it was collected from.
List<String> filamentColourTokens(String? raw) =>
    raw?.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList() ??
    const [];

/// The one colour that stands for a print — the first token, normalized to
/// `#RRGGBB` — or null when the field is empty or holds something that is not
/// a colour.
///
/// Statistics group by this string, so a value that is not a colour has to
/// drop out rather than become a bucket: reading six characters off the front
/// without checking them turned `unknown` into the colour `#UNKNOW`.
String? primaryFilamentColour(String? raw) {
  final hex = sixHexDigits(filamentColourTokens(raw).firstOrNull);
  return hex == null ? null : '#$hex';
}
