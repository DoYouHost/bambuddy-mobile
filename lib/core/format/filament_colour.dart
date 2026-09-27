/// Reading the filament a print recorded: the server's `filament_color` and
/// `filament_type`, a single token for a single-material print and a
/// comma-separated list for a multi-material one (`#AABBCC,#112233`,
/// `PLA, PETG`).
library;

/// Split on the comma and trim afterwards, never on `', '`: the server writes
/// the space for materials and omits it for colours, so a field with both
/// spellings comes back as one long token from the two-character separator.
List<String> _commaTokens(String? raw) =>
    raw?.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList() ??
    const [];

/// Hoisted out of [sixHexDigits]: the statistics call it once per archived
/// run, and a `RegExp(...)` in the body recompiles the pattern every time.
final _sixHexDigits = RegExp(r'^[0-9A-F]{6}$');

/// Six upper-case hex digits from any spelling a colour arrives in (`#RRGGBB`,
/// `RRGGBB`, `RRGGBBAA`), or null when it is not a colour. The alpha is dropped
/// so the catalogue's `#RRGGBB` and the printer's `RRGGBBAA` compare equal.
String? sixHexDigits(String? raw) {
  final hex = raw?.trim().replaceFirst('#', '');
  if (hex == null || hex.length < 6) return null;
  final rgb = hex.substring(0, 6).toUpperCase();
  return _sixHexDigits.hasMatch(rgb) ? rgb : null;
}

/// Verbatim, a leading `#` included: the archive filter compares these against
/// values it collected from the same field, so normalizing here would make a
/// chosen swatch stop matching the rows it came from.
List<String> filamentColourTokens(String? raw) => _commaTokens(raw);

List<String> filamentTypeTokens(String? raw) => _commaTokens(raw);

/// The first token as `#RRGGBB`, or null when the field is empty or holds
/// something that is not a colour — statistics group by this string, and
/// reading six characters off the front unchecked made `unknown` a colour.
String? primaryFilamentColour(String? raw) {
  final hex = sixHexDigits(filamentColourTokens(raw).firstOrNull);
  return hex == null ? null : '#$hex';
}
