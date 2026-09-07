import '../../core/api/action_outcome.dart';
import '../../core/models/user_write.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';

/// What to tell the user when an account write was refused.
///
/// The rules of `users.py` live server-side and arrive as an English `detail`;
/// [serverRefusal] is the ladder every feature shares. Only called on the
/// failing branch, so a success reads as the generic save failure — which is
/// the honest thing to say about an outcome that carries no refusal at all.
String userWriteMessage(AppLocalizations l10n, ActionOutcome result) =>
    outcomeRefusal(l10n, result, _rules) ?? l10n.usersSaveFailed;

/// The three `last admin` rows come first and most-specific-first, so the bare
/// one stays the fallback for a wording none of them recognize.
final _rules = <RefusalRule>[
  (['last admin', 'delete'], (l10n) => l10n.usersErrLastAdminDelete),
  (['last admin', 'deactivate'], (l10n) => l10n.usersErrLastAdminDeactivate),
  (['last admin', 'role'], (l10n) => l10n.usersErrLastAdminRole),
  (['last admin'], (l10n) => l10n.usersErrLastAdmin),
  (['your own account'], (l10n) => l10n.usersErrSelfDelete),
  (['username already exists'], (l10n) => l10n.usersErrUsernameTaken),
  (['email already exists'], (l10n) => l10n.usersErrEmailTaken),
  (['password for ldap'], (l10n) => l10n.usersErrLdapPassword),
  (['email is required'], (l10n) => l10n.usersErrEmailRequired),
  (['password is required'], (l10n) => l10n.usersErrPasswordRequired),
  (['group ids'], (l10n) => l10n.usersErrGroupsInvalid),
];

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
