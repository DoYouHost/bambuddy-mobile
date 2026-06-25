// Modele logowania do chmury Bambu (`/api/v1/cloud/*`) — warunek pobierania
// z MakerWorld.

/// Stan z `GET /cloud/status`.
class CloudAuthStatus {
  const CloudAuthStatus({
    required this.isAuthenticated,
    this.email,
    this.region,
  });

  factory CloudAuthStatus.fromJson(Map<String, dynamic> json) =>
      CloudAuthStatus(
        isAuthenticated: json['is_authenticated'] == true,
        email: json['email'] is String ? json['email'] as String : null,
        region: json['region'] is String ? json['region'] as String : null,
      );

  final bool isAuthenticated;
  final String? email;

  /// `global` lub `china` (lub null, gdy wylogowany).
  final String? region;
}

/// Wynik `POST /cloud/login` oraz `POST /cloud/verify` (ten sam kształt).
class CloudLoginResult {
  const CloudLoginResult({
    required this.success,
    this.needsVerification = false,
    this.message = '',
    this.verificationType,
    this.tfaKey,
  });

  factory CloudLoginResult.fromJson(Map<String, dynamic> json) =>
      CloudLoginResult(
        success: json['success'] == true,
        needsVerification: json['needs_verification'] == true,
        message: json['message'] is String ? json['message'] as String : '',
        verificationType: json['verification_type'] is String
            ? json['verification_type'] as String
            : null,
        tfaKey: json['tfa_key'] is String ? json['tfa_key'] as String : null,
      );

  final bool success;

  /// Serwer żąda kodu 2FA/OTP — dosyłamy go przez `POST /cloud/verify`.
  final bool needsVerification;
  final String message;

  /// Np. `email` / `totp` — wskazówka, skąd wziąć kod.
  final String? verificationType;

  /// Klucz przekazywany do weryfikacji TOTP (z odpowiedzi logowania).
  final String? tfaKey;
}
