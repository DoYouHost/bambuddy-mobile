import '../core/api/api_exceptions.dart';
import 'app_localizations.dart';

/// Tłumaczy kod błędu warstwy API na komunikat w języku UI. Trzyma
/// mapowanie kod → string poza rdzeniem, który pozostaje niezależny od l10n.
extension AppApiExceptionL10n on AppApiException {
  String localized(AppLocalizations l10n) => switch (code) {
        AppErrorCode.serverUnreachable => l10n.errServerUnreachable,
        AppErrorCode.unauthorized => l10n.errUnauthorized,
        AppErrorCode.badResponse => l10n.errBadResponse(statusCode ?? 0),
        AppErrorCode.badCertificate => l10n.errBadCertificate,
        AppErrorCode.connectionError => l10n.errConnection,
        AppErrorCode.malformedResponse => l10n.errMalformedResponse,
        AppErrorCode.invalidCredentials => l10n.errInvalidCredentials,
        AppErrorCode.twoFactorUnsupported => l10n.errTwoFactorUnsupported,
        AppErrorCode.apiKeyRejected => l10n.errApiKeyRejected,
      };
}
