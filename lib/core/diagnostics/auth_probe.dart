import '../auth/two_factor.dart';
import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Why a second-factor step failed, in terms that point at a fix.
///
/// The names are wire values — the summarising Action groups by them, so
/// renaming one breaks logs already attached to an issue.
enum TwoFactorFailure {
  /// The server checked the code and rejected it. The user retypes and the
  /// challenge lives on.
  code,

  /// The pre-auth token is gone: expired (5 minutes), already spent, or the
  /// `2fa_challenge` binding did not match. With `cookie: false` on the
  /// preceding `two_factor_required` record, this pair is the signature of a
  /// proxy dropping `Set-Cookie` — which otherwise reads as "my code is wrong".
  challenge,

  /// 429. bambuddy allows 5 failed 2FA attempts per user in 15 minutes, and
  /// answers before looking at the code — so a correct one gets this too.
  rateLimit,

  /// The method is not usable on this account (TOTP switched off mid-login, a
  /// backup code without TOTP), or the server cannot send mail.
  method,

  /// Anything else the server said, including 5xx.
  server,
}

/// Records the second login step, which `HttpProbe` deliberately cannot cover.
///
/// `/auth/*` is off that probe's sampling allowlist — the bodies there carry
/// tokens, the password and the code. What survives is a bare status, and a 401
/// from `/2fa/verify` has four different causes with four different fixes (type
/// it again / sign in from scratch / wait 15 minutes / the proxy is eating the
/// cookie). These records name the one that happened.
///
/// Stateless and static, like `HttpProbe` and `NotifProbe`: every method reads
/// `DiagnosticRecorder.active` per call, so an idle app pays nothing.
///
/// ## What never enters a record
///
/// The pre-auth token, the cookie value, the code the user typed, and the
/// e-mail address it was sent to. Which methods the account offers is not a
/// secret and is the first thing worth knowing; whether a cookie arrived is a
/// boolean. The failure reason is the enum above, never the server's `detail`.
class AuthProbe {
  const AuthProbe._();

  /// The password was accepted and the server asked for a second factor.
  ///
  /// `binding`, not `cookie`: the redactor blanks any field whose *name* looks
  /// like a secret, and `cookie` is on that list — a live recording logged
  /// `"cookie":"[REDACTED]"`, which is the same text whether the binding
  /// arrived or not and so answered nothing. The value here is a boolean and
  /// never the cookie itself.
  static void twoFactorRequired(TwoFactorChallenge challenge) =>
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_required',
        fields: {
          'methods': [for (final m in challenge.methods) m.name],
          'binding': challenge.challengeCookie != null,
        },
      );

  /// The challenge ran out its five minutes with no code submitted, so the app
  /// dropped back to the password step by itself.
  ///
  /// Distinct from a [TwoFactorFailure.challenge] verdict, which is the server
  /// refusing a token we did send: nothing went out here at all.
  static void twoFactorLapsed() => DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_lapsed',
      );

  /// An e-mail code was requested. [ok] false means the server refused to send
  /// it; the challenge stays usable either way (the token is only consumed on a
  /// successful send).
  static void emailCodeSent({required bool ok, int? status}) =>
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_email_sent',
        lvl: ok ? LogLevel.info : LogLevel.warn,
        fields: {'ok': ok, 'status': status},
      );

  /// A verification attempt. [failure] null means the app got its JWT.
  static void twoFactorVerified(
    TwoFactorMethod method, {
    TwoFactorFailure? failure,
    int? status,
  }) =>
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_verify',
        lvl: failure == null ? LogLevel.info : LogLevel.warn,
        fields: {
          'method': method.name,
          'ok': failure == null,
          'reason': failure?.name,
          'status': status,
        },
      );

  /// Silent re-login reached a server that now wants a second factor, so the
  /// saved password can no longer restore a session on its own.
  ///
  /// The app goes quiet after this — every later request 401s — and nothing on
  /// screen explains it until the next launch shows the warning. One record
  /// says the session ended for a reason nobody could have acted on in the
  /// background.
  static void twoFactorBlockedSilentLogin() => DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_silent_blocked',
        lvl: LogLevel.warn,
      );
}
