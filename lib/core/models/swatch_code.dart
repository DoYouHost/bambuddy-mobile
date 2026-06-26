/// "Swatch" codes — 6-character identifiers for filament SAMPLE (not specific spool).
/// Describe filament definition: brand + type + variant + color
/// (e.g. "Bambu PLA Basic Red"), without weight, location, or usage history.
///
/// Local data (no server endpoint) — stored in SharedPreferences as JSON,
/// exportable/importable as file. Codes are case-insensitive and avoid ambiguous
/// chars (0/O, 1/I/L) for easy transcription from physical sample label.
library;

import 'dart:math';

/// Code alphabet: digits 2–9 and letters A–Z WITHOUT ambiguous chars
/// (`0`, `1`, `I`, `L`, `O`). 31 chars → 31^6 ≈ 887M combinations.
const String swatchCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Swatch code length.
const int swatchCodeLength = 6;

/// Generate random 6-character code from [swatchCodeAlphabet].
String generateSwatchCode([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      swatchCodeLength,
      (_) => swatchCodeAlphabet.codeUnitAt(r.nextInt(swatchCodeAlphabet.length)),
    ),
  );
}

/// Normalize user-entered code for comparison: uppercase, no spaces.
/// (Ambiguous chars don't appear in codes, so we don't map O→0 etc. —
/// typing them just means no match.)
String normalizeSwatchCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

/// Whether [code] (after normalization) is valid: exactly [swatchCodeLength]
/// chars, all from [swatchCodeAlphabet]. For manual edit validation.
bool isValidSwatchCode(String code) {
  final c = normalizeSwatchCode(code);
  if (c.length != swatchCodeLength) return false;
  for (final unit in c.codeUnits) {
    if (!swatchCodeAlphabet.contains(String.fromCharCode(unit))) return false;
  }
  return true;
}

/// Filament definition identity key — used for dedup and code-to-inventory
/// spool matching. Composed from brand, material, variant, color
/// (normalized: trim + lowercase). Empty = "—".
String filamentIdentityKey({
  String? brand,
  required String material,
  String? variant,
  String? colorName,
}) {
  String n(String? s) => (s ?? '').trim().toLowerCase();
  return [n(brand), n(material), n(variant), n(colorName)].join('|');
}

/// Readable filament definition name: "Brand Material Variant — Color".
String filamentIdentityName({
  String? brand,
  required String material,
  String? variant,
  String? colorName,
}) {
  final head = [
    if (brand != null && brand.trim().isNotEmpty) brand.trim(),
    material.trim(),
    if (variant != null && variant.trim().isNotEmpty) variant.trim(),
  ].join(' ');
  final color = colorName?.trim();
  return (color != null && color.isNotEmpty) ? '$head — $color' : head;
}

/// Filament definition with assigned swatch code.
class SwatchCode {
  const SwatchCode({
    required this.code,
    required this.material,
    this.brand,
    this.variant,
    this.colorName,
    this.rgba,
    this.createdAt,
  });

  factory SwatchCode.fromJson(Map<String, dynamic> json) => SwatchCode(
        code: normalizeSwatchCode((json['code'] as String?) ?? ''),
        material: ((json['material'] as String?)?.trim().isNotEmpty == true)
            ? (json['material'] as String).trim()
            : 'Unknown',
        brand: _str(json['brand']),
        variant: _str(json['variant']),
        colorName: _str(json['color_name']),
        rgba: _str(json['rgba']),
        createdAt: _str(json['created_at']),
      );

  final String code;
  final String material;
  final String? brand;
  final String? variant;
  final String? colorName;
  final String? rgba;
  final String? createdAt;

  /// Filament identity key (for matching to inventory spools).
  String get identityKey => filamentIdentityKey(
        brand: brand,
        material: material,
        variant: variant,
        colorName: colorName,
      );

  String get displayName => filamentIdentityName(
        brand: brand,
        material: material,
        variant: variant,
        colorName: colorName,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'material': material,
        if (brand != null) 'brand': brand,
        if (variant != null) 'variant': variant,
        if (colorName != null) 'color_name': colorName,
        if (rgba != null) 'rgba': rgba,
        if (createdAt != null) 'created_at': createdAt,
      };

  static String? _str(dynamic v) {
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    return null;
  }
}

/// Light filament identity extracted from inventory (no specific spool) — for
/// "filamenty without code" list. Key/name consistent with [SwatchCode].
class FilamentIdentity {
  const FilamentIdentity({
    required this.material,
    this.brand,
    this.variant,
    this.colorName,
    this.rgba,
  });

  final String material;
  final String? brand;
  final String? variant;
  final String? colorName;
  final String? rgba;

  String get key => filamentIdentityKey(
        brand: brand,
        material: material,
        variant: variant,
        colorName: colorName,
      );

  String get displayName => filamentIdentityName(
        brand: brand,
        material: material,
        variant: variant,
        colorName: colorName,
      );
}
