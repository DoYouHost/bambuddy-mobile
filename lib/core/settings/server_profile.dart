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
}
