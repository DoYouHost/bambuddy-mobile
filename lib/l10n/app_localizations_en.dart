// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get printersTitle => 'Printers';

  @override
  String get changeServer => 'Change server';

  @override
  String get sessionExpired => 'Session expired — sign in again';

  @override
  String get serverUnreachableStale =>
      'Server unreachable — data may be out of date';

  @override
  String get wsReconnecting => 'Reconnecting live updates…';

  @override
  String get connectFailed => 'Could not connect to the server';

  @override
  String get retry => 'Try again';

  @override
  String get searchPrinters => 'Search printers…';

  @override
  String get noPrinters => 'No printers — add them on the server';

  @override
  String noSearchResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get changeServerQuestion => 'Change server?';

  @override
  String get changeServerWarning =>
      'The saved profile and credentials will be removed.';

  @override
  String get cancel => 'Cancel';

  @override
  String get change => 'Change';

  @override
  String get noActivePrints => 'No active prints';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count printing',
      one: '$count printing',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => 'Next available: ';

  @override
  String get tempNozzle => 'Nozzle';

  @override
  String get tempBed => 'Bed';

  @override
  String get tempChamber => 'Chamber';

  @override
  String tempNozzleNumbered(String n) {
    return 'Nozzle $n';
  }

  @override
  String get ctrlFanPart => 'Part fan';

  @override
  String get ctrlFanAux => 'Aux fan';

  @override
  String get ctrlFanChamber => 'Chamber fan';

  @override
  String get ctrlSpeed => 'Speed';

  @override
  String get ctrlLight => 'Chamber light';

  @override
  String get ctrlLightOn => 'On';

  @override
  String get ctrlLightOff => 'Off';

  @override
  String get ctrlAirduct => 'Airduct';

  @override
  String get ctrlAirductCooling => 'Cooling';

  @override
  String get ctrlAirductHeating => 'Heating';

  @override
  String get statusUnavailable => 'status unavailable';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

  @override
  String remaining(String time) {
    return '$time left';
  }

  @override
  String eta(String time) {
    return 'ETA $time';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get connectToServer => 'Connect to server';

  @override
  String get serverAddressLabel => 'bambuddy server address';

  @override
  String get serverAddressHint => 'e.g. 192.168.1.10:8000';

  @override
  String get serverAddressHelper =>
      'Remote access: use HTTPS via a reverse proxy';

  @override
  String get testConnection => 'Test connection';

  @override
  String get serverRequiresAuth => 'The server requires authentication';

  @override
  String get authModeApiKey => 'API key (recommended)';

  @override
  String get authModeLogin => 'Username & password';

  @override
  String get apiKeyExplain =>
      'An API key does not expire and has limited permissions — create one on the server: Settings → API Keys.';

  @override
  String get apiKeyLabel => 'API key';

  @override
  String get saveAndConnect => 'Save and connect';

  @override
  String get loginExplain =>
      'A login session expires after 24 h. Tick “Remember me” to have the app sign in again automatically.';

  @override
  String get usernameLabel => 'Username or email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get rememberMeSubtitle =>
      'The password is stored in encrypted storage (Android Keystore)';

  @override
  String get signInAndConnect => 'Sign in and connect';

  @override
  String get errMissingUrl => 'Enter the server address';

  @override
  String get errMissingApiKey => 'Enter the API key';

  @override
  String get errMissingCredentials => 'Enter username and password';

  @override
  String get errRequiresServerSetup =>
      'The server needs initial setup — finish it in a browser and come back here.';

  @override
  String get errServerUnreachable => 'Server unreachable';

  @override
  String get errUnauthorized => 'Not authorized';

  @override
  String errBadResponse(int code) {
    return 'Server returned error $code';
  }

  @override
  String get errBadCertificate =>
      'Invalid TLS certificate (self-signed not supported in v1)';

  @override
  String get errConnection => 'Connection error';

  @override
  String get errMalformedResponse => 'Malformed server response';

  @override
  String get errInvalidCredentials => 'Invalid username or password';

  @override
  String get errTwoFactorUnsupported =>
      'Account requires 2FA — not supported in this version. Use an API key (Settings → API Keys on the server).';

  @override
  String get errApiKeyRejected =>
      'API key rejected — check the key and its scope (can_read_status required)';
}
