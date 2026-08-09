/// The second login step: what the server offered, and what the app has to
/// carry between `POST /auth/login` and `POST /auth/2fa/verify`.
///
/// Contract in `docs/plans/10-two-factor-login.md`; server side is
/// `reference/bambuddy/backend/app/api/routes/mfa.py`.
library;

/// Wire values: they go out as `method` on `/2fa/verify`, which accepts exactly
/// these three.
enum TwoFactorMethod {
  /// Authenticator app, 30-second window.
  totp,

  /// Mailed on request, so `/2fa/email/send` has to come first.
  email,

  /// One of the 10 single-use codes from TOTP setup, one fewer afterwards.
  backup;

  static TwoFactorMethod? tryParse(Object? wire) {
    for (final m in TwoFactorMethod.values) {
      if (m.name == wire) return m;
    }
    return null;
  }

  /// The server rejects anything outside `^[A-Za-z0-9]{6,8}$`, so the field can
  /// stop the user before the round trip.
  int get codeLength => this == TwoFactorMethod.backup ? 8 : 6;

  /// Worth a digits-only keyboard for the two that carry no letters.
  bool get isNumericCode => this != TwoFactorMethod.backup;
}

/// A login that got past the password and is waiting for a code.
///
/// `peek_pre_auth_token` in `mfa.py` refuses the token when a call arrives
/// without the matching HttpOnly `2fa_challenge` cookie, so [challengeCookie]
/// travels back on every `/2fa/*` call — dio has no cookie jar and nothing does
/// this implicitly. `null` means the response set none, and a token issued
/// *with* a binding then refuses us: the signature of a reverse proxy stripping
/// `Set-Cookie`, not of a wrong code, which is why `AuthProbe` logs it.
class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.preAuthToken,
    required this.methods,
    this.challengeCookie,
  });

  /// `null` when the body is not a 2FA answer or carries no usable token; the
  /// caller then treats the response as a plain login.
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
      // Every account with 2FA on has at least one factor, so refusing to show
      // a code field because the server named a method we do not know would
      // strand the user for nothing. The code is checked server-side anyway.
      methods: methods.isEmpty ? const [TwoFactorMethod.totp] : methods,
      challengeCookie: readChallengeCookie(setCookie),
    );
  }

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

  /// `PRE_AUTH_TOKEN_TTL` in `mfa.py`. The server never announces the deadline
  /// in the body, so the app counts it down from the moment the answer arrives
  /// — later than the server's own start, so it never cuts a live challenge
  /// short. Otherwise the user learns it went stale by typing a correct code.
  static const lifetime = Duration(minutes: 5);

  final String preAuthToken;

  /// In the order the server listed, and never empty — see [tryParse].
  final List<TwoFactorMethod> methods;

  final String? challengeCookie;

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
