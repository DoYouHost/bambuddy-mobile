import '../auth/two_factor.dart';
import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Why a second-factor step failed, in terms that point at a fix. The names are
/// wire values the summarising Action groups by.
enum TwoFactorFailure {
  /// Server checked the code and rejected it; the challenge lives on.
  code,

  /// The pre-auth token is gone: expired (5 minutes), spent, or the
  /// `2fa_challenge` binding did not match. With `binding: false` on the
  /// preceding `two_factor_required` record, this pair is the signature of a
  /// proxy dropping `Set-Cookie` — which otherwise reads as "my code is wrong".
  challenge,

  /// 429. bambuddy allows 5 failed attempts per user in 15 minutes, and answers
  /// before looking at the code — so a correct one gets this too.
  rateLimit,

  /// The method is not usable on this account (TOTP switched off mid-login, a
  /// backup code without TOTP), or the server cannot send mail.
  method,

  /// Anything else the server said, including 5xx.
  server,
}

/// Records the second login step, which `HttpProbe` deliberately cannot cover.
///
/// `/auth/*` is off that probe's sampling allowlist — the bodies carry tokens,
/// the password and the code — so what survives is a bare status, and a 401
/// from `/2fa/verify` has four causes with four different fixes. These records
/// name the one that happened, never the server's `detail`, the token, the
/// cookie value, the code typed or the address it went to.
class AuthProbe {
  const AuthProbe._();

  /// The password was accepted and the server asked for a second factor.
  ///
  /// `binding`, not `cookie`: the redactor blanks any field whose *name* looks
  /// like a secret, so a live recording logged `"cookie":"[REDACTED]"` — the
  /// same text whether the binding arrived or not. This is a boolean.
  static void twoFactorRequired(TwoFactorChallenge challenge) =>
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'two_factor_required',
        fields: {
          'methods': [for (final m in challenge.methods) m.name],
          'binding': challenge.challengeCookie != null,
        },
      );

  /// The challenge ran out its five minutes with no code submitted. Distinct
  /// from [TwoFactorFailure.challenge] — nothing went out to the server here.
  static void twoFactorLapsed() =>
      DiagnosticRecorder.active?.add(LogSource.app, 'two_factor_lapsed');

  /// An e-mail code was requested. The challenge stays usable even when [ok] is
  /// false — the token is only consumed on a successful send.
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
  }) => DiagnosticRecorder.active?.add(
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

  /// Silent re-login reached a server that now wants a second factor. Nothing
  /// on screen explains the 401s that follow until the next launch warns.
  static void twoFactorBlockedSilentLogin() => DiagnosticRecorder.active?.add(
    LogSource.app,
    'two_factor_silent_blocked',
    lvl: LogLevel.warn,
  );

  /// A step of the proactive refresh threw instead of answering — the keystore
  /// read is the one that does this on some OEMs. Worth a line of its own: the
  /// schedule survives it now, but every request keeps working off a token
  /// nothing renewed, so the failures that follow look like a server problem.
  static void refreshStepFailed(Object error) => DiagnosticRecorder.active?.add(
    LogSource.app,
    'token_refresh_step_failed',
    lvl: LogLevel.warn,
    fields: {'cause': error.runtimeType.toString()},
  );
}
