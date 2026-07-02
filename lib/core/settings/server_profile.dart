/// Server authentication mode. EVERY code path that touches auth
/// (headers, token minting, re-login) MUST branch on this enum —
/// auth-disabled servers are fully supported configurations.
enum AuthMode { none, jwt, apiKey }

/// Connection profile for a bambuddy server. Does not contain secrets —
/// those live in [CredentialsStore] (secure storage).
class ServerProfile {
  const ServerProfile({
    required this.baseUrl,
    required this.authMode,
    this.label,
  });

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        baseUrl: json['baseUrl'] as String,
        authMode: AuthMode.values.asNameMap()[json['authMode']] ??
            AuthMode.none,
        label: json['label'] as String?,
      );

  /// E.g., `http://192.168.1.10:8000` — without trailing `/` or `/api/v1`.
  final String baseUrl;
  final AuthMode authMode;
  final String? label;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'authMode': authMode.name,
        if (label != null) 'label': label,
      };

  /// Normalizes raw user input: adds `http://` if no scheme, strips trailing `/`.
  ///
  /// The `http://` default is intentional: local/self-hosted servers are often
  /// plain http, and a public https server redirects the probe so the caller
  /// adopts the reached URL via [baseUrlFromReached]. See setup flow.
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Recover the base URL actually reached by a probe request, honoring any
  /// http→https (or host) redirect the HTTP client followed transparently.
  ///
  /// [reached] is the final URI of the probe (e.g. `Response.realUri`);
  /// [endpointSuffix] is the path that was appended to the base (e.g.
  /// `/api/v1/auth/status`). Strips that suffix off `origin + path` so any base
  /// path prefix survives. Falls back to [requested] when [reached] is null or
  /// doesn't end with the suffix (unexpected shape, e.g. mocked transport).
  static String baseUrlFromReached(
    Uri? reached, {
    required String requested,
    required String endpointSuffix,
  }) {
    if (reached == null) return requested;
    final full = reached.origin + reached.path;
    if (full.endsWith(endpointSuffix)) {
      return full.substring(0, full.length - endpointSuffix.length);
    }
    return requested;
  }
}
