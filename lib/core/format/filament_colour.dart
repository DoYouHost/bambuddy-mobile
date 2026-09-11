/// Reading the filament a print recorded: the server's `filament_color` and
/// `filament_type`, a single token for a single-material print and a
/// comma-separated list for a multi-material one (`#AABBCC,#112233`,
/// `PLA, PETG`).
///
/// What callers want out of it differs — the archive filter compares tokens
/// verbatim, the statistics bucket by one normalized colour — which is why
/// every reading lives here instead of being re-derived per screen.
library;

/// One comma-separated server list, trimmed, with the empty pieces dropped.
///
/// Split on the comma and trim afterwards, never on `', '`: the server writes
/// the space for materials and omits it for colours, and a field that has both
/// spellings in it (`'PLA,PETG '`) comes back as one long token from the
/// two-character separator.
List<String> _commaTokens(String? raw) =>
    raw?.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList() ??
    const [];

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
List<String> filamentColourTokens(String? raw) => _commaTokens(raw);

/// The material names of a print, in the order the server listed them
/// (`PLA, PETG` -> `['PLA', 'PETG']`).
///
/// The archive collects its material chips from this and then filters rows
/// with it, so the two sides have to tokenize the same way: the collecting
/// side trimmed and the filtering side did not, which let a `'PLA, PETG '`
/// row hand out a chip that then matched nothing — not even the row it came
/// from.
List<String> filamentTypeTokens(String? raw) => _commaTokens(raw);

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
