import '../../core/models/user_write.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'users_providers.dart';

/// What to tell the user when an account write was refused.
///
/// The rules live server-side and arrive as an English `detail` string. The
/// ones worth naming are matched and localized; anything else is shown exactly
/// as the server wrote it, which is still better than a generic failure — a
/// server phrasing we don't know yet is usually the most informative thing on
/// screen. Nothing is guessed at: no match and no detail falls back to the
/// error code's own wording.
String userWriteMessage(AppLocalizations l10n, UserWriteResult result) {
  final detail = result.message;
  if (detail != null) {
    final known = _localizedRule(l10n, detail);
    if (known != null) return known;
    return detail;
  }
  final error = result.error;
  if (error != null) return error.localized(l10n);
  return l10n.usersSaveFailed;
}

/// The server's own wording for the rules of `users.py`, matched loosely
/// (`contains`) so a version that adds punctuation or a name still lands.
String? _localizedRule(AppLocalizations l10n, String detail) {
  final d = detail.toLowerCase();
  if (d.contains('last admin')) {
    if (d.contains('delete')) return l10n.usersErrLastAdminDelete;
    if (d.contains('deactivate')) return l10n.usersErrLastAdminDeactivate;
    if (d.contains('role')) return l10n.usersErrLastAdminRole;
    return l10n.usersErrLastAdmin;
  }
  if (d.contains('your own account')) return l10n.usersErrSelfDelete;
  if (d.contains('username already exists')) return l10n.usersErrUsernameTaken;
  if (d.contains('email already exists')) return l10n.usersErrEmailTaken;
  if (d.contains('password for ldap')) return l10n.usersErrLdapPassword;
  if (d.contains('email is required')) return l10n.usersErrEmailRequired;
  if (d.contains('password is required')) return l10n.usersErrPasswordRequired;
  if (d.contains('group ids')) return l10n.usersErrGroupsInvalid;
  return null;
}

/// Why a typed password is not acceptable — the same rules the server applies
/// in `_validate_password_complexity`, said before the request instead of as a
/// 422 after it.
String? passwordRuleMessage(AppLocalizations l10n, String password) =>
    switch (checkPasswordComplexity(password)) {
      PasswordRule.tooShort => l10n.usersPasswordTooShort,
      PasswordRule.noUppercase => l10n.usersPasswordNoUppercase,
      PasswordRule.noLowercase => l10n.usersPasswordNoLowercase,
      PasswordRule.noDigit => l10n.usersPasswordNoDigit,
      PasswordRule.noSpecial => l10n.usersPasswordNoSpecial,
      null => null,
    };
