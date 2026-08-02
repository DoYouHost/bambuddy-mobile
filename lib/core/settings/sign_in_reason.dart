/// Why the app stopped being able to restore a session on its own, and so has
/// to ask the user to sign in by hand.
///
/// Both cases are noticed where nobody can see them — the 401 interceptor and
/// the background token refresh — and afterwards the app just goes quiet. The
/// dashboard turns this into one warning on the next launch, and the reason
/// decides its wording: pointing at the password when 2FA is what changed sends
/// the user off to reset a password that works fine.
///
/// The names are persisted values (SharedPreferences) — renaming one makes the
/// stored reason unreadable, which degrades to the password wording.
enum SignInReason {
  /// The server checked the saved password and rejected it.
  credentialsRejected,

  /// The password still works, but the account now wants a second factor and
  /// nothing in the background can supply one.
  twoFactorRequired;

  static SignInReason fromName(String? name) {
    for (final reason in SignInReason.values) {
      if (reason.name == name) return reason;
    }
    return SignInReason.credentialsRejected;
  }
}
