/// The two roles the server accepts (`users.py:115`, `:289` — anything else is
/// a 400). `is_admin` is computed from this *or* group membership
/// (`backend/app/models/user.py:99`), and bambuddy's own UI only ever sends
/// `user`, granting admin by putting the account in the Administrators group.
/// The app does the same, so [admin] is here to name the value the server may
/// send back, not one this app writes.
abstract final class UserRoles {
  static const admin = 'admin';
  static const user = 'user';
}

/// Body for `POST /users/` (`UserCreate`, `backend/app/schemas/auth.py:50`).
///
/// [password] is omitted when the server has advanced authentication on — it
/// generates one and mails it (`users.py:137`), and refuses the request
/// without an [email]. With advanced authentication off the reverse holds:
/// the password is required and the e-mail optional.
class UserCreateInput {
  const UserCreateInput({
    required this.username,
    this.password,
    this.email,
    this.role = UserRoles.user,
    this.groupIds,
  });

  final String username;
  final String? password;
  final String? email;
  final String role;
  final List<int>? groupIds;

  Map<String, dynamic> toJson() => {
        'username': username,
        if (password != null) 'password': password,
        if (email != null) 'email': email,
        'role': role,
        if (groupIds != null) 'group_ids': groupIds,
      };
}

/// Body for `PATCH /users/{id}` (`UserUpdate`, `backend/app/schemas/auth.py:64`).
///
/// Every field is optional and **omitted means unchanged** — the route acts on
/// `is not None` (`users.py:256`), so a caller must send only what it means to
/// change. That is also why an e-mail is cleared by sending an empty string
/// rather than a null.
class UserUpdateInput {
  const UserUpdateInput({
    this.username,
    this.password,
    this.email,
    this.role,
    this.isActive,
    this.groupIds,
  });

  final String? username;
  final String? password;
  final String? email;
  final String? role;
  final bool? isActive;
  final List<int>? groupIds;

  /// Nothing to send — the form was opened and closed without a change.
  bool get isEmpty =>
      username == null &&
      password == null &&
      email == null &&
      role == null &&
      isActive == null &&
      groupIds == null;

  Map<String, dynamic> toJson() => {
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (email != null) 'email': email,
        if (role != null) 'role': role,
        if (isActive != null) 'is_active': isActive,
        if (groupIds != null) 'group_ids': groupIds,
      };
}

/// Password rules the server enforces in `_validate_password_complexity`
/// (`backend/app/schemas/auth.py:7`). Mirrored so the form can say which rule
/// is unmet instead of showing the 422 that would come back.
enum PasswordRule { tooShort, noUppercase, noLowercase, noDigit, noSpecial }

/// The first rule [password] breaks, or null when it satisfies all of them.
PasswordRule? checkPasswordComplexity(String password) {
  if (password.length < 8) return PasswordRule.tooShort;
  if (!password.contains(RegExp(r'[A-Z]'))) return PasswordRule.noUppercase;
  if (!password.contains(RegExp(r'[a-z]'))) return PasswordRule.noLowercase;
  if (!password.contains(RegExp(r'\d'))) return PasswordRule.noDigit;
  if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) return PasswordRule.noSpecial;
  return null;
}

/// `GET /auth/advanced-auth/status` — only the two fields the account form
/// needs. [smtpConfigured] matters because the welcome e-mail carrying the
/// generated password is best-effort server-side (`users.py:183` logs the
/// failure and creates the account anyway), so an admin creating an account
/// with no SMTP would leave nobody able to sign in.
class AdvancedAuthStatus {
  const AdvancedAuthStatus({
    required this.enabled,
    required this.smtpConfigured,
  });

  factory AdvancedAuthStatus.fromJson(Map<String, dynamic> json) =>
      AdvancedAuthStatus(
        enabled: json['advanced_auth_enabled'] == true,
        smtpConfigured: json['smtp_configured'] == true,
      );

  /// What an older server that doesn't know the route leaves us with: the
  /// classic shape, where the admin sets the password.
  static const legacy = AdvancedAuthStatus(enabled: false, smtpConfigured: false);

  final bool enabled;
  final bool smtpConfigured;
}
