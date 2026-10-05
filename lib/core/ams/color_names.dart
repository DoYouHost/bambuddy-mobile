/// Colour names as the web gives them (`frontend/src/utils/colors.ts`): the
/// server's colour catalogue first, then a family read off the hue — which is
/// what the mapping dialog writes next to every slot and filament.
library;

/// `COLOR_FAMILY_ORDER`. The names are the screen's to translate.
enum ColorFamily {
  red,
  orange,
  yellow,
  green,
  cyan,
  blue,
  purple,
  pink,
  brown,
  white,
  lightGray,
  gray,
  darkGray,
  black,
  clear,
}

/// `colorFamily`: the family a hex reads as, `RRGGBB` or `RRGGBBAA` with or
/// without `#`; null when it is no colour. Fully transparent is [clear]
/// whatever the RGB says, so Bambu's `00000000` is not black.
ColorFamily? colorFamily(String? hex) {
  if (hex == null || hex.length < 6) return null;
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 8 && clean.substring(6, 8).toLowerCase() == '00') {
    return ColorFamily.clear;
  }
  final hsl = _hexToHsl(clean);
  if (hsl == null) return null;
  final (h, s, l) = hsl;

  if (l < 0.15) return ColorFamily.black;
  if (l > 0.85) return ColorFamily.white;
  if (s < 0.15) {
    if (l < 0.4) return ColorFamily.darkGray;
    if (l > 0.6) return ColorFamily.lightGray;
    return ColorFamily.gray;
  }
  // Brown is an orange or yellow hue at low lightness.
  if (h >= 15 && h < 45 && l < 0.45) return ColorFamily.brown;
  if (h >= 45 && h < 70 && l < 0.40) return ColorFamily.brown;
  if (h < 15 || h >= 345) return ColorFamily.red;
  if (h < 45) return ColorFamily.orange;
  if (h < 70) return ColorFamily.yellow;
  if (h < 150) return ColorFamily.green;
  if (h < 200) return ColorFamily.cyan;
  if (h < 260) return ColorFamily.blue;
  if (h < 290) return ColorFamily.purple;
  return ColorFamily.pink;
}

(double, double, double)? _hexToHsl(String clean) {
  if (clean.length < 6) return null;
  final r = int.tryParse(clean.substring(0, 2), radix: 16);
  final g = int.tryParse(clean.substring(2, 4), radix: 16);
  final b = int.tryParse(clean.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) return null;

  final max = [r, g, b].reduce((a, c) => a > c ? a : c) / 255;
  final min = [r, g, b].reduce((a, c) => a < c ? a : c) / 255;
  final l = (max + min) / 2;
  var h = 0.0;
  var s = 0.0;
  if (max != min) {
    final d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    final (rn, gn, bn) = (r / 255, g / 255, b / 255);
    if (max == rn) {
      h = ((gn - bn) / d + (gn < bn ? 6 : 0)) / 6;
    } else if (max == gn) {
      h = ((bn - rn) / d + 2) / 6;
    } else {
      h = ((rn - gn) / d + 4) / 6;
    }
  }
  return (h * 360, s, l);
}

/// The server's colour catalogue (`GET /inventory/colors/map`): a name per
/// hex, and per material and hex where one hex names two colours — `#FFFFFF`
/// is Jade White in PLA Basic and Ivory White in PLA Matte (#2875).
class ColorCatalog {
  const ColorCatalog({this.byHex = const {}, this.byMaterial = const {}});

  factory ColorCatalog.fromJson(Map<String, dynamic> json) {
    final byHex = <String, String>{};
    if (json['colors'] case final Map<String, dynamic> colors) {
      for (final MapEntry(:key, :value) in colors.entries) {
        final hex = key.replaceFirst('#', '').toLowerCase();
        if (value is String && value.isNotEmpty && hex.length >= 6) {
          byHex[hex.substring(0, 6)] = value;
        }
      }
    }
    final byMaterial = <String, String>{};
    if (json['by_material'] case final Map<String, dynamic> materials) {
      for (final MapEntry(:key, :value) in materials.entries) {
        // The last separator: a material is free text and may hold a '|'.
        final cut = key.lastIndexOf('|');
        if (cut <= 0 || value is! String || value.isEmpty) continue;
        final material = key.substring(0, cut).trim().toLowerCase();
        final hex = key.substring(cut + 1).replaceFirst('#', '').toLowerCase();
        if (material.isNotEmpty && hex.length >= 6) {
          byMaterial['$material|${hex.substring(0, 6)}'] = value;
        }
      }
    }
    return ColorCatalog(byHex: byHex, byMaterial: byMaterial);
  }

  static const empty = ColorCatalog();

  final Map<String, String> byHex;
  final Map<String, String> byMaterial;

  /// `getColorName` without its fallback: the catalogue's name for [hex],
  /// by [material] when it knows that pair; null when it has none, and for a
  /// fully transparent colour, which is [ColorFamily.clear] instead.
  String? nameOf(String? hex, {String? material}) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceFirst('#', '').toLowerCase();
    if (clean.length == 8 && clean.substring(6, 8) == '00') return null;
    if (clean.length < 6) return null;
    final key = clean.substring(0, 6);
    if (material != null && material.trim().isNotEmpty) {
      final qualified = byMaterial['${material.trim().toLowerCase()}|$key'];
      if (qualified != null) return qualified;
    }
    return byHex[key];
  }
}

/// `disambiguateColorNames`: two colour labels a reader can tell apart. When
/// the names collide — a slicer's pure blue and a spool's navy are both
/// "Blue" — the hex goes on both (#2941); a side with no name shows its hex.
(String, String) disambiguateColorNames(
  ({String? name, String? hex}) first,
  ({String? name, String? hex}) second,
) {
  String hexLabel(String? hex) {
    final raw = (hex ?? '').replaceFirst('#', '').trim();
    final clean = raw
        .substring(0, raw.length < 6 ? raw.length : 6)
        .toUpperCase();
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(clean) ? '#$clean' : '';
  }

  final firstName = (first.name ?? '').trim();
  final secondName = (second.name ?? '').trim();
  final firstHex = hexLabel(first.hex);
  final secondHex = hexLabel(second.hex);

  if (firstName.isEmpty || secondName.isEmpty) {
    return (
      firstName.isEmpty ? firstHex : firstName,
      secondName.isEmpty ? secondHex : secondName,
    );
  }
  if (firstName.toLowerCase() != secondName.toLowerCase()) {
    return (firstName, secondName);
  }
  if (firstHex.isEmpty && secondHex.isEmpty) return (firstName, secondName);
  return (
    firstHex.isEmpty ? firstName : '$firstName ($firstHex)',
    secondHex.isEmpty ? secondName : '$secondName ($secondHex)',
  );
}
