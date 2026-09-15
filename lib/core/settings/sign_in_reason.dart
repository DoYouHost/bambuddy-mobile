/// Why the app stopped being able to restore a session on its own. Both cases
/// are noticed where nobody can see them — the 401 interceptor and the
/// background token refresh — and the dashboard turns this into one warning on
/// the next launch, whose wording it decides: pointing at the password when 2FA
/// is what changed sends the user to reset a password that works fine.
///
/// **The names are persisted values** (SharedPreferences); renaming one makes
/// the stored reason unreadable.
enum SignInReason {
  credentialsRejected,

  /// The password still works; nothing in the background can supply a second
  /// factor.
  twoFactorRequired;

  static SignInReason fromName(String? name) {
    for (final reason in SignInReason.values) {
      if (reason.name == name) return reason;
    }
    return SignInReason.credentialsRejected;
  }
}
