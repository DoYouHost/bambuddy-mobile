import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/admin/user_messages.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules `users.py` enforces, quoted verbatim from the route source
/// (`backend/app/api/routes/users.py`, the `detail=` of each `HTTPException`).
/// The app does not re-implement any of them, so the server's `detail` is the
/// only thing that says which one was hit — and these are what keeps the
/// table matching the words it actually sends.
void main() {
  late AppLocalizations en;
  late AppLocalizations pl;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    pl = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  ActionOutcome refused(String? detail) => ActionOutcome.failed(
    ApiException(AppErrorCode.badResponse, statusCode: 400, detail: detail),
  );

  test('the three last-admin rules are told apart', () {
    // All three details contain "last admin", so the table's order is what
    // keeps them from collapsing into the generic one.
    expect(
      userWriteMessage(en, refused('Cannot delete the last admin user')),
      en.usersErrLastAdminDelete,
    );
    expect(
      userWriteMessage(en, refused('Cannot deactivate the last admin user')),
      en.usersErrLastAdminDeactivate,
    );
    expect(
      userWriteMessage(
        en,
        refused('Cannot change role of the last admin user'),
      ),
      en.usersErrLastAdminRole,
    );
  });

  test('a last-admin refusal worded some other way still lands', () {
    expect(
      userWriteMessage(en, refused('This is the last admin account')),
      en.usersErrLastAdmin,
    );
  });

  test('each remaining rule maps to its own sentence', () {
    final cases = {
      'Cannot delete your own account': en.usersErrSelfDelete,
      'Username already exists': en.usersErrUsernameTaken,
      'Email already exists': en.usersErrEmailTaken,
      'Cannot set password for LDAP users': en.usersErrLdapPassword,
      'Cannot change password for LDAP users — passwords are managed by the '
              'LDAP server':
          en.usersErrLdapPassword,
      'Email is required when advanced authentication is enabled':
          en.usersErrEmailRequired,
      'Password is required when advanced authentication is disabled':
          en.usersErrPasswordRequired,
      'One or more group IDs are invalid': en.usersErrGroupsInvalid,
    };
    cases.forEach((detail, expected) {
      expect(userWriteMessage(en, refused(detail)), expected, reason: detail);
    });
  });

  test('the sentence is the user\'s language, not the server\'s', () {
    expect(
      userWriteMessage(pl, refused('Username already exists')),
      pl.usersErrUsernameTaken,
    );
  });

  test('a rule we do not know is quoted rather than swallowed', () {
    // A server phrasing the app has not met is still the most informative
    // thing available.
    expect(
      userWriteMessage(en, refused('Cannot rename system groups')),
      'Cannot rename system groups',
    );
  });

  test('a refusal the server did not explain falls back to the code', () {
    expect(userWriteMessage(en, refused(null)), en.errBadResponse(400));
  });

  test('an outcome carrying no failure reads as the generic save failure', () {
    // Only reached if a caller asks for the message on a success, which none
    // do — the branch exists so it cannot answer with a lie.
    expect(userWriteMessage(en, ActionOutcome.ok), en.usersSaveFailed);
  });
}
