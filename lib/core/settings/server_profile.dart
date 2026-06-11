/// Tryb uwierzytelniania serwera. KAŻDA ścieżka kodu dotykająca auth
/// (nagłówki, mintowanie tokenów, re-login) MUSI branchować po tym enumie —
/// serwer z wyłączonym auth jest pełnoprawną konfiguracją.
enum AuthMode { none, jwt, apiKey }

/// Profil połączenia z serwerem bambuddy. Nie zawiera sekretów —
/// te żyją w [CredentialsStore] (secure storage).
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

  /// Np. `http://192.168.1.10:8000` — bez końcowego `/` i bez `/api/v1`.
  final String baseUrl;
  final AuthMode authMode;
  final String? label;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'authMode': authMode.name,
        if (label != null) 'label': label,
      };

  /// Normalizuje surowy wpis użytkownika: dokleja `http://` gdy brak
  /// schematu, ucina końcowe `/`.
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
