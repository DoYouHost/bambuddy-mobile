/// The leading `RRGGBB` of a hex colour, with or without a `#` and with or
/// without the trailing alpha the inventory writes (`RRGGBBAA`).
(int, int, int)? rgbFromHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length < 6) return null;
  final v = int.tryParse(h.substring(0, 6), radix: 16);
  if (v == null) return null;
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

/// Squared RGB distance between two hex colours — big when either is missing,
/// so a known colour always beats an unknown one when picking the closest
/// spool for a print.
double colorDistance(String? a, String? b) {
  final ca = rgbFromHex(a), cb = rgbFromHex(b);
  if (ca == null || cb == null) return double.maxFinite;
  final dr = ca.$1 - cb.$1, dg = ca.$2 - cb.$2, db = ca.$3 - cb.$3;
  return (dr * dr + dg * dg + db * db).toDouble();
}
