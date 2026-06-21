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

  /// No description provided for @wsReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting live updates…'**
  String get wsReconnecting;

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

  /// No description provided for @ctrlFanPart.
  ///
  /// In en, this message translates to:
  /// **'Part fan'**
  String get ctrlFanPart;

  /// No description provided for @ctrlFanAux.
  ///
  /// In en, this message translates to:
  /// **'Aux fan'**
  String get ctrlFanAux;

  /// No description provided for @ctrlFanChamber.
  ///
  /// In en, this message translates to:
  /// **'Chamber fan'**
  String get ctrlFanChamber;

  /// No description provided for @ctrlSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get ctrlSpeed;

  /// No description provided for @ctrlLight.
  ///
  /// In en, this message translates to:
  /// **'Chamber light'**
  String get ctrlLight;

  /// No description provided for @ctrlLightOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get ctrlLightOn;

  /// No description provided for @ctrlLightOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get ctrlLightOff;

  /// No description provided for @ctrlAirduct.
  ///
  /// In en, this message translates to:
  /// **'Airduct'**
  String get ctrlAirduct;

  /// No description provided for @ctrlAirductCooling.
  ///
  /// In en, this message translates to:
  /// **'Cooling'**
  String get ctrlAirductCooling;

  /// No description provided for @ctrlAirductHeating.
  ///
  /// In en, this message translates to:
  /// **'Heating'**
  String get ctrlAirductHeating;

  /// No description provided for @ctrlPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get ctrlPause;

  /// No description provided for @ctrlResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get ctrlResume;

  /// No description provided for @ctrlStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ctrlStop;

  /// No description provided for @ctrlStopConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop print?'**
  String get ctrlStopConfirmTitle;

  /// No description provided for @ctrlStopConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This cancels the current print. It cannot be resumed.'**
  String get ctrlStopConfirmBody;

  /// No description provided for @ctrlForbidden.
  ///
  /// In en, this message translates to:
  /// **'This API key can\'t control the printer'**
  String get ctrlForbidden;

  /// No description provided for @ctrlFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the command'**
  String get ctrlFailed;

  /// No description provided for @speedSilent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get speedSilent;

  /// No description provided for @speedStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get speedStandard;

  /// No description provided for @speedSport.
  ///
  /// In en, this message translates to:
  /// **'Sport'**
  String get speedSport;

  /// No description provided for @speedLudicrous.
  ///
  /// In en, this message translates to:
  /// **'Ludicrous'**
  String get speedLudicrous;

  /// Smart plug powered on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get smartPlugOn;

  /// Smart plug powered off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get smartPlugOff;

  /// Smart plug does not respond
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get smartPlugUnreachable;

  /// Why the off switch is blocked during a print
  ///
  /// In en, this message translates to:
  /// **'Can\'t cut power while the printer is printing'**
  String get smartPlugCantPowerOff;

  /// Confirm turning the plug off
  ///
  /// In en, this message translates to:
  /// **'Cut power?'**
  String get smartPlugOffConfirmTitle;

  /// Confirm body when turning a plug off
  ///
  /// In en, this message translates to:
  /// **'The printer loses power immediately.'**
  String get smartPlugOffConfirmBody;

  /// Confirm button: turn the plug off
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get smartPlugTurnOff;

  /// Power draw in watts
  ///
  /// In en, this message translates to:
  /// **'{watts} W'**
  String powerWatts(int watts);

  /// Dashboard header power sum tooltip
  ///
  /// In en, this message translates to:
  /// **'Total power draw across all plugs'**
  String get totalPowerTooltip;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'The queue is empty'**
  String get queueEmpty;

  /// No description provided for @queueDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue?'**
  String get queueDeleteTitle;

  /// No description provided for @queueDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the item from the print queue.'**
  String get queueDeleteBody;

  /// No description provided for @queueDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get queueDeleteConfirm;

  /// No description provided for @queueStart.
  ///
  /// In en, this message translates to:
  /// **'Start now'**
  String get queueStart;

  /// No description provided for @queueStartNext.
  ///
  /// In en, this message translates to:
  /// **'Start next'**
  String get queueStartNext;

  /// No description provided for @queueCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get queueCancel;

  /// No description provided for @queueNoFreePrinters.
  ///
  /// In en, this message translates to:
  /// **'No free printers right now'**
  String get queueNoFreePrinters;

  /// No description provided for @queuePrintStarted.
  ///
  /// In en, this message translates to:
  /// **'Print started'**
  String get queuePrintStarted;

  /// No description provided for @queueStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get queueStatusPending;

  /// No description provided for @queueStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get queueStatusScheduled;

  /// No description provided for @queueStatusPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get queueStatusPrinting;

  /// No description provided for @queueStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get queueStatusPaused;

  /// No description provided for @archiveSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search archive'**
  String get archiveSearchHint;

  /// No description provided for @archiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived prints'**
  String get archiveEmpty;

  /// No description provided for @archiveSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search for \"{query}\". Try a different term.'**
  String archiveSearchFailed(String query);

  /// No description provided for @archiveReprint.
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get archiveReprint;

  /// No description provided for @archiveAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get archiveAddToQueue;

  /// No description provided for @archiveReprintConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Start reprint?'**
  String get archiveReprintConfirmTitle;

  /// No description provided for @archiveReprintConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This sends the file to {printer} and starts printing.'**
  String archiveReprintConfirmBody(String printer);

  /// No description provided for @archiveReprintStarted.
  ///
  /// In en, this message translates to:
  /// **'Reprint started'**
  String get archiveReprintStarted;

  /// No description provided for @archiveAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get archiveAddedToQueue;

  /// No description provided for @pickPrinterTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a printer'**
  String get pickPrinterTitle;

  /// No description provided for @noPrintersAvailable.
  ///
  /// In en, this message translates to:
  /// **'No printers available'**
  String get noPrintersAvailable;

  /// No description provided for @detailsShow.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsShow;

  /// No description provided for @detailsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get detailsHide;

  /// No description provided for @cameraTooltip.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraTooltip;

  /// No description provided for @cameraConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to camera…'**
  String get cameraConnecting;

  /// No description provided for @cameraError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the camera stream'**
  String get cameraError;

  /// No description provided for @amsUnit.
  ///
  /// In en, this message translates to:
  /// **'AMS {number}'**
  String amsUnit(int number);

  /// No description provided for @externalSpool.
  ///
  /// In en, this message translates to:
  /// **'External spool'**
  String get externalSpool;

  /// No description provided for @traySlotEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get traySlotEmpty;

  /// No description provided for @extruderLeft.
  ///
  /// In en, this message translates to:
  /// **'Left extruder'**
  String get extruderLeft;

  /// No description provided for @extruderRight.
  ///
  /// In en, this message translates to:
  /// **'Right extruder'**
  String get extruderRight;

  /// No description provided for @extruderLeftShort.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get extruderLeftShort;

  /// No description provided for @extruderRightShort.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get extruderRightShort;

  /// No description provided for @amsHumidityTooltip.
  ///
  /// In en, this message translates to:
  /// **'AMS humidity'**
  String get amsHumidityTooltip;

  /// No description provided for @amsTempTooltip.
  ///
  /// In en, this message translates to:
  /// **'AMS temperature'**
  String get amsTempTooltip;

  /// No description provided for @wifiTooltip.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi signal'**
  String get wifiTooltip;

  /// No description provided for @doorOpen.
  ///
  /// In en, this message translates to:
  /// **'Door open'**
  String get doorOpen;

  /// No description provided for @doorClosed.
  ///
  /// In en, this message translates to:
  /// **'Door closed'**
  String get doorClosed;

  /// No description provided for @firmwareUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Firmware up to date'**
  String get firmwareUpToDate;

  /// No description provided for @firmwareUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Firmware update available: {version}'**
  String firmwareUpdateAvailable(String version);

  /// No description provided for @statusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'status unavailable'**
  String get statusUnavailable;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get statusOffline;

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

  /// No description provided for @errForbidden.
  ///
  /// In en, this message translates to:
  /// **'Not allowed — your API key lacks permission for this'**
  String get errForbidden;

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

  /// No description provided for @notifOngoingBody.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · ETA {eta}'**
  String notifOngoingBody(int percent, String eta);

  /// No description provided for @notifMorePrints.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String notifMorePrints(int count);

  /// No description provided for @printFinishedTitle.
  ///
  /// In en, this message translates to:
  /// **'Print finished'**
  String get printFinishedTitle;

  /// No description provided for @printFinishedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is done'**
  String printFinishedBody(String name);

  /// No description provided for @printFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Print failed'**
  String get printFailedTitle;

  /// No description provided for @printFailedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} failed'**
  String printFailedBody(String name);

  /// No description provided for @notifStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Print started'**
  String get notifStartedTitle;

  /// No description provided for @notifStartedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} started printing'**
  String notifStartedBody(String name);

  /// No description provided for @notifFirstLayerTitle.
  ///
  /// In en, this message translates to:
  /// **'First layer done'**
  String get notifFirstLayerTitle;

  /// No description provided for @notifFirstLayerBody.
  ///
  /// In en, this message translates to:
  /// **'{name} finished its first layer'**
  String notifFirstLayerBody(String name);

  /// No description provided for @notifMilestoneTitle.
  ///
  /// In en, this message translates to:
  /// **'{percent}% printed'**
  String notifMilestoneTitle(int percent);

  /// No description provided for @notifMilestoneBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is {percent}% done'**
  String notifMilestoneBody(String name, int percent);

  /// No description provided for @notifPlateTitle.
  ///
  /// In en, this message translates to:
  /// **'Plate not empty'**
  String get notifPlateTitle;

  /// No description provided for @notifPlateBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} needs the plate cleared before the next job'**
  String notifPlateBody(String printer);

  /// No description provided for @notifOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer offline'**
  String get notifOfflineTitle;

  /// No description provided for @notifOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} lost connection'**
  String notifOfflineBody(String printer);

  /// No description provided for @notifErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer error'**
  String get notifErrorTitle;

  /// No description provided for @notifErrorBody.
  ///
  /// In en, this message translates to:
  /// **'{printer}: {detail}'**
  String notifErrorBody(String printer, String detail);

  /// No description provided for @notifLowFilamentTitle.
  ///
  /// In en, this message translates to:
  /// **'Low filament'**
  String get notifLowFilamentTitle;

  /// No description provided for @notifLowFilamentBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} has {percent}% filament left'**
  String notifLowFilamentBody(String printer, int percent);

  /// No description provided for @notifHumidityTitle.
  ///
  /// In en, this message translates to:
  /// **'AMS humidity high'**
  String get notifHumidityTitle;

  /// No description provided for @notifHumidityHtTitle.
  ///
  /// In en, this message translates to:
  /// **'AMS-HT humidity high'**
  String get notifHumidityHtTitle;

  /// No description provided for @notifHumidityBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} AMS humidity is {value}%'**
  String notifHumidityBody(String printer, int value);

  /// No description provided for @notifBedCooledTitle.
  ///
  /// In en, this message translates to:
  /// **'Bed cooled'**
  String get notifBedCooledTitle;

  /// No description provided for @notifBedCooledBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} bed cooled to {temp}°C'**
  String notifBedCooledBody(String printer, int temp);

  /// No description provided for @notifSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifSettingsTitle;

  /// No description provided for @notifSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose which events trigger a notification. Changes apply the next time background monitoring starts.'**
  String get notifSettingsHint;

  /// No description provided for @notifEventsHeader.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get notifEventsHeader;

  /// No description provided for @notifThresholdsHeader.
  ///
  /// In en, this message translates to:
  /// **'Thresholds'**
  String get notifThresholdsHeader;

  /// No description provided for @notifEvtStarted.
  ///
  /// In en, this message translates to:
  /// **'Print started'**
  String get notifEvtStarted;

  /// No description provided for @notifEvtStartedDesc.
  ///
  /// In en, this message translates to:
  /// **'When a print begins'**
  String get notifEvtStartedDesc;

  /// No description provided for @notifEvtFinished.
  ///
  /// In en, this message translates to:
  /// **'Print finished'**
  String get notifEvtFinished;

  /// No description provided for @notifEvtFinishedDesc.
  ///
  /// In en, this message translates to:
  /// **'When a print completes successfully'**
  String get notifEvtFinishedDesc;

  /// No description provided for @notifEvtFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed'**
  String get notifEvtFailed;

  /// No description provided for @notifEvtFailedDesc.
  ///
  /// In en, this message translates to:
  /// **'When a print fails'**
  String get notifEvtFailedDesc;

  /// No description provided for @notifEvtFirstLayer.
  ///
  /// In en, this message translates to:
  /// **'First layer done'**
  String get notifEvtFirstLayer;

  /// No description provided for @notifEvtFirstLayerDesc.
  ///
  /// In en, this message translates to:
  /// **'When the first layer finishes'**
  String get notifEvtFirstLayerDesc;

  /// No description provided for @notifEvtMilestones.
  ///
  /// In en, this message translates to:
  /// **'Progress milestones'**
  String get notifEvtMilestones;

  /// No description provided for @notifEvtMilestonesDesc.
  ///
  /// In en, this message translates to:
  /// **'At 25%, 50% and 75%'**
  String get notifEvtMilestonesDesc;

  /// No description provided for @notifEvtPlate.
  ///
  /// In en, this message translates to:
  /// **'Plate not empty'**
  String get notifEvtPlate;

  /// No description provided for @notifEvtPlateDesc.
  ///
  /// In en, this message translates to:
  /// **'When the plate must be cleared before the next job'**
  String get notifEvtPlateDesc;

  /// No description provided for @notifEvtOffline.
  ///
  /// In en, this message translates to:
  /// **'Printer offline'**
  String get notifEvtOffline;

  /// No description provided for @notifEvtOfflineDesc.
  ///
  /// In en, this message translates to:
  /// **'When a printer loses connection'**
  String get notifEvtOfflineDesc;

  /// No description provided for @notifEvtError.
  ///
  /// In en, this message translates to:
  /// **'Printer error (HMS)'**
  String get notifEvtError;

  /// No description provided for @notifEvtErrorDesc.
  ///
  /// In en, this message translates to:
  /// **'When the printer reports an HMS error'**
  String get notifEvtErrorDesc;

  /// No description provided for @notifEvtLowFilament.
  ///
  /// In en, this message translates to:
  /// **'Low filament'**
  String get notifEvtLowFilament;

  /// No description provided for @notifEvtLowFilamentDesc.
  ///
  /// In en, this message translates to:
  /// **'When remaining filament drops below the threshold'**
  String get notifEvtLowFilamentDesc;

  /// No description provided for @notifEvtHumidity.
  ///
  /// In en, this message translates to:
  /// **'AMS humidity high'**
  String get notifEvtHumidity;

  /// No description provided for @notifEvtHumidityDesc.
  ///
  /// In en, this message translates to:
  /// **'When AMS humidity rises above the threshold'**
  String get notifEvtHumidityDesc;

  /// No description provided for @notifEvtBedCooled.
  ///
  /// In en, this message translates to:
  /// **'Bed cooled'**
  String get notifEvtBedCooled;

  /// No description provided for @notifEvtBedCooledDesc.
  ///
  /// In en, this message translates to:
  /// **'When the bed cools down after a print'**
  String get notifEvtBedCooledDesc;

  /// No description provided for @notifBedCooledThreshold.
  ///
  /// In en, this message translates to:
  /// **'Bed cooled below {temp}°C'**
  String notifBedCooledThreshold(int temp);

  /// No description provided for @notifHumidityThreshold.
  ///
  /// In en, this message translates to:
  /// **'AMS humidity above {value}%'**
  String notifHumidityThreshold(int value);

  /// No description provided for @notifLowFilamentThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low filament below {percent}%'**
  String notifLowFilamentThreshold(int percent);

  /// No description provided for @notifEventsMenu.
  ///
  /// In en, this message translates to:
  /// **'Notification events'**
  String get notifEventsMenu;

  /// No description provided for @hmsSeverityFatal.
  ///
  /// In en, this message translates to:
  /// **'Fatal'**
  String get hmsSeverityFatal;

  /// No description provided for @hmsSeveritySerious.
  ///
  /// In en, this message translates to:
  /// **'Serious'**
  String get hmsSeveritySerious;

  /// No description provided for @hmsSeverityCommon.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get hmsSeverityCommon;

  /// No description provided for @hmsSeverityInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get hmsSeverityInfo;

  /// No description provided for @hmsModuleMainboard.
  ///
  /// In en, this message translates to:
  /// **'mainboard'**
  String get hmsModuleMainboard;

  /// No description provided for @hmsModuleAms.
  ///
  /// In en, this message translates to:
  /// **'AMS'**
  String get hmsModuleAms;

  /// No description provided for @hmsModuleToolhead.
  ///
  /// In en, this message translates to:
  /// **'toolhead'**
  String get hmsModuleToolhead;

  /// No description provided for @hmsModuleXcam.
  ///
  /// In en, this message translates to:
  /// **'camera'**
  String get hmsModuleXcam;

  /// No description provided for @hmsModuleMc.
  ///
  /// In en, this message translates to:
  /// **'motion controller'**
  String get hmsModuleMc;

  /// No description provided for @hmsErrorsHeader.
  ///
  /// In en, this message translates to:
  /// **'Active errors'**
  String get hmsErrorsHeader;

  /// No description provided for @hmsViewInWiki.
  ///
  /// In en, this message translates to:
  /// **'Open in Bambu wiki'**
  String get hmsViewInWiki;

  /// No description provided for @batteryOptTitle.
  ///
  /// In en, this message translates to:
  /// **'Reliable background notifications'**
  String get batteryOptTitle;

  /// No description provided for @batteryOptBody.
  ///
  /// In en, this message translates to:
  /// **'To keep print notifications working when the app is in the background, allow BambuBuddy to run without battery restrictions. On Samsung phones this is essential.'**
  String get batteryOptBody;

  /// No description provided for @batteryOptAllow.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get batteryOptAllow;

  /// No description provided for @batteryOptLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get batteryOptLater;

  /// No description provided for @batteryOptMenu.
  ///
  /// In en, this message translates to:
  /// **'Background notifications'**
  String get batteryOptMenu;

  /// No description provided for @notificationsReady.
  ///
  /// In en, this message translates to:
  /// **'Notifications are all set'**
  String get notificationsReady;

  /// No description provided for @notificationsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off — enable them in system settings'**
  String get notificationsBlocked;

  /// No description provided for @bgServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'BambuBuddy'**
  String get bgServiceTitle;

  /// No description provided for @bgServiceText.
  ///
  /// In en, this message translates to:
  /// **'Monitoring printers'**
  String get bgServiceText;

  /// No description provided for @bgMonitoringToggle.
  ///
  /// In en, this message translates to:
  /// **'Background monitoring'**
  String get bgMonitoringToggle;

  /// No description provided for @bgMonitoringSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep watching prints while the app is closed. Shows a persistent notification.'**
  String get bgMonitoringSubtitle;

  /// No description provided for @bgMonitoringOn.
  ///
  /// In en, this message translates to:
  /// **'Background monitoring on'**
  String get bgMonitoringOn;

  /// No description provided for @bgMonitoringOff.
  ///
  /// In en, this message translates to:
  /// **'Background monitoring off'**
  String get bgMonitoringOff;

  /// Bottom nav tab: Dashboard
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// Bottom nav tab: Queue
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get navQueue;

  /// Bottom nav tab: Archive
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get navArchive;

  /// Bottom nav tab: Maintenance
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get navMaintenance;

  /// Bottom nav tab: Filaments inventory
  ///
  /// In en, this message translates to:
  /// **'Filaments'**
  String get navFilaments;

  /// No description provided for @inventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No spools in inventory'**
  String get inventoryEmpty;

  /// No description provided for @inventoryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No filaments match your search'**
  String get inventoryNoMatches;

  /// No description provided for @inventorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search material, brand, color…'**
  String get inventorySearchHint;

  /// No description provided for @inventoryShowArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived'**
  String get inventoryShowArchived;

  /// No description provided for @inventoryArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get inventoryArchived;

  /// No description provided for @inventoryLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get inventoryLowStock;

  /// No description provided for @inventoryFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get inventoryFilters;

  /// No description provided for @inventoryFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get inventoryFilterStatus;

  /// No description provided for @inventoryStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get inventoryStatusActive;

  /// No description provided for @inventoryStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get inventoryStatusArchived;

  /// No description provided for @inventoryFilterStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get inventoryFilterStock;

  /// No description provided for @inventoryStockAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inventoryStockAll;

  /// No description provided for @inventoryStockLow.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get inventoryStockLow;

  /// No description provided for @inventoryFilterMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get inventoryFilterMaterial;

  /// No description provided for @inventoryFilterBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get inventoryFilterBrand;

  /// No description provided for @inventoryFiltersClear.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get inventoryFiltersClear;

  /// No description provided for @inventorySpoolCount.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{spool} other{spools}}'**
  String inventorySpoolCount(int count);

  /// No description provided for @inventoryRemaining.
  ///
  /// In en, this message translates to:
  /// **'{grams} g left'**
  String inventoryRemaining(String grams);

  /// No description provided for @inventoryOfTotal.
  ///
  /// In en, this message translates to:
  /// **'of {total} g'**
  String inventoryOfTotal(int total);

  /// No description provided for @inventoryLoadedIn.
  ///
  /// In en, this message translates to:
  /// **'Loaded in {slot}'**
  String inventoryLoadedIn(String slot);

  /// No description provided for @inventoryNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Not loaded in any AMS slot'**
  String get inventoryNotLoaded;

  /// No description provided for @inventoryLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get inventoryLocation;

  /// No description provided for @inventoryNozzleTemp.
  ///
  /// In en, this message translates to:
  /// **'Nozzle temp'**
  String get inventoryNozzleTemp;

  /// No description provided for @inventoryCostPerKg.
  ///
  /// In en, this message translates to:
  /// **'{cost}/kg'**
  String inventoryCostPerKg(String cost);

  /// No description provided for @inventoryNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get inventoryNote;

  /// No description provided for @inventoryTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get inventoryTag;

  /// No description provided for @inventoryUsageHistory.
  ///
  /// In en, this message translates to:
  /// **'Usage history'**
  String get inventoryUsageHistory;

  /// No description provided for @inventoryUsageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usage recorded yet'**
  String get inventoryUsageEmpty;

  /// No description provided for @inventoryUsageWeight.
  ///
  /// In en, this message translates to:
  /// **'{grams} g'**
  String inventoryUsageWeight(String grams);

  /// No description provided for @inventoryKProfiles.
  ///
  /// In en, this message translates to:
  /// **'Calibration (K)'**
  String get inventoryKProfiles;

  /// No description provided for @inventoryKProfileLine.
  ///
  /// In en, this message translates to:
  /// **'{nozzle} mm · K {k}'**
  String inventoryKProfileLine(String nozzle, String k);

  /// No description provided for @maintenanceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No maintenance data'**
  String get maintenanceEmpty;

  /// No description provided for @maintenanceTotalHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h total'**
  String maintenanceTotalHours(int hours);

  /// No description provided for @maintenanceDueBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} due'**
  String maintenanceDueBadge(int count);

  /// No description provided for @maintenanceWarningBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} soon'**
  String maintenanceWarningBadge(int count);

  /// No description provided for @maintenanceDueIn.
  ///
  /// In en, this message translates to:
  /// **'Due in {hours} h'**
  String maintenanceDueIn(int hours);

  /// No description provided for @maintenanceOverdueBy.
  ///
  /// In en, this message translates to:
  /// **'Overdue by {hours} h'**
  String maintenanceOverdueBy(int hours);

  /// No description provided for @maintenancePerform.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get maintenancePerform;

  /// No description provided for @maintenancePerformConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset the counter for this maintenance task?'**
  String get maintenancePerformConfirm;

  /// No description provided for @maintenanceNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get maintenanceNotesHint;

  /// No description provided for @maintenanceHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get maintenanceHistory;

  /// No description provided for @maintenanceHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get maintenanceHistoryEmpty;

  /// No description provided for @maintenanceDone.
  ///
  /// In en, this message translates to:
  /// **'Maintenance marked as done'**
  String get maintenanceDone;

  /// No description provided for @maintenanceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update maintenance'**
  String get maintenanceFailed;

  /// No description provided for @notifEvtMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance due'**
  String get notifEvtMaintenance;

  /// No description provided for @notifEvtMaintenanceDesc.
  ///
  /// In en, this message translates to:
  /// **'When a maintenance task becomes overdue'**
  String get notifEvtMaintenanceDesc;

  /// No description provided for @maintenanceNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance due'**
  String get maintenanceNotifTitle;

  /// No description provided for @maintenanceNotifBody.
  ///
  /// In en, this message translates to:
  /// **'{printer}: {task}'**
  String maintenanceNotifBody(String printer, String task);

  /// No description provided for @maintenanceReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance reminder'**
  String get maintenanceReminderTitle;

  /// No description provided for @maintenanceReminderBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} has {count} overdue maintenance {count, plural, one{task} other{tasks}}'**
  String maintenanceReminderBody(String printer, int count);

  /// No description provided for @maintenanceNotifAction.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get maintenanceNotifAction;
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
