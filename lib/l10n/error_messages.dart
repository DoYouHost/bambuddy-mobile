import '../core/api/action_outcome.dart';
import '../core/api/api_exceptions.dart';
import 'app_localizations.dart';

/// Turns an API-layer error code into a message in the UI language. Keeps the
/// code → string mapping out of the core, which stays independent of l10n.
extension AppApiExceptionL10n on AppApiException {
  String localized(AppLocalizations l10n) => switch (code) {
        AppErrorCode.serverUnreachable => l10n.errServerUnreachable,
        AppErrorCode.unauthorized => l10n.errUnauthorized,
        AppErrorCode.forbidden => _forbidden(l10n),
        AppErrorCode.badResponse => l10n.errBadResponse(statusCode ?? 0),
        AppErrorCode.badCertificate => l10n.errBadCertificate,
        AppErrorCode.connectionError => l10n.errConnection,
        AppErrorCode.malformedResponse => l10n.errMalformedResponse,
        AppErrorCode.invalidCredentials => l10n.errInvalidCredentials,
        AppErrorCode.twoFactorUnsupported => l10n.errTwoFactorUnsupported,
        AppErrorCode.twoFactorCodeRejected => l10n.errTwoFactorCodeRejected,
        AppErrorCode.twoFactorChallengeExpired =>
          l10n.errTwoFactorChallengeExpired,
        AppErrorCode.twoFactorMethodUnavailable =>
          l10n.errTwoFactorMethodUnavailable,
        AppErrorCode.twoFactorEmailUnavailable =>
          l10n.errTwoFactorEmailUnavailable,
        AppErrorCode.apiKeyRejected => l10n.errApiKeyRejected,
        AppErrorCode.tooManyAttempts => l10n.errTooManyAttempts,
      };

  /// A refusal is the one error a code alone cannot explain: which permission
  /// is missing exists only in what the server wrote. So the frame is
  /// localized and the reason is quoted from the server, in its own English —
  /// the alternative is telling everyone "not allowed" and leaving them to
  /// guess which of a dozen permissions it was.
  String _forbidden(AppLocalizations l10n) {
    if (isApiKeyOwnerDisabled) return l10n.errApiKeyOwnerDisabled;
    final reason = detail;
    return reason == null
        ? l10n.errForbidden
        : l10n.errForbiddenDetail(reason);
  }
}

/// How a failed action reads, for every feature.
///
/// **The rule:** a feature decides *whether* to say something and *where*, never
/// *what it says*. [localized] is the wording, here and everywhere else. A
/// feature may special-case a single status it has genuinely better wording for
/// — "a tag with that name exists" beats "server returned error 409" — but it
/// falls through to here for everything it has not thought about, which is
/// where the interesting failures live.
///
/// Before this, four features each translated their own outcome enum back into
/// their own sentence, and all four discarded what the server said.
extension ActionOutcomeL10n on ActionOutcome {
  /// `null` when nothing failed, so a caller can `if (msg != null) snack(msg)`
  /// without asking twice.
  String? messageFor(AppLocalizations l10n) => switch (this) {
        ActionOk() => null,
        ActionFailed(:final error) => error.localized(l10n),
      };
}
