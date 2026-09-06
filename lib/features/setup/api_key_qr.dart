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
/// The server encodes both the base URL and a freshly-created key in one code so
/// a mobile client can configure everything from a single scan (payload contract
/// `reference/.../apiKeyQr.ts`):
///
///   `bambuddy://config?v=1&url=<encoded baseUrl>&key=<encoded apiKey>`
///
/// Parsing is version-tolerant (the `v` is ignored — a bumped payload that still
/// carries `url`/`key` keeps working) and lenient about hand-made codes:
///
///  1. any URL/deep-link with a `key`/`api_key`/`token` query param (plus an
///     optional `url` param → [baseUrl]);
///  2. otherwise a `bb_…` token found anywhere in the text;
///  3. otherwise the whole value, if it's a single whitespace-free token.
///
/// Returns null when nothing key-shaped can be read. The caller drops the result
/// into the (editable) fields, so a user can still correct a loose match.
/// Top-level (pure function) — testable without UI.
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

  // Bare token: accept only if it carries no whitespace (rejects prose/labels)
  // and carries no URI scheme. Anything scannable ends up in front of this
  // parser, and a `scheme:` payload that got this far had no key parameter and no
  // `bb_` token — a shop link, a `WIFI:` share, an `otpauth:` seed. Without the
  // scheme test its whole text would quietly become the "key" and the server
  // would answer "key rejected", which reads as a bad key rather than a wrong
  // code. Cost of the rule: a custom key containing a colon has to be typed in
  // by hand, which the (editable) field allows.
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
