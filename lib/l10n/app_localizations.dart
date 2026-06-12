import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// Dashboard app bar title
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get printersTitle;

  /// Tooltip / action to reset the saved server
  ///
  /// In en, this message translates to:
  /// **'Change server'**
  String get changeServer;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired — sign in again'**
  String get sessionExpired;

  /// No description provided for @serverUnreachableStale.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable — data may be out of date'**
  String get serverUnreachableStale;

  /// No description provided for @connectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server'**
  String get connectFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @searchPrinters.
  ///
  /// In en, this message translates to:
  /// **'Search printers…'**
  String get searchPrinters;

  /// No description provided for @noPrinters.
  ///
  /// In en, this message translates to:
  /// **'No printers — add them on the server'**
  String get noPrinters;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No results for “{query}”'**
  String noSearchResults(String query);

  /// No description provided for @changeServerQuestion.
  ///
  /// In en, this message translates to:
  /// **'Change server?'**
  String get changeServerQuestion;

  /// No description provided for @changeServerWarning.
  ///
  /// In en, this message translates to:
  /// **'The saved profile and credentials will be removed.'**
  String get changeServerWarning;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @noActivePrints.
  ///
  /// In en, this message translates to:
  /// **'No active prints'**
  String get noActivePrints;

  /// No description provided for @printingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} printing} other{{count} printing}}'**
  String printingCount(int count);

  /// No description provided for @nextAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Next available: '**
  String get nextAvailableLabel;

  /// No description provided for @tempNozzle.
  ///
  /// In en, this message translates to:
  /// **'Nozzle'**
  String get tempNozzle;

  /// No description provided for @tempBed.
  ///
  /// In en, this message translates to:
  /// **'Bed'**
  String get tempBed;

  /// No description provided for @tempChamber.
  ///
  /// In en, this message translates to:
  /// **'Chamber'**
  String get tempChamber;

  /// No description provided for @tempNozzleNumbered.
  ///
  /// In en, this message translates to:
  /// **'Nozzle {n}'**
  String tempNozzleNumbered(String n);

  /// No description provided for @statusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'status unavailable'**
  String get statusUnavailable;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get offline;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String remaining(String time);

  /// No description provided for @eta.
  ///
  /// In en, this message translates to:
  /// **'ETA {time}'**
  String eta(String time);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(int minutes);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @connectToServer.
  ///
  /// In en, this message translates to:
  /// **'Connect to server'**
  String get connectToServer;

  /// No description provided for @serverAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'bambuddy server address'**
  String get serverAddressLabel;

  /// No description provided for @serverAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 192.168.1.10:8000'**
  String get serverAddressHint;

  /// No description provided for @serverAddressHelper.
  ///
  /// In en, this message translates to:
  /// **'Remote access: use HTTPS via a reverse proxy'**
  String get serverAddressHelper;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @serverRequiresAuth.
  ///
  /// In en, this message translates to:
  /// **'The server requires authentication'**
  String get serverRequiresAuth;

  /// No description provided for @authModeApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key (recommended)'**
  String get authModeApiKey;

  /// No description provided for @authModeLogin.
  ///
  /// In en, this message translates to:
  /// **'Username & password'**
  String get authModeLogin;

  /// No description provided for @apiKeyExplain.
  ///
  /// In en, this message translates to:
  /// **'An API key does not expire and has limited permissions — create one on the server: Settings → API Keys.'**
  String get apiKeyExplain;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeyLabel;

  /// No description provided for @saveAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Save and connect'**
  String get saveAndConnect;

  /// No description provided for @loginExplain.
  ///
  /// In en, this message translates to:
  /// **'A login session expires after 24 h. Tick “Remember me” to have the app sign in again automatically.'**
  String get loginExplain;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @rememberMeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The password is stored in encrypted storage (Android Keystore)'**
  String get rememberMeSubtitle;

  /// No description provided for @signInAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Sign in and connect'**
  String get signInAndConnect;

  /// No description provided for @errMissingUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter the server address'**
  String get errMissingUrl;

  /// No description provided for @errMissingApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter the API key'**
  String get errMissingApiKey;

  /// No description provided for @errMissingCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter username and password'**
  String get errMissingCredentials;

  /// No description provided for @errRequiresServerSetup.
  ///
  /// In en, this message translates to:
  /// **'The server needs initial setup — finish it in a browser and come back here.'**
  String get errRequiresServerSetup;

  /// No description provided for @errServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable'**
  String get errServerUnreachable;

  /// No description provided for @errUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Not authorized'**
  String get errUnauthorized;

  /// No description provided for @errBadResponse.
  ///
  /// In en, this message translates to:
  /// **'Server returned error {code}'**
  String errBadResponse(int code);

  /// No description provided for @errBadCertificate.
  ///
  /// In en, this message translates to:
  /// **'Invalid TLS certificate (self-signed not supported in v1)'**
  String get errBadCertificate;

  /// No description provided for @errConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get errConnection;

  /// No description provided for @errMalformedResponse.
  ///
  /// In en, this message translates to:
  /// **'Malformed server response'**
  String get errMalformedResponse;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid username or password'**
  String get errInvalidCredentials;

  /// No description provided for @errTwoFactorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Account requires 2FA — not supported in this version. Use an API key (Settings → API Keys on the server).'**
  String get errTwoFactorUnsupported;

  /// No description provided for @errApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'API key rejected — check the key and its scope (can_read_status required)'**
  String get errApiKeyRejected;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
