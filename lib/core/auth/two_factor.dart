/// The second login step: what the server offered, and what the app has to
/// carry between `POST /auth/login` and `POST /auth/2fa/verify`.
///
/// Contract in `docs/plans/10-two-factor-login.md`; server side is
/// `reference/bambuddy/backend/app/api/routes/mfa.py`.
library;

/// A second factor the account can be verified with. The names are wire values
/// — they go out as `method` on `/2fa/verify`, which accepts exactly these
/// three.
enum TwoFactorMethod {
  /// Authenticator app, 6 digits, 30-second window.
  totp,

  /// 6 digits mailed on request. Needs `/2fa/email/send` first.
  email,

  /// One of the 10 single-use codes handed out with TOTP setup: 8 alphanumeric
  /// characters, and one fewer left afterwards.
  backup;

  static TwoFactorMethod? tryParse(Object? wire) {
    for (final m in TwoFactorMethod.values) {
      if (m.name == wire) return m;
    }
    return null;
  }

  /// Codes are 6 digits everywhere except backup codes, which are 8 characters.
  /// The server rejects anything outside `^[A-Za-z0-9]{6,8}$`, so the field can
  /// stop the user before the round trip.
  int get codeLength => this == TwoFactorMethod.backup ? 8 : 6;

  /// Backup codes carry letters; the other two are numeric, which is worth a
  /// digits-only keyboard.
  bool get isNumericCode => this != TwoFactorMethod.backup;
}

/// A login that got past the password and is waiting for a code.
///
/// [challengeCookie] is the value of the HttpOnly `2fa_challenge` cookie the
/// login response set. The server stores it next to the pre-auth token and
/// refuses the token when a later call comes without the matching value
/// (`peek_pre_auth_token` in `mfa.py`), so it has to travel back on every
/// `/2fa/*` call. Dio carries no cookie jar — nothing does this implicitly.
///
/// `null` means the response had no such cookie. We then send none and let the
/// server decide; a token issued with a binding will refuse us, which is the
/// signature of a reverse proxy stripping `Set-Cookie` rather than of a wrong
/// code — hence it is logged.
class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.preAuthToken,
    required this.methods,
    this.challengeCookie,
  });

  /// Reads the challenge out of a `/auth/login` body plus its response headers.
  /// Returns `null` when the body is not a 2FA answer or carries no usable
  /// token — the caller then treats the response as a plain login.
  static TwoFactorChallenge? tryParse(
    Map<String, dynamic> body, {
    Iterable<String> setCookie = const [],
  }) {
    final token = body['pre_auth_token'];
    if (token is! String || token.isEmpty) return null;
    final raw = body['two_fa_methods'];
    final methods = <TwoFactorMethod>[
      if (raw is List)
        for (final entry in raw) ?TwoFactorMethod.tryParse(entry),
    ];
    return TwoFactorChallenge(
      preAuthToken: token,
      // An empty or unrecognised list still leaves TOTP: every account with 2FA
      // on has at least one factor, and refusing to show a code field because
      // the server named a method we don't know would strand the user for
      // nothing. The code they type is checked server-side either way.
      methods: methods.isEmpty ? const [TwoFactorMethod.totp] : methods,
      challengeCookie: readChallengeCookie(setCookie),
    );
  }

  /// Value of the `2fa_challenge` cookie from `Set-Cookie` headers, or `null`.
  /// Attributes after the first `;` (Path, HttpOnly, …) are dropped.
  static String? readChallengeCookie(Iterable<String> setCookie) {
    for (final header in setCookie) {
      for (final part in header.split(';')) {
        final pair = part.trim();
        if (!pair.startsWith('$cookieName=')) continue;
        final value = pair.substring(cookieName.length + 1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static const cookieName = '2fa_challenge';

  /// How long a pre-auth token stays usable (`PRE_AUTH_TOKEN_TTL` in `mfa.py`,
  /// and the `Max-Age` of the binding cookie). The server never announces the
  /// deadline in the body, so the app counts it down itself — otherwise the
  /// code step sits there indefinitely and the user finds out it went stale
  /// only by typing a correct code and being told it was wrong.
  ///
  /// Counted from the moment the answer arrives, which is already later than
  /// the server's own start, so the app is never the one to cut a live
  /// challenge short.
  static const lifetime = Duration(minutes: 5);

  final String preAuthToken;

  /// What the account can be verified with, in the order the server listed.
  /// Never empty — see [tryParse].
  final List<TwoFactorMethod> methods;

  final String? challengeCookie;

  /// Headers for a `/2fa/*` call: the binding cookie, when there is one.
  Map<String, String> get cookieHeader => {
        if (challengeCookie != null)
          'Cookie': '$cookieName=$challengeCookie',
      };

  /// `/2fa/email/send` answers with a fresh token and expects the same cookie
  /// to carry over.
  TwoFactorChallenge withToken(String token) => TwoFactorChallenge(
        preAuthToken: token,
        methods: methods,
        challengeCookie: challengeCookie,
      );
}
