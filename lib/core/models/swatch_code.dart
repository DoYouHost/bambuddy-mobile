/// Kody „swatch" — 6-znakowe identyfikatory PRÓBKI filamentu (nie konkretnej
/// szpuli). Opisują definicję filamentu: producent + typ + wariant + kolor
/// (np. „Bambu PLA Basic Red"), bez wagi, lokalizacji czy historii zużycia.
///
/// Dane lokalne (nie ma endpointu serwerowego) — trzymane w SharedPreferences
/// jako JSON i eksportowalne/importowalne plikiem. Kody są wielkością liter
/// nieczułe i unikają znaków dwuznacznych (0/O, 1/I/L), by łatwo je przepisać
/// z naklejki na fizycznej próbce.
library;

import 'dart:math';

/// Alfabet kodów: cyfry 2–9 i litery A–Z BEZ znaków dwuznacznych
/// (`0`, `1`, `I`, `L`, `O`). 31 znaków → 31^6 ≈ 887 mln kombinacji.
const String swatchCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Długość kodu swatch.
const int swatchCodeLength = 6;

/// Generuje losowy 6-znakowy kod z [swatchCodeAlphabet].
String generateSwatchCode([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      swatchCodeLength,
      (_) => swatchCodeAlphabet.codeUnitAt(r.nextInt(swatchCodeAlphabet.length)),
    ),
  );
}

/// Normalizuje kod wpisany przez użytkownika do porównania: wielkie litery,
/// bez spacji. (Znaki dwuznaczne i tak nie występują w kodach, więc nie
/// mapujemy O→0 itp. — wpisanie ich to po prostu brak trafienia.)
String normalizeSwatchCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

/// Czy [code] (po normalizacji) jest poprawny: dokładnie [swatchCodeLength]
/// znaków, wszystkie z [swatchCodeAlphabet]. Do walidacji ręcznej edycji.
bool isValidSwatchCode(String code) {
  final c = normalizeSwatchCode(code);
  if (c.length != swatchCodeLength) return false;
  for (final unit in c.codeUnits) {
    if (!swatchCodeAlphabet.contains(String.fromCharCode(unit))) return false;
  }
  return true;
}

/// Klucz tożsamości definicji filamentu — używany do dedup i dopasowania kodu
/// do szpul z magazynu. Składany z producenta, materiału, wariantu i koloru
/// (znormalizowane: trim + lowercase). Pusta wartość = „—".
String filamentIdentityKey({
  String? brand,
  required String material,
  String? variant,
  String? colorName,
}) {
  String n(String? s) => (s ?? '').trim().toLowerCase();
  return [n(brand), n(material), n(variant), n(colorName)].join('|');
}

/// Czytelna nazwa definicji filamentu: „Marka Materiał Wariant — Kolor".
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

/// Definicja filamentu z przypisanym kodem swatch.
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

  /// Klucz tożsamości filamentu (do dopasowania do szpul z magazynu).
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

/// Lekka tożsamość filamentu wyłuskana z magazynu (bez konkretnej szpuli) —
/// do listy „filamenty bez kodu". Klucz/nazwa spójne ze [SwatchCode].
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
