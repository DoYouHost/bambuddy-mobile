/// Server URL + API key decoded from a bambuddy configuration QR code.
class ScannedApiKeyConfig {
  const ScannedApiKeyConfig({this.baseUrl, required this.apiKey});

  /// Server origin carried by the combined `bambuddy://config` QR; null when the
  /// code held only a key.
  final String? baseUrl;

  /// The scanned API key.
  final String apiKey;
}

/// Decodes a bambuddy configuration QR code into a [ScannedApiKeyConfig].
///
/// The payload contract is `reference/.../apiKeyQr.ts`:
///
///   `bambuddy://config?v=1&url=<encoded baseUrl>&key=<encoded apiKey>`
///
/// The `v` is ignored, so a bumped payload still carrying `url`/`key` keeps
/// working, and hand-made codes are read leniently: a query param
/// (`key`/`api_key`/`token`), then a `bb_…` token anywhere in the text, then the
/// whole value if it is one whitespace-free token.
///
/// Null when nothing key-shaped can be read. The caller drops the result into
/// editable fields, so a loose match is still correctable.
ScannedApiKeyConfig? parseScannedApiKey(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  final uri = Uri.tryParse(s);
  if (uri != null && uri.hasQuery) {
    final key = _firstParam(uri, const [
      'key',
      'api_key',
      'apikey',
      'apiKey',
      'token',
    ]);
    if (key != null) {
      return ScannedApiKeyConfig(
        baseUrl: _firstParam(uri, const ['url', 'base_url', 'baseUrl']),
        apiKey: key,
      );
    }
  }

  // A bb_-prefixed token wins even when surrounded by other text.
  final match = RegExp(r'bb_[A-Za-z0-9._-]+').firstMatch(s);
  if (match != null) return ScannedApiKeyConfig(apiKey: match.group(0)!);

  // A bare token needs no whitespace (rejects prose) and no URI scheme: a
  // `scheme:` payload this far down had no key param and no `bb_` token — a shop
  // link, a `WIFI:` share — and without the test its whole text would become the
  // "key", which the server answers as "key rejected" rather than "wrong code".
  // The cost is a custom key containing a colon, which has to be typed in.
  final looksLikeLink = uri != null && uri.hasScheme;
  if (!looksLikeLink && !s.contains(RegExp(r'\s'))) {
    return ScannedApiKeyConfig(apiKey: s);
  }
  return null;
}

/// First non-empty value among [keys] in the query string, or null.
String? _firstParam(Uri uri, List<String> keys) {
  for (final k in keys) {
    final v = uri.queryParameters[k]?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}
