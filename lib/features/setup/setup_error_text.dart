import '../../core/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'providers.dart';

/// Translate setup error: [AppApiException] from network or local
/// [SetupErrorCode] validation. Shared by the phone and Wear setup screens.
String setupErrorText(AppLocalizations l10n, Object error) {
  if (error is AppApiException) return error.localized(l10n);
  if (error is SetupErrorCode) {
    return switch (error) {
      SetupErrorCode.missingUrl => l10n.errMissingUrl,
      SetupErrorCode.missingApiKey => l10n.errMissingApiKey,
      SetupErrorCode.missingCredentials => l10n.errMissingCredentials,
      SetupErrorCode.missingTwoFactorCode => l10n.errMissingTwoFactorCode,
      SetupErrorCode.requiresServerSetup => l10n.errRequiresServerSetup,
    };
  }
  return error.toString();
}
