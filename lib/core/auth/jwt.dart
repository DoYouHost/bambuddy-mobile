import 'dart:convert';

/// Czas wygaśnięcia JWT odczytany z claimu `exp` (sekundy od epoki, UTC).
///
/// Zwraca `null`, gdy token nie jest poprawnym trójczłonowym JWT, payload nie
/// jest mapą albo brak w nim liczbowego `exp` — wołający stosuje wtedy fallback
/// (nie zakładamy formatu tokenu serwera ponad standard). Czysta funkcja: bez
/// zależności od pluginów, działa też w isolacie tła.
DateTime? jwtExpiry(String? token) {
  if (token == null || token.isEmpty) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final exp = decoded['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
  } on Object {
    return null;
  }
}
