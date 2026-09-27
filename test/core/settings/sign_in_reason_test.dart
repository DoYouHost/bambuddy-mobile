import 'package:bambuddy_mobile/core/settings/sign_in_reason.dart';
import 'package:flutter_test/flutter_test.dart';

/// The names are persisted in SharedPreferences, so this reads back what an
/// older install wrote — and has to survive what it cannot recognize.
void main() {
  test('a stored name comes back as the reason that wrote it', () {
    for (final reason in SignInReason.values) {
      expect(SignInReason.fromName(reason.name), reason, reason: reason.name);
    }
  });

  test('a name no build of this app wrote degrades to the password wording', () {
    // Renaming a member — or reading a reason a newer install stored — must not
    // throw on the dashboard; the password sentence is the safe half-truth.
    expect(
      SignInReason.fromName('twoFactorNeeded'),
      SignInReason.credentialsRejected,
    );
    expect(SignInReason.fromName(''), SignInReason.credentialsRejected);
  });

  test('nothing stored at all is the password wording too', () {
    expect(SignInReason.fromName(null), SignInReason.credentialsRejected);
  });
}
