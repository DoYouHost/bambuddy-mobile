import 'dart:convert';

/// Expiry from the `exp` claim, or `null` for anything that is not a 3-part JWT
/// carrying a numeric one — the caller falls back rather than assume a token
/// format beyond the standard. Pure, so the background isolate can use it.
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
