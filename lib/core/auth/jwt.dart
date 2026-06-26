import 'dart:convert';

/// JWT expiry time extracted from `exp` claim (seconds since epoch, UTC).
///
/// Returns `null` if token is not a valid 3-part JWT, payload is not a map,
/// or lacks numeric `exp` — caller then uses fallback (we don't assume server
/// token format beyond standard). Pure function: no plugin dependencies,
/// works in background isolate too.
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
