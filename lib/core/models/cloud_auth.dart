/// Models for Bambu Cloud authentication (`/api/v1/cloud/*`) — required for
/// MakerWorld download.
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

  /// `global` or `china` (null if logged out).
  final String? region;
}

/// Result of `POST /cloud/login` and `POST /cloud/verify` (same shape).
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

  /// Server requests 2FA/OTP code — send via `POST /cloud/verify`.
  final bool needsVerification;
  final String message;

  /// E.g. `email` / `totp` — hint for code source.
  final String? verificationType;

  /// Key sent to TOTP verification (from login response).
  final String? tfaKey;
}
