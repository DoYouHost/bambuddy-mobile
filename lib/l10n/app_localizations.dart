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

  /// No description provided for @signInRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInRequiredTitle;

  /// No description provided for @signInRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'The server rejected your saved password, so the app stopped retrying it — repeated attempts get an account locked out. Sign in again, and use a new password if it was changed.'**
  String get signInRequiredBody;

  /// No description provided for @signInRequiredAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInRequiredAction;

  /// Sign-in warning when silent re-login hit requires_2fa rather than a bad password
  ///
  /// In en, this message translates to:
  /// **'Your account now asks for a second factor, and the app cannot supply one in the background — so it stopped signing in on its own. Sign in again and enter the code.'**
  String get signInRequiredTwoFactorBody;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @serverUnreachableStale.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable — data may be out of date'**
  String get serverUnreachableStale;

  /// Banner shown while the live WebSocket is down but REST polling keeps data fresh
  ///
  /// In en, this message translates to:
  /// **'No live connection — refreshing every 5 s'**
  String get wsReconnecting;

  /// Connection-mode chip: real-time updates over WebSocket
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get connLive;

  /// No description provided for @connLiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Real-time updates over WebSocket'**
  String get connLiveTooltip;

  /// Connection-mode chip: no WebSocket, data refreshed via periodic REST polling
  ///
  /// In en, this message translates to:
  /// **'Polling'**
  String get connPolling;

  /// No description provided for @connPollingTooltip.
  ///
  /// In en, this message translates to:
  /// **'No live link — refreshing every 5 s (REST)'**
  String get connPollingTooltip;

  /// No description provided for @connectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server'**
  String get connectFailed;

  /// No description provided for @filePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'The file dialog could not be opened'**
  String get filePickerFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

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

  /// No description provided for @noPrintersMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No printers match the current filters'**
  String get noPrintersMatchFilters;

  /// Title of the dashboard filter sheet / filter button tooltip
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get dashboardFilters;

  /// No description provided for @filterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get filterStatus;

  /// No description provided for @filtersClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get filtersClear;

  /// No description provided for @hideOffline.
  ///
  /// In en, this message translates to:
  /// **'Hide offline'**
  String get hideOffline;

  /// No description provided for @statusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statusAll;

  /// No description provided for @statusPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get statusPrinting;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get statusIdle;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get statusFinished;

  /// No description provided for @statusErrorFilter.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get statusErrorFilter;

  /// No description provided for @statusOfflineFilter.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOfflineFilter;

  /// No description provided for @addPrinterTitle.
  ///
  /// In en, this message translates to:
  /// **'Add printer'**
  String get addPrinterTitle;

  /// No description provided for @addPrinterName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get addPrinterName;

  /// No description provided for @addPrinterIp.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get addPrinterIp;

  /// No description provided for @addPrinterSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get addPrinterSerial;

  /// No description provided for @addPrinterAccessCode.
  ///
  /// In en, this message translates to:
  /// **'Access code'**
  String get addPrinterAccessCode;

  /// No description provided for @addPrinterModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get addPrinterModel;

  /// No description provided for @addPrinterModelOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get addPrinterModelOptional;

  /// No description provided for @addPrinterModelNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get addPrinterModelNone;

  /// No description provided for @addPrinterLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get addPrinterLocation;

  /// No description provided for @addPrinterLocationOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get addPrinterLocationOptional;

  /// No description provided for @addPrinterSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add printer'**
  String get addPrinterSubmit;

  /// No description provided for @addPrinterConnectionNote.
  ///
  /// In en, this message translates to:
  /// **'The server verifies the connection before saving, so a wrong IP or access code is reported and nothing is created.'**
  String get addPrinterConnectionNote;

  /// No description provided for @addPrinterRequiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get addPrinterRequiredField;

  /// No description provided for @addPrinterSuccess.
  ///
  /// In en, this message translates to:
  /// **'Printer added'**
  String get addPrinterSuccess;

  /// No description provided for @addPrinterErrConnection.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the printer. Check the IP address, serial number and access code, and make sure LAN-only mode is on.'**
  String get addPrinterErrConnection;

  /// No description provided for @addPrinterErrDuplicate.
  ///
  /// In en, this message translates to:
  /// **'A printer with this serial number already exists'**
  String get addPrinterErrDuplicate;

  /// No description provided for @addPrinterErrForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to add printers'**
  String get addPrinterErrForbidden;

  /// No description provided for @addPrinterErrGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not add the printer. Try again.'**
  String get addPrinterErrGeneric;

  /// No description provided for @addPrinterAutoArchive.
  ///
  /// In en, this message translates to:
  /// **'Auto-archive completed prints'**
  String get addPrinterAutoArchive;

  /// No description provided for @addPrinterScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Find printers on the network'**
  String get addPrinterScanTitle;

  /// No description provided for @addPrinterSubnet.
  ///
  /// In en, this message translates to:
  /// **'Subnet to scan'**
  String get addPrinterSubnet;

  /// No description provided for @addPrinterScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan subnet for printers'**
  String get addPrinterScanButton;

  /// No description provided for @addPrinterDiscoverNetwork.
  ///
  /// In en, this message translates to:
  /// **'Discover printers on network'**
  String get addPrinterDiscoverNetwork;

  /// No description provided for @addPrinterScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning… {scanned}/{total}'**
  String addPrinterScanning(int scanned, int total);

  /// No description provided for @addPrinterScanningPlain.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get addPrinterScanningPlain;

  /// No description provided for @addPrinterScanNoResults.
  ///
  /// In en, this message translates to:
  /// **'No printers found'**
  String get addPrinterScanNoResults;

  /// No description provided for @addPrinterScanError.
  ///
  /// In en, this message translates to:
  /// **'Scan failed. Try again.'**
  String get addPrinterScanError;

  /// No description provided for @addPrinterSubnetCustomOption.
  ///
  /// In en, this message translates to:
  /// **'Custom subnet…'**
  String get addPrinterSubnetCustomOption;

  /// No description provided for @addPrinterSubnetCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom subnet (CIDR)'**
  String get addPrinterSubnetCustomLabel;

  /// No description provided for @addPrinterSubnetDockerNote.
  ///
  /// In en, this message translates to:
  /// **'Docker detected. Enter your printer\'s subnet in CIDR notation. Requires network_mode: host in docker-compose.yml.'**
  String get addPrinterSubnetDockerNote;

  /// No description provided for @addPrinterSubnetCustomNote.
  ///
  /// In en, this message translates to:
  /// **'Use a custom subnet if your printer is on a different network than the server. The FTP (990) and MQTT (8883) ports must be reachable across the routing boundary.'**
  String get addPrinterSubnetCustomNote;

  /// No description provided for @addPrinterDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'Run diagnostic'**
  String get addPrinterDiagnostic;

  /// No description provided for @addPrinterDiagnosticRunning.
  ///
  /// In en, this message translates to:
  /// **'Running diagnostic…'**
  String get addPrinterDiagnosticRunning;

  /// No description provided for @addPrinterDiagnosticError.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic failed. Try again.'**
  String get addPrinterDiagnosticError;

  /// No description provided for @diagOverallOk.
  ///
  /// In en, this message translates to:
  /// **'All checks passed'**
  String get diagOverallOk;

  /// No description provided for @diagOverallWarnings.
  ///
  /// In en, this message translates to:
  /// **'Completed with warnings'**
  String get diagOverallWarnings;

  /// No description provided for @diagOverallProblems.
  ///
  /// In en, this message translates to:
  /// **'Problems found'**
  String get diagOverallProblems;

  /// No description provided for @diagCheckPortMqtt.
  ///
  /// In en, this message translates to:
  /// **'MQTT port (8883)'**
  String get diagCheckPortMqtt;

  /// No description provided for @diagCheckPortFtps.
  ///
  /// In en, this message translates to:
  /// **'FTPS port (990)'**
  String get diagCheckPortFtps;

  /// No description provided for @diagCheckPortRtsps.
  ///
  /// In en, this message translates to:
  /// **'Camera port (322)'**
  String get diagCheckPortRtsps;

  /// No description provided for @diagCheckNetworkMode.
  ///
  /// In en, this message translates to:
  /// **'Network mode'**
  String get diagCheckNetworkMode;

  /// No description provided for @diagCheckSubnet.
  ///
  /// In en, this message translates to:
  /// **'Subnet reachability'**
  String get diagCheckSubnet;

  /// No description provided for @diagCheckMqttAuth.
  ///
  /// In en, this message translates to:
  /// **'MQTT credentials'**
  String get diagCheckMqttAuth;

  /// No description provided for @diagCheckDeveloperMode.
  ///
  /// In en, this message translates to:
  /// **'Developer / LAN mode'**
  String get diagCheckDeveloperMode;

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

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

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
  /// **'Part cooling fan'**
  String get ctrlFanPart;

  /// No description provided for @ctrlFanAux.
  ///
  /// In en, this message translates to:
  /// **'Aux fan'**
  String get ctrlFanAux;

  /// No description provided for @ctrlFanAux2.
  ///
  /// In en, this message translates to:
  /// **'Left aux fan'**
  String get ctrlFanAux2;

  /// No description provided for @ctrlFanChamber.
  ///
  /// In en, this message translates to:
  /// **'Chamber fan'**
  String get ctrlFanChamber;

  /// No description provided for @ctrlFanExhaust.
  ///
  /// In en, this message translates to:
  /// **'Exhaust fan'**
  String get ctrlFanExhaust;

  /// No description provided for @ctrlFanPartShort.
  ///
  /// In en, this message translates to:
  /// **'Part'**
  String get ctrlFanPartShort;

  /// No description provided for @ctrlFanAuxShort.
  ///
  /// In en, this message translates to:
  /// **'Aux'**
  String get ctrlFanAuxShort;

  /// No description provided for @ctrlFanAux2Short.
  ///
  /// In en, this message translates to:
  /// **'Aux L'**
  String get ctrlFanAux2Short;

  /// No description provided for @ctrlFanChamberShort.
  ///
  /// In en, this message translates to:
  /// **'Chamber'**
  String get ctrlFanChamberShort;

  /// No description provided for @ctrlFanExhaustShort.
  ///
  /// In en, this message translates to:
  /// **'Exhaust'**
  String get ctrlFanExhaustShort;

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

  /// No description provided for @ctrlOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get ctrlOff;

  /// No description provided for @ctrlSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get ctrlSet;

  /// No description provided for @ctrlActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get ctrlActivate;

  /// No description provided for @ctrlNozzleActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get ctrlNozzleActive;

  /// No description provided for @ctrlDry.
  ///
  /// In en, this message translates to:
  /// **'Dry'**
  String get ctrlDry;

  /// No description provided for @ctrlDrying.
  ///
  /// In en, this message translates to:
  /// **'Drying'**
  String get ctrlDrying;

  /// No description provided for @ctrlDryStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get ctrlDryStart;

  /// No description provided for @ctrlDryFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get ctrlDryFilament;

  /// No description provided for @ctrlDryTemp.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get ctrlDryTemp;

  /// No description provided for @ctrlDryDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get ctrlDryDuration;

  /// No description provided for @ctrlDryHours.
  ///
  /// In en, this message translates to:
  /// **'{h} h'**
  String ctrlDryHours(int h);

  /// No description provided for @ctrlDryAutoIdle.
  ///
  /// In en, this message translates to:
  /// **'Auto-drying when humidity is high.'**
  String get ctrlDryAutoIdle;

  /// No description provided for @ctrlDryAutoQueue.
  ///
  /// In en, this message translates to:
  /// **'Auto-drying between queued prints.'**
  String get ctrlDryAutoQueue;

  /// No description provided for @ctrlDryAutoWhilePrinting.
  ///
  /// In en, this message translates to:
  /// **'During prints, too.'**
  String get ctrlDryAutoWhilePrinting;

  /// No description provided for @ctrlDryStartWhen.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get ctrlDryStartWhen;

  /// No description provided for @ctrlDryStartNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get ctrlDryStartNow;

  /// No description provided for @ctrlDryStartAfter.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get ctrlDryStartAfter;

  /// No description provided for @ctrlDryStartAt.
  ///
  /// In en, this message translates to:
  /// **'At time'**
  String get ctrlDryStartAt;

  /// No description provided for @ctrlDryPickTime.
  ///
  /// In en, this message translates to:
  /// **'Pick a time'**
  String get ctrlDryPickTime;

  /// No description provided for @ctrlDrySchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get ctrlDrySchedule;

  /// No description provided for @ctrlDryScheduled.
  ///
  /// In en, this message translates to:
  /// **'Drying scheduled'**
  String get ctrlDryScheduled;

  /// No description provided for @ctrlDryScheduleTimePast.
  ///
  /// In en, this message translates to:
  /// **'Pick a time in the future'**
  String get ctrlDryScheduleTimePast;

  /// No description provided for @ctrlDryScheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Drying at {time}'**
  String ctrlDryScheduledFor(String time);

  /// No description provided for @ctrlDryScheduledAsap.
  ///
  /// In en, this message translates to:
  /// **'Drying scheduled, waiting for the printer'**
  String get ctrlDryScheduledAsap;

  /// No description provided for @ctrlDryScheduleCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel scheduled drying'**
  String get ctrlDryScheduleCancel;

  /// No description provided for @ctrlDryScheduleDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get ctrlDryScheduleDismiss;

  /// No description provided for @ctrlDryScheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'Scheduled drying failed: {reason}'**
  String ctrlDryScheduleFailed(String reason);

  /// No description provided for @ctrlDryScheduleFailedUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown error'**
  String get ctrlDryScheduleFailedUnknown;

  /// No description provided for @ctrlDryWaitPower.
  ///
  /// In en, this message translates to:
  /// **'Connect the AMS power adapter'**
  String get ctrlDryWaitPower;

  /// No description provided for @ctrlDryWaitRetract.
  ///
  /// In en, this message translates to:
  /// **'Retract the filament at the AMS outlet'**
  String get ctrlDryWaitRetract;

  /// No description provided for @ctrlDryWaitBlocked.
  ///
  /// In en, this message translates to:
  /// **'The AMS cannot start drying right now'**
  String get ctrlDryWaitBlocked;

  /// No description provided for @ctrlDryWaitAmsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the AMS to be detected'**
  String get ctrlDryWaitAmsNotFound;

  /// No description provided for @ctrlDryWaitOffline.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the printer to come online'**
  String get ctrlDryWaitOffline;

  /// No description provided for @ctrlDryWaitBusy.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the printer to be free'**
  String get ctrlDryWaitBusy;

  /// No description provided for @ctrlDryWaitAlreadyDrying.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the current cycle to finish'**
  String get ctrlDryWaitAlreadyDrying;

  /// No description provided for @ctrlDryWaitInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted, will restart when the printer is free'**
  String get ctrlDryWaitInterrupted;

  /// No description provided for @ctrlMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get ctrlMove;

  /// No description provided for @ctrlMoveHome.
  ///
  /// In en, this message translates to:
  /// **'Home all'**
  String get ctrlMoveHome;

  /// No description provided for @ctrlMoveHomeStarted.
  ///
  /// In en, this message translates to:
  /// **'Homing started'**
  String get ctrlMoveHomeStarted;

  /// No description provided for @ctrlMoveStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get ctrlMoveStep;

  /// No description provided for @ctrlMoveZ.
  ///
  /// In en, this message translates to:
  /// **'Z (bed gap)'**
  String get ctrlMoveZ;

  /// No description provided for @ctrlMoveZUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get ctrlMoveZUp;

  /// No description provided for @ctrlMoveZDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get ctrlMoveZDown;

  /// No description provided for @ctrlMoveExtruder.
  ///
  /// In en, this message translates to:
  /// **'Extruder'**
  String get ctrlMoveExtruder;

  /// No description provided for @ctrlMoveExtrude.
  ///
  /// In en, this message translates to:
  /// **'Extrude'**
  String get ctrlMoveExtrude;

  /// No description provided for @ctrlMoveRetract.
  ///
  /// In en, this message translates to:
  /// **'Retract'**
  String get ctrlMoveRetract;

  /// No description provided for @ctrlMoveLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get ctrlMoveLength;

  /// No description provided for @ctrlMoveMm.
  ///
  /// In en, this message translates to:
  /// **'{d} mm'**
  String ctrlMoveMm(int d);

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
  /// **'No permission to control this printer'**
  String get ctrlForbidden;

  /// No description provided for @ctrlFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the command'**
  String get ctrlFailed;

  /// Skip-objects screen title
  ///
  /// In en, this message translates to:
  /// **'Skip objects'**
  String get skipObjectsTitle;

  /// Button: skip a single object
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipObjectsSkip;

  /// Status label on an already-skipped object
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skipObjectsSkippedTag;

  /// Snackbar after skipping one or more objects
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Skipped \"{names}\"} other{Skipped {count} objects}}'**
  String skipObjectsSkippedToast(int count, String names);

  /// Confirm dialog title before skipping the selected objects
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Skip this object?} other{Skip {count} objects?}}'**
  String skipObjectsConfirmTitle(int count);

  /// Confirm dialog body before skipping the selected objects
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{\"{names}\" will be skipped for the rest of this print. This can\'t be undone.} other{\"{names}\" will be skipped for the rest of this print. This can\'t be undone.}}'**
  String skipObjectsConfirmBody(int count, String names);

  /// Bottom bar: how many objects are selected to skip
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String skipObjectsSelectedCount(int count);

  /// Hint shown while nothing is selected yet
  ///
  /// In en, this message translates to:
  /// **'Tap an object above or below to select it for skipping'**
  String get skipObjectsSelectHint;

  /// Info banner title on the skip screen
  ///
  /// In en, this message translates to:
  /// **'Match IDs with your printer display'**
  String get skipObjectsMatchInfo;

  /// Info banner subtitle on the skip screen
  ///
  /// In en, this message translates to:
  /// **'The printer screen shows object IDs on the build plate'**
  String get skipObjectsMatchHint;

  /// Skipped-of-total counter in the info banner
  ///
  /// In en, this message translates to:
  /// **'{skipped}/{total} skipped'**
  String skipObjectsCounter(int skipped, int total);

  /// Active (not skipped) object count badge on the plate preview
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String skipObjectsActiveCount(int count);

  /// Warning: the first layer can't be skipped
  ///
  /// In en, this message translates to:
  /// **'Skipping is available from layer 2 (currently layer {layer})'**
  String skipObjectsWaitForLayer(int layer);

  /// Empty state title on the skip screen
  ///
  /// In en, this message translates to:
  /// **'No printable objects'**
  String get skipObjectsEmpty;

  /// Empty state hint on the skip screen
  ///
  /// In en, this message translates to:
  /// **'Objects load when a print starts. Reload if a print is running.'**
  String get skipObjectsEmptyHint;

  /// Button: re-read objects from the print file
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get skipObjectsReload;

  /// Error state on the skip screen
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load printable objects.'**
  String get skipObjectsLoadFailed;

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

  /// Why an MQTT plug cannot be switched from the card
  ///
  /// In en, this message translates to:
  /// **'Monitoring only'**
  String get smartPlugMonitorOnly;

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

  /// Confirm turning the plug on
  ///
  /// In en, this message translates to:
  /// **'Power on?'**
  String get smartPlugOnConfirmTitle;

  /// Confirm body when turning a plug on
  ///
  /// In en, this message translates to:
  /// **'The printer will be powered on.'**
  String get smartPlugOnConfirmBody;

  /// Confirm button: turn the plug on
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get smartPlugTurnOn;

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

  /// No description provided for @queueAmsFromSlicer.
  ///
  /// In en, this message translates to:
  /// **'AMS from slicer'**
  String get queueAmsFromSlicer;

  /// No description provided for @queueAnyOfModels.
  ///
  /// In en, this message translates to:
  /// **'Any of: {models}'**
  String queueAnyOfModels(String models);

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

  /// No description provided for @archiveNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No prints match your filters'**
  String get archiveNoMatches;

  /// No description provided for @archiveFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get archiveFilters;

  /// No description provided for @archiveFiltersClear.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get archiveFiltersClear;

  /// No description provided for @archiveSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get archiveSortLabel;

  /// No description provided for @archiveSortDateDesc.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get archiveSortDateDesc;

  /// No description provided for @archiveSortDateAsc.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get archiveSortDateAsc;

  /// No description provided for @archiveSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get archiveSortNameAsc;

  /// No description provided for @archiveSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get archiveSortNameDesc;

  /// No description provided for @archiveSortSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Largest first'**
  String get archiveSortSizeDesc;

  /// No description provided for @archiveSortSizeAsc.
  ///
  /// In en, this message translates to:
  /// **'Smallest first'**
  String get archiveSortSizeAsc;

  /// No description provided for @archiveFilterFileType.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get archiveFilterFileType;

  /// No description provided for @archiveFileTypeAll.
  ///
  /// In en, this message translates to:
  /// **'All files'**
  String get archiveFileTypeAll;

  /// No description provided for @archiveFileTypeGcode.
  ///
  /// In en, this message translates to:
  /// **'Sliced'**
  String get archiveFileTypeGcode;

  /// No description provided for @archiveFileTypeSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get archiveFileTypeSource;

  /// No description provided for @archiveFilterFlags.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get archiveFilterFlags;

  /// No description provided for @archiveFilterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get archiveFilterFavorites;

  /// No description provided for @archiveFilterHideFailed.
  ///
  /// In en, this message translates to:
  /// **'Hide failed'**
  String get archiveFilterHideFailed;

  /// No description provided for @archiveFilterHideDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Hide duplicates'**
  String get archiveFilterHideDuplicates;

  /// No description provided for @archiveFilterPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get archiveFilterPrinter;

  /// No description provided for @archiveFilterMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get archiveFilterMaterial;

  /// No description provided for @archiveFilterColors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get archiveFilterColors;

  /// No description provided for @archiveColorModeAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get archiveColorModeAny;

  /// No description provided for @archiveColorModeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get archiveColorModeAll;

  /// No description provided for @archiveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get archiveFavorite;

  /// No description provided for @archiveUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get archiveUnfavorite;

  /// No description provided for @archiveFavoriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update favorite'**
  String get archiveFavoriteFailed;

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

  /// No description provided for @archiveTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Watch timelapse'**
  String get archiveTimelapse;

  /// No description provided for @archivePhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{View photo} other{View photos ({count})}}'**
  String archivePhotos(int count);

  /// Archive detail sheet: one entry for everything the print has to look at or keep — replaces the separate timelapse and photos buttons.
  ///
  /// In en, this message translates to:
  /// **'Recordings & photos'**
  String get archiveMediaAction;

  /// Section header: what bambuddy already holds. These rows open a viewer.
  ///
  /// In en, this message translates to:
  /// **'On the server'**
  String get archiveMediaOnServer;

  /// Section header: what is still only on the printer's own storage. These rows are ticked and downloaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{On the printer} other{On the printer ({count})}}'**
  String archiveMediaOnPrinter(int count);

  /// No description provided for @archiveMediaSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking on the printer…'**
  String get archiveMediaSearching;

  /// No description provided for @archiveMediaNothingOnPrinter.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the printer'**
  String get archiveMediaNothingOnPrinter;

  /// Subtitle of the photos row in the media sheet — the row's own count, beside the timelapse row's size.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{one photo} other{{count} photos}}'**
  String archiveMediaPhotoCount(int count);

  /// No description provided for @archiveMediaKindTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Timelapse'**
  String get archiveMediaKindTimelapse;

  /// No description provided for @archiveMediaKindIpcam.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get archiveMediaKindIpcam;

  /// Download button. Zero is the disabled state, before anything is ticked.
  ///
  /// In en, this message translates to:
  /// **'Download {count, plural, =0{selected} one{one file} other{{count} files}}'**
  String archiveMediaDownloadSelected(int count);

  /// No description provided for @archiveMediaSaved.
  ///
  /// In en, this message translates to:
  /// **'Video saved'**
  String get archiveMediaSaved;

  /// No description provided for @archiveMediaNoFilePermission.
  ///
  /// In en, this message translates to:
  /// **'No permission for the printer\'s files'**
  String get archiveMediaNoFilePermission;

  /// No description provided for @archiveMediaPrinterMissing.
  ///
  /// In en, this message translates to:
  /// **'The printer is gone'**
  String get archiveMediaPrinterMissing;

  /// No description provided for @archiveMediaTimelapseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Timelapses: no answer from the printer'**
  String get archiveMediaTimelapseUnavailable;

  /// No description provided for @archiveMediaIpcamUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera: no answer from the printer'**
  String get archiveMediaIpcamUnavailable;

  /// No description provided for @archivePlate.
  ///
  /// In en, this message translates to:
  /// **'Plate {plate}'**
  String archivePlate(int plate);

  /// Line in the archive detail sheet: which plate of a multi-plate 3MF this run printed
  ///
  /// In en, this message translates to:
  /// **'Plate {plate} of a multi-plate file'**
  String archivePlateDetail(int plate);

  /// No description provided for @archivePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get archivePhotosTitle;

  /// No description provided for @archivePhotosEmpty.
  ///
  /// In en, this message translates to:
  /// **'No photos for this print'**
  String get archivePhotosEmpty;

  /// No description provided for @archivePhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this photo.'**
  String get archivePhotoFailed;

  /// No description provided for @archiveFilamentUsed.
  ///
  /// In en, this message translates to:
  /// **'Filament used'**
  String get archiveFilamentUsed;

  /// No description provided for @archiveFilamentGrams.
  ///
  /// In en, this message translates to:
  /// **'{grams} g'**
  String archiveFilamentGrams(String grams);

  /// No description provided for @archiveFilamentActual.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Used {grams}} other{Used {grams} over {count} runs}}'**
  String archiveFilamentActual(String grams, int count);

  /// No description provided for @archiveFilamentNoActual.
  ///
  /// In en, this message translates to:
  /// **'No usage recorded'**
  String get archiveFilamentNoActual;

  /// No description provided for @archiveFilamentSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get archiveFilamentSaving;

  /// No description provided for @archiveFilamentNone.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get archiveFilamentNone;

  /// No description provided for @archiveFilamentLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight (g)'**
  String get archiveFilamentLabel;

  /// No description provided for @archiveFilamentNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, or leave it empty to clear the weight.'**
  String get archiveFilamentNotANumber;

  /// No description provided for @archiveFilamentOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'A weight between 0 and {max} g.'**
  String archiveFilamentOutOfRange(String max);

  /// No description provided for @archiveFilamentSaved.
  ///
  /// In en, this message translates to:
  /// **'Filament weight saved'**
  String get archiveFilamentSaved;

  /// No description provided for @archiveFilamentUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server doesn\'t store a typed-in filament weight yet. Update bambuddy.'**
  String get archiveFilamentUnsupported;

  /// No description provided for @archiveHasTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Has a timelapse'**
  String get archiveHasTimelapse;

  /// No description provided for @archiveHasPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Has a photo} other{Has {count} photos}}'**
  String archiveHasPhotos(int count);

  /// No description provided for @timelapseTitle.
  ///
  /// In en, this message translates to:
  /// **'Timelapse'**
  String get timelapseTitle;

  /// No description provided for @timelapseError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this timelapse.'**
  String get timelapseError;

  /// No description provided for @timelapseHttpError.
  ///
  /// In en, this message translates to:
  /// **'The server would not hand over this timelapse ({status}).'**
  String timelapseHttpError(int status);

  /// No description provided for @timelapseStalled.
  ///
  /// In en, this message translates to:
  /// **'The server is serving the video, but the player never started it.'**
  String get timelapseStalled;

  /// No description provided for @timelapsePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get timelapsePlay;

  /// No description provided for @timelapsePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get timelapsePause;

  /// No description provided for @timelapseSave.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get timelapseSave;

  /// No description provided for @timelapseShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get timelapseShare;

  /// No description provided for @timelapseSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to the gallery'**
  String get timelapseSaved;

  /// No description provided for @timelapseSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the video'**
  String get timelapseSaveFailed;

  /// No description provided for @timelapseSaveDenied.
  ///
  /// In en, this message translates to:
  /// **'Bambuddy needs permission to write to the gallery on this Android version.'**
  String get timelapseSaveDenied;

  /// No description provided for @timelapseEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get timelapseEdit;

  /// No description provided for @timelapseEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get timelapseEditSave;

  /// No description provided for @timelapseEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit timelapse'**
  String get timelapseEditTitle;

  /// No description provided for @timelapseEditTrim.
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get timelapseEditTrim;

  /// No description provided for @timelapseEditSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get timelapseEditSpeed;

  /// No description provided for @timelapseEditOutput.
  ///
  /// In en, this message translates to:
  /// **'Result: {length}'**
  String timelapseEditOutput(String length);

  /// No description provided for @timelapseEditSource.
  ///
  /// In en, this message translates to:
  /// **'Original: {length} at {width}×{height}'**
  String timelapseEditSource(String length, int width, int height);

  /// No description provided for @timelapseEditSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwrite the recording?'**
  String get timelapseEditSaveTitle;

  /// No description provided for @timelapseEditSaveMessage.
  ///
  /// In en, this message translates to:
  /// **'The server re-encodes the timelapse and replaces the original. There is no copy to go back to.'**
  String get timelapseEditSaveMessage;

  /// No description provided for @timelapseEditProcessing.
  ///
  /// In en, this message translates to:
  /// **'The server is re-encoding the video. On a small host this takes minutes — leaving this screen does not stop it.'**
  String get timelapseEditProcessing;

  /// No description provided for @timelapseEdited.
  ///
  /// In en, this message translates to:
  /// **'Timelapse updated'**
  String get timelapseEdited;

  /// No description provided for @gcodeViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'G-code preview'**
  String get gcodeViewerTitle;

  /// No description provided for @gcodeViewerOpen.
  ///
  /// In en, this message translates to:
  /// **'Preview G-code'**
  String get gcodeViewerOpen;

  /// No description provided for @gcodeViewerError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the G-code preview.'**
  String get gcodeViewerError;

  /// No description provided for @gcodeViewerLoading.
  ///
  /// In en, this message translates to:
  /// **'Downloading G-code…'**
  String get gcodeViewerLoading;

  /// No description provided for @gcodeViewerParsing.
  ///
  /// In en, this message translates to:
  /// **'Reading the toolpath…'**
  String get gcodeViewerParsing;

  /// No description provided for @gcodeViewerTravels.
  ///
  /// In en, this message translates to:
  /// **'Travel moves'**
  String get gcodeViewerTravels;

  /// No description provided for @gcodeViewerColorByFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get gcodeViewerColorByFilament;

  /// No description provided for @gcodeViewerColorByFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get gcodeViewerColorByFeature;

  /// No description provided for @gcodeViewerColorByHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get gcodeViewerColorByHeight;

  /// No description provided for @gcodeViewerColorByWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get gcodeViewerColorByWidth;

  /// No description provided for @gcodeSingleLayer.
  ///
  /// In en, this message translates to:
  /// **'single layer'**
  String get gcodeSingleLayer;

  /// No description provided for @gcodeViewerFilamentSlot.
  ///
  /// In en, this message translates to:
  /// **'Filament {n}'**
  String gcodeViewerFilamentSlot(int n);

  /// No description provided for @gcodeViewerEmpty.
  ///
  /// In en, this message translates to:
  /// **'There is no toolpath in this file — it hasn\'t been sliced yet.'**
  String get gcodeViewerEmpty;

  /// No description provided for @gcodeViewerHttpError.
  ///
  /// In en, this message translates to:
  /// **'The server would not hand over the G-code for this file ({status}).'**
  String gcodeViewerHttpError(int status);

  /// No description provided for @gcodeFeatureWall.
  ///
  /// In en, this message translates to:
  /// **'Walls'**
  String get gcodeFeatureWall;

  /// No description provided for @gcodeFeatureSparseInfill.
  ///
  /// In en, this message translates to:
  /// **'Sparse infill'**
  String get gcodeFeatureSparseInfill;

  /// No description provided for @gcodeFeatureSolidInfill.
  ///
  /// In en, this message translates to:
  /// **'Solid infill'**
  String get gcodeFeatureSolidInfill;

  /// No description provided for @gcodeFeatureSkirt.
  ///
  /// In en, this message translates to:
  /// **'Skirt / brim'**
  String get gcodeFeatureSkirt;

  /// No description provided for @gcodeFeatureSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get gcodeFeatureSupport;

  /// No description provided for @gcodeFeatureGapFill.
  ///
  /// In en, this message translates to:
  /// **'Gap fill'**
  String get gcodeFeatureGapFill;

  /// No description provided for @gcodeFeatureBridge.
  ///
  /// In en, this message translates to:
  /// **'Bridge / overhang'**
  String get gcodeFeatureBridge;

  /// No description provided for @gcodeFeatureIroning.
  ///
  /// In en, this message translates to:
  /// **'Ironing'**
  String get gcodeFeatureIroning;

  /// No description provided for @gcodeFeaturePrimeTower.
  ///
  /// In en, this message translates to:
  /// **'Prime tower'**
  String get gcodeFeaturePrimeTower;

  /// No description provided for @archiveNo3mfTitle.
  ///
  /// In en, this message translates to:
  /// **'Some recent prints archived without their thumbnails'**
  String get archiveNo3mfTitle;

  /// Banner on the archive screen for the original cause: the slicer setting. The quoted string is a Bambu Studio / OrcaSlicer label and stays in English in every locale, because that is what the slicer shows.
  ///
  /// In en, this message translates to:
  /// **'The slicer didn\'t leave the .gcode.3mf on the printer\'s card, so Bambuddy couldn\'t pull the thumbnail or the slicer metadata. Usually \"Store sent files on external storage\" is off in the slicer\'s Device tab.'**
  String get archiveNo3mfBody;

  /// No description provided for @archiveNo3mfTitleInternal.
  ///
  /// In en, this message translates to:
  /// **'Some recent prints stayed on the printer\'s internal storage'**
  String get archiveNo3mfTitleInternal;

  /// Same banner for the H2-series / P2S case (#2780), where the slicer setting is already on and the advice above would be wrong.
  ///
  /// In en, this message translates to:
  /// **'Bambu Studio put the sliced file on the printer\'s internal storage instead of the card, so there was nothing to read over FTP. On H2-series and P2S the Print button always does that — switching the slicer setting on changes nothing. Those prints are still archived with their name and timing, just without a thumbnail or slicer metadata. For complete archives, start the print from Bambuddy or slice in OrcaSlicer — either way with a card or stick in the printer.'**
  String get archiveNo3mfBodyInternal;

  /// No description provided for @archiveNo3mfTitleNoStorage.
  ///
  /// In en, this message translates to:
  /// **'Some recent prints couldn\'t be archived — no storage in the printer'**
  String get archiveNo3mfTitleNoStorage;

  /// No description provided for @archiveNo3mfBodyNoStorage.
  ///
  /// In en, this message translates to:
  /// **'The printer reports no card or stick in its slot, so the sliced file had nowhere to land and Bambuddy had nothing to read. Insert one and the next print archives in full.'**
  String get archiveNo3mfBodyNoStorage;

  /// No description provided for @archiveNo3mfDocs.
  ///
  /// In en, this message translates to:
  /// **'See install step 4'**
  String get archiveNo3mfDocs;

  /// No description provided for @archiveNo3mfDocsWhy.
  ///
  /// In en, this message translates to:
  /// **'Why this happens'**
  String get archiveNo3mfDocsWhy;

  /// Tooltip and accessible name of the banner's close button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss this notice'**
  String get archiveNo3mfDismiss;

  /// No description provided for @archiveDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get archiveDelete;

  /// No description provided for @archiveDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete print?'**
  String get archiveDeleteTitle;

  /// No description provided for @archiveDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the archive.'**
  String archiveDeleteBody(String name);

  /// No description provided for @archiveDeletePurgeStats.
  ///
  /// In en, this message translates to:
  /// **'Also remove from statistics'**
  String get archiveDeletePurgeStats;

  /// No description provided for @archiveDeletePurgeStatsHint.
  ///
  /// In en, this message translates to:
  /// **'Otherwise the print is kept in your statistics totals.'**
  String get archiveDeletePurgeStatsHint;

  /// No description provided for @archiveDeleted.
  ///
  /// In en, this message translates to:
  /// **'Print deleted'**
  String get archiveDeleted;

  /// No description provided for @archiveDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the print'**
  String get archiveDeleteFailed;

  /// No description provided for @archiveSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get archiveSelectAll;

  /// No description provided for @archiveSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String archiveSelectedCount(int count);

  /// No description provided for @archiveDeleteSelectedTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 print?} other{Delete {count} prints?}}'**
  String archiveDeleteSelectedTitle(int count);

  /// No description provided for @archiveDeleteSelectedBody.
  ///
  /// In en, this message translates to:
  /// **'Remove the selected prints from the archive.'**
  String get archiveDeleteSelectedBody;

  /// No description provided for @archiveDeletedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 print deleted} other{{count} prints deleted}}'**
  String archiveDeletedCount(int count);

  /// No description provided for @archiveDeleteSomeFailed.
  ///
  /// In en, this message translates to:
  /// **'{ok} deleted, {failed} failed'**
  String archiveDeleteSomeFailed(int ok, int failed);

  /// No description provided for @archivePurgeOlder.
  ///
  /// In en, this message translates to:
  /// **'Purge old prints…'**
  String get archivePurgeOlder;

  /// No description provided for @archivePurgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Purge old prints'**
  String get archivePurgeTitle;

  /// No description provided for @archivePurgeOlderThan.
  ///
  /// In en, this message translates to:
  /// **'Older than'**
  String get archivePurgeOlderThan;

  /// No description provided for @archivePurgeDaysOption.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String archivePurgeDaysOption(int days);

  /// No description provided for @archivePurgePreview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 print · {size}} other{{count} prints · {size}}}'**
  String archivePurgePreview(int count, String size);

  /// No description provided for @archivePurgeNothing.
  ///
  /// In en, this message translates to:
  /// **'No prints older than this.'**
  String get archivePurgeNothing;

  /// No description provided for @archivePurgePreviewError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the preview.'**
  String get archivePurgePreviewError;

  /// No description provided for @archivePurgeResult.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No prints purged} =1{1 print purged} other{{count} prints purged}}'**
  String archivePurgeResult(int count);

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

  /// No description provided for @cameraDemoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera preview is not available in demo mode'**
  String get cameraDemoUnavailable;

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

  /// No description provided for @amsSlotFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get amsSlotFilament;

  /// No description provided for @amsLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get amsLoad;

  /// No description provided for @amsUnload.
  ///
  /// In en, this message translates to:
  /// **'Unload'**
  String get amsUnload;

  /// No description provided for @amsRfidReread.
  ///
  /// In en, this message translates to:
  /// **'Re-read tag'**
  String get amsRfidReread;

  /// No description provided for @amsLoadStarted.
  ///
  /// In en, this message translates to:
  /// **'Loading filament…'**
  String get amsLoadStarted;

  /// No description provided for @amsUnloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Unloading filament…'**
  String get amsUnloadStarted;

  /// No description provided for @amsRfidRereadStarted.
  ///
  /// In en, this message translates to:
  /// **'Re-reading the tag…'**
  String get amsRfidRereadStarted;

  /// No description provided for @amsFeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Feed {slot} into which nozzle?'**
  String amsFeedTitle(String slot);

  /// No description provided for @amsFeedPrompt.
  ///
  /// In en, this message translates to:
  /// **'The Filament Track Switch can route this slot to either nozzle, so the printer cannot work out where the filament should go.'**
  String get amsFeedPrompt;

  /// No description provided for @amsFeedAlreadyLoaded.
  ///
  /// In en, this message translates to:
  /// **'already loaded'**
  String get amsFeedAlreadyLoaded;

  /// No description provided for @amsSwitchNotReady.
  ///
  /// In en, this message translates to:
  /// **'The Filament Track Switch is not set up yet. Assign every AMS to an inlet on the printer, then try again.'**
  String get amsSwitchNotReady;

  /// No description provided for @amsUnloadSlotNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'No nozzle is fed from this slot'**
  String get amsUnloadSlotNotLoaded;

  /// No description provided for @amsActionsWhilePrinting.
  ///
  /// In en, this message translates to:
  /// **'Unavailable while the printer is printing'**
  String get amsActionsWhilePrinting;

  /// No description provided for @amsSlotConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure slot'**
  String get amsSlotConfigure;

  /// No description provided for @amsSlotConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Slot configuration'**
  String get amsSlotConfigTitle;

  /// No description provided for @amsSlotConfigSearch.
  ///
  /// In en, this message translates to:
  /// **'Search presets'**
  String get amsSlotConfigSearch;

  /// No description provided for @amsSlotConfigColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get amsSlotConfigColour;

  /// No description provided for @amsSlotConfigApply.
  ///
  /// In en, this message translates to:
  /// **'Write to printer'**
  String get amsSlotConfigApply;

  /// No description provided for @amsSlotConfigStarted.
  ///
  /// In en, this message translates to:
  /// **'Configuring the slot…'**
  String get amsSlotConfigStarted;

  /// No description provided for @amsSlotConfigNameNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Slot configured, but the preset name could not be saved'**
  String get amsSlotConfigNameNotSaved;

  /// No description provided for @amsSlotConfigEmpty.
  ///
  /// In en, this message translates to:
  /// **'No filament presets available'**
  String get amsSlotConfigEmpty;

  /// No description provided for @amsSlotConfigNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No preset matches the search'**
  String get amsSlotConfigNoMatch;

  /// No description provided for @amsSlotConfigCloudHint.
  ///
  /// In en, this message translates to:
  /// **'Log in to Bambu Cloud to pick from your own presets.'**
  String get amsSlotConfigCloudHint;

  /// No description provided for @amsSlotConfigCloudAction.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get amsSlotConfigCloudAction;

  /// No description provided for @amsSlotConfigTierLocal.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get amsSlotConfigTierLocal;

  /// No description provided for @amsSlotConfigTierCloud.
  ///
  /// In en, this message translates to:
  /// **'Bambu Cloud'**
  String get amsSlotConfigTierCloud;

  /// No description provided for @amsSlotConfigTierBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get amsSlotConfigTierBuiltin;

  /// No description provided for @amsSlotConfigOnlyPrinter.
  ///
  /// In en, this message translates to:
  /// **'Only for {model}'**
  String amsSlotConfigOnlyPrinter(String model);

  /// No description provided for @amsSlotConfigOnlyPrinterHiding.
  ///
  /// In en, this message translates to:
  /// **'Only for {model} ({hidden} hidden)'**
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden);

  /// No description provided for @amsSlotConfigModelUnknown.
  ///
  /// In en, this message translates to:
  /// **'Printer model unknown — showing every preset'**
  String get amsSlotConfigModelUnknown;

  /// No description provided for @amsSlotConfigCurrent.
  ///
  /// In en, this message translates to:
  /// **'Currently set'**
  String get amsSlotConfigCurrent;

  /// No description provided for @amsSlotConfigKProfile.
  ///
  /// In en, this message translates to:
  /// **'K profile'**
  String get amsSlotConfigKProfile;

  /// No description provided for @amsSlotConfigKProfileDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (K {value})'**
  String amsSlotConfigKProfileDefault(String value);

  /// No description provided for @amsSlotConfigKProfileOther.
  ///
  /// In en, this message translates to:
  /// **'Other profiles'**
  String get amsSlotConfigKProfileOther;

  /// No description provided for @amsSlotConfigKProfileNone.
  ///
  /// In en, this message translates to:
  /// **'This printer has no stored K profiles for this nozzle'**
  String get amsSlotConfigKProfileNone;

  /// No description provided for @amsSlotConfigKProfileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the printer\'s K profiles'**
  String get amsSlotConfigKProfileUnavailable;

  /// No description provided for @amsSlotConfigNozzleGuess.
  ///
  /// In en, this message translates to:
  /// **'The printer did not report its nozzle size — assuming {diameter} mm'**
  String amsSlotConfigNozzleGuess(String diameter);

  /// No description provided for @amsSlotConfigKProfileValue.
  ///
  /// In en, this message translates to:
  /// **'K {value}'**
  String amsSlotConfigKProfileValue(String value);

  /// No description provided for @amsSlotConfigColourCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Catalogue colours'**
  String get amsSlotConfigColourCatalogue;

  /// No description provided for @amsSlotConfigColourCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom colour'**
  String get amsSlotConfigColourCustom;

  /// No description provided for @amsSlotReset.
  ///
  /// In en, this message translates to:
  /// **'Clear slot'**
  String get amsSlotReset;

  /// No description provided for @amsSlotResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear this slot?'**
  String get amsSlotResetConfirmTitle;

  /// No description provided for @amsSlotResetConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The printer forgets the filament configured here, and bambuddy forgets which preset it was.'**
  String get amsSlotResetConfirmMessage;

  /// No description provided for @amsSlotResetStarted.
  ///
  /// In en, this message translates to:
  /// **'Clearing the slot…'**
  String get amsSlotResetStarted;

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

  /// No description provided for @amsHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'{ams} history'**
  String amsHistoryTitle(String ams);

  /// No description provided for @amsHistoryHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get amsHistoryHumidity;

  /// No description provided for @amsHistoryTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get amsHistoryTemperature;

  /// No description provided for @sensorHistoryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get sensorHistoryCurrent;

  /// No description provided for @sensorHistoryAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get sensorHistoryAverage;

  /// No description provided for @sensorHistoryMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get sensorHistoryMin;

  /// No description provided for @sensorHistoryMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get sensorHistoryMax;

  /// No description provided for @sensorHistoryRange6h.
  ///
  /// In en, this message translates to:
  /// **'6h'**
  String get sensorHistoryRange6h;

  /// No description provided for @sensorHistoryRange24h.
  ///
  /// In en, this message translates to:
  /// **'24h'**
  String get sensorHistoryRange24h;

  /// No description provided for @sensorHistoryRange48h.
  ///
  /// In en, this message translates to:
  /// **'48h'**
  String get sensorHistoryRange48h;

  /// No description provided for @sensorHistoryRange7d.
  ///
  /// In en, this message translates to:
  /// **'7d'**
  String get sensorHistoryRange7d;

  /// No description provided for @amsHistoryGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get amsHistoryGood;

  /// No description provided for @amsHistoryFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get amsHistoryFair;

  /// No description provided for @sensorHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No data for this range'**
  String get sensorHistoryEmpty;

  /// No description provided for @sensorHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load history'**
  String get sensorHistoryError;

  /// No description provided for @amsHistoryRecordingInfo.
  ///
  /// In en, this message translates to:
  /// **'Recorded every 5 minutes while the printer is connected'**
  String get amsHistoryRecordingInfo;

  /// No description provided for @heaterHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Temperature history'**
  String get heaterHistoryTitle;

  /// No description provided for @heaterHistoryOpen.
  ///
  /// In en, this message translates to:
  /// **'Temperature history'**
  String get heaterHistoryOpen;

  /// No description provided for @heaterHistoryReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get heaterHistoryReading;

  /// No description provided for @heaterHistoryTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get heaterHistoryTarget;

  /// No description provided for @heaterHistoryRecordingInfo.
  ///
  /// In en, this message translates to:
  /// **'Recorded every minute while the printer is connected'**
  String get heaterHistoryRecordingInfo;

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

  /// No description provided for @widgetNoPrinter.
  ///
  /// In en, this message translates to:
  /// **'No printer'**
  String get widgetNoPrinter;

  /// No description provided for @widgetStatusPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get widgetStatusPrinting;

  /// No description provided for @widgetStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get widgetStatusPaused;

  /// No description provided for @widgetStatusFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get widgetStatusFinished;

  /// No description provided for @widgetStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get widgetStatusFailed;

  /// No description provided for @widgetStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get widgetStatusIdle;

  /// No description provided for @widgetStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get widgetStatusOffline;

  /// No description provided for @widgetStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get widgetStatusError;

  /// No description provided for @widgetMultiTitle.
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get widgetMultiTitle;

  /// No description provided for @widgetMultiActive.
  ///
  /// In en, this message translates to:
  /// **'{active}/{total} active'**
  String widgetMultiActive(int active, int total);

  /// No description provided for @widgetMultiMore.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String widgetMultiMore(int count);

  /// No description provided for @widgetMultiGaugeLabel.
  ///
  /// In en, this message translates to:
  /// **'printing'**
  String get widgetMultiGaugeLabel;

  /// No description provided for @widgetMultiIdleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} idle'**
  String widgetMultiIdleCount(int count);

  /// No description provided for @widgetMultiOfflineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} offline'**
  String widgetMultiOfflineCount(int count);

  /// No description provided for @widgetMultiName.
  ///
  /// In en, this message translates to:
  /// **'Bambuddy · Printers'**
  String get widgetMultiName;

  /// No description provided for @widgetMultiDescription.
  ///
  /// In en, this message translates to:
  /// **'All printers at a glance'**
  String get widgetMultiDescription;

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
  /// **'{minutes}min'**
  String durationMinutes(int minutes);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}min'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String durationHours(int hours);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String durationSeconds(int seconds);

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

  /// Heading of the second login step, shown after the server answered requires_2fa
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get twoFactorTitle;

  /// No description provided for @twoFactorMethodTotp.
  ///
  /// In en, this message translates to:
  /// **'Authenticator'**
  String get twoFactorMethodTotp;

  /// No description provided for @twoFactorMethodEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get twoFactorMethodEmail;

  /// No description provided for @twoFactorMethodBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup code'**
  String get twoFactorMethodBackup;

  /// No description provided for @twoFactorExplainTotp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app.'**
  String get twoFactorExplainTotp;

  /// No description provided for @twoFactorExplainEmail.
  ///
  /// In en, this message translates to:
  /// **'Have the server e-mail you a 6-digit code, then enter it here.'**
  String get twoFactorExplainEmail;

  /// No description provided for @twoFactorExplainEmailSent.
  ///
  /// In en, this message translates to:
  /// **'A 6-digit code has been sent to the address on your account. It expires in 10 minutes.'**
  String get twoFactorExplainEmailSent;

  /// No description provided for @twoFactorExplainBackup.
  ///
  /// In en, this message translates to:
  /// **'Enter one of the 8-character backup codes you saved when setting up 2FA. Each one works once.'**
  String get twoFactorExplainBackup;

  /// No description provided for @twoFactorCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get twoFactorCodeLabel;

  /// No description provided for @twoFactorSendEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail me a code'**
  String get twoFactorSendEmail;

  /// No description provided for @twoFactorResendEmail.
  ///
  /// In en, this message translates to:
  /// **'Send another code'**
  String get twoFactorResendEmail;

  /// No description provided for @twoFactorVerify.
  ///
  /// In en, this message translates to:
  /// **'Confirm and connect'**
  String get twoFactorVerify;

  /// No description provided for @twoFactorBack.
  ///
  /// In en, this message translates to:
  /// **'Use a different account'**
  String get twoFactorBack;

  /// Why remember-me does nothing for a 2FA account; shown under the code field
  ///
  /// In en, this message translates to:
  /// **'The app cannot renew a 2FA session on its own, so it will ask again when this one expires. An API key does not expire and skips this step.'**
  String get twoFactorSessionNote;

  /// No description provided for @tryDemo.
  ///
  /// In en, this message translates to:
  /// **'Try the demo'**
  String get tryDemo;

  /// No description provided for @scanApiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan API key'**
  String get scanApiKeyTitle;

  /// No description provided for @scanApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the API key QR code'**
  String get scanApiKeyHint;

  /// No description provided for @cameraPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access needed'**
  String get cameraPermissionTitle;

  /// No description provided for @cameraPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access to scan QR codes.'**
  String get cameraPermissionBody;

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
  /// **'Not allowed — the server refused this action'**
  String get errForbidden;

  /// No description provided for @errForbiddenDetail.
  ///
  /// In en, this message translates to:
  /// **'Not allowed: {reason}'**
  String errForbiddenDetail(String reason);

  /// No description provided for @errApiKeyOwnerDisabled.
  ///
  /// In en, this message translates to:
  /// **'The account that owns this API key has been deactivated or deleted — the key stays refused until that account is restored.'**
  String get errApiKeyOwnerDisabled;

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

  /// No description provided for @errTwoFactorCodeRejected.
  ///
  /// In en, this message translates to:
  /// **'Wrong code — check it and try again.'**
  String get errTwoFactorCodeRejected;

  /// No description provided for @errTwoFactorChallengeExpired.
  ///
  /// In en, this message translates to:
  /// **'The sign-in attempt expired — enter your password again to get a new code.'**
  String get errTwoFactorChallengeExpired;

  /// No description provided for @errTwoFactorMethodUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That method is not available on this account — pick another one.'**
  String get errTwoFactorMethodUnavailable;

  /// No description provided for @errTwoFactorEmailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The server could not send the code — it has no e-mail set up, or your account has no address. Use another method.'**
  String get errTwoFactorEmailUnavailable;

  /// No description provided for @errMissingTwoFactorCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get errMissingTwoFactorCode;

  /// No description provided for @errApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'API key rejected — check the key and its scope (can_read_status required)'**
  String get errApiKeyRejected;

  /// No description provided for @errTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts — the server is blocking sign-in for a few minutes. Wait and try again, or use an API key.'**
  String get errTooManyAttempts;

  /// No description provided for @errSlotTagUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This slot has no readable RFID tag — Spoolman binds spools by tag, so it cannot take this one. The built-in inventory assigns by slot instead.'**
  String get errSlotTagUnreadable;

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

  /// No description provided for @notifMasterTitle.
  ///
  /// In en, this message translates to:
  /// **'Event notifications'**
  String get notifMasterTitle;

  /// No description provided for @notifMasterDesc.
  ///
  /// In en, this message translates to:
  /// **'Turn off to silence all alerts. The ongoing print-progress notification stays.'**
  String get notifMasterDesc;

  /// No description provided for @notifEventsHeader.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get notifEventsHeader;

  /// No description provided for @notifExtrasHeader.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get notifExtrasHeader;

  /// No description provided for @notifFinishPhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo of the finished print'**
  String get notifFinishPhotoTitle;

  /// No description provided for @notifFinishPhotoDesc.
  ///
  /// In en, this message translates to:
  /// **'Adds the shot the server takes when a print ends to the finished/failed notification, once it arrives'**
  String get notifFinishPhotoDesc;

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

  /// No description provided for @hmsErrorsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 error} other{{count} errors}}'**
  String hmsErrorsCount(int count);

  /// No description provided for @hmsDismissAll.
  ///
  /// In en, this message translates to:
  /// **'Dismiss all'**
  String get hmsDismissAll;

  /// No description provided for @hmsDismissed.
  ///
  /// In en, this message translates to:
  /// **'Errors cleared on the printer'**
  String get hmsDismissed;

  /// No description provided for @hmsDismissFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the errors'**
  String get hmsDismissFailed;

  /// No description provided for @hmsActionSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to the printer'**
  String get hmsActionSent;

  /// No description provided for @hmsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'The printer refused the action'**
  String get hmsActionFailed;

  /// No description provided for @hmsActionNotAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'The printer did not confirm the action — check its screen'**
  String get hmsActionNotAcknowledged;

  /// No description provided for @hmsStopConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop the print?'**
  String get hmsStopConfirmTitle;

  /// No description provided for @hmsStopConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{printer} will abandon the print job. This cannot be undone.'**
  String hmsStopConfirmBody(String printer);

  /// No description provided for @hmsStopConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Stop printing'**
  String get hmsStopConfirmAction;

  /// No description provided for @hmsActionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get hmsActionResume;

  /// No description provided for @hmsActionResumeDefects.
  ///
  /// In en, this message translates to:
  /// **'Resume anyway'**
  String get hmsActionResumeDefects;

  /// No description provided for @hmsActionResumeSolved.
  ///
  /// In en, this message translates to:
  /// **'Fixed, resume'**
  String get hmsActionResumeSolved;

  /// No description provided for @hmsActionProblemSolvedResume.
  ///
  /// In en, this message translates to:
  /// **'Fixed, resume'**
  String get hmsActionProblemSolvedResume;

  /// No description provided for @hmsActionFilamentLoadedResume.
  ///
  /// In en, this message translates to:
  /// **'Loaded, resume'**
  String get hmsActionFilamentLoadedResume;

  /// No description provided for @hmsActionProceed.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get hmsActionProceed;

  /// No description provided for @hmsActionStopPrinting.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get hmsActionStopPrinting;

  /// No description provided for @hmsActionIgnoreResume.
  ///
  /// In en, this message translates to:
  /// **'Ignore, resume'**
  String get hmsActionIgnoreResume;

  /// No description provided for @hmsActionIgnoreNoReminder.
  ///
  /// In en, this message translates to:
  /// **'Ignore always'**
  String get hmsActionIgnoreNoReminder;

  /// No description provided for @hmsActionDontRemind.
  ///
  /// In en, this message translates to:
  /// **'Don\'t remind'**
  String get hmsActionDontRemind;

  /// No description provided for @hmsActionNoReminder.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get hmsActionNoReminder;

  /// No description provided for @hmsActionFilamentExtruded.
  ///
  /// In en, this message translates to:
  /// **'Extruded'**
  String get hmsActionFilamentExtruded;

  /// No description provided for @hmsActionRetryFilamentExtruded.
  ///
  /// In en, this message translates to:
  /// **'Not yet, retry'**
  String get hmsActionRetryFilamentExtruded;

  /// No description provided for @hmsActionContinue.
  ///
  /// In en, this message translates to:
  /// **'Done, continue'**
  String get hmsActionContinue;

  /// No description provided for @hmsActionRetrySolved.
  ///
  /// In en, this message translates to:
  /// **'Fixed, retry'**
  String get hmsActionRetrySolved;

  /// No description provided for @hmsActionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get hmsActionDone;

  /// No description provided for @hmsActionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get hmsActionRetry;

  /// No description provided for @hmsActionResumePlain.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get hmsActionResumePlain;

  /// No description provided for @hmsActionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get hmsActionConfirm;

  /// No description provided for @hmsActionAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get hmsActionAbort;

  /// No description provided for @hmsActionOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get hmsActionOk;

  /// No description provided for @hmsActionRecheck.
  ///
  /// In en, this message translates to:
  /// **'Recheck'**
  String get hmsActionRecheck;

  /// No description provided for @hmsActionTurnOffFireAlarm.
  ///
  /// In en, this message translates to:
  /// **'Turn off alarm'**
  String get hmsActionTurnOffFireAlarm;

  /// No description provided for @hmsActionStopDrying.
  ///
  /// In en, this message translates to:
  /// **'Stop drying'**
  String get hmsActionStopDrying;

  /// No description provided for @hmsActionDisablePurification.
  ///
  /// In en, this message translates to:
  /// **'Disable purification'**
  String get hmsActionDisablePurification;

  /// No description provided for @batteryOptTitle.
  ///
  /// In en, this message translates to:
  /// **'Reliable background notifications'**
  String get batteryOptTitle;

  /// No description provided for @batteryOptBody.
  ///
  /// In en, this message translates to:
  /// **'To keep print notifications working when the app is in the background, allow Bambuddy to run without battery restrictions. On Samsung phones this is essential.'**
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
  /// **'Bambuddy'**
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

  /// Bottom nav tab: printers overview
  ///
  /// In en, this message translates to:
  /// **'Printers'**
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

  /// No description provided for @inventoryTotalConsumed.
  ///
  /// In en, this message translates to:
  /// **'{weight} consumed'**
  String inventoryTotalConsumed(String weight);

  /// No description provided for @inventoryConsumedSinceReset.
  ///
  /// In en, this message translates to:
  /// **'Consumed since reset: {weight}'**
  String inventoryConsumedSinceReset(String weight);

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

  /// No description provided for @inventoryId.
  ///
  /// In en, this message translates to:
  /// **'Filament ID'**
  String get inventoryId;

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

  /// No description provided for @inventoryAddSpool.
  ///
  /// In en, this message translates to:
  /// **'Add spool'**
  String get inventoryAddSpool;

  /// No description provided for @inventoryAddSpools.
  ///
  /// In en, this message translates to:
  /// **'Add {count} {count, plural, one{spool} other{spools}}'**
  String inventoryAddSpools(int count);

  /// No description provided for @inventoryNewSpool.
  ///
  /// In en, this message translates to:
  /// **'New spool'**
  String get inventoryNewSpool;

  /// No description provided for @inventoryEditSpool.
  ///
  /// In en, this message translates to:
  /// **'Edit spool'**
  String get inventoryEditSpool;

  /// No description provided for @inventorySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get inventorySave;

  /// No description provided for @inventoryFieldQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get inventoryFieldQuantity;

  /// No description provided for @inventoryQuantityHint.
  ///
  /// In en, this message translates to:
  /// **'Create several identical spools at once'**
  String get inventoryQuantityHint;

  /// No description provided for @inventoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get inventoryEdit;

  /// No description provided for @inventoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get inventoryDelete;

  /// No description provided for @inventoryArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get inventoryArchive;

  /// No description provided for @inventoryRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get inventoryRestore;

  /// No description provided for @inventoryResetUsage.
  ///
  /// In en, this message translates to:
  /// **'Reset usage'**
  String get inventoryResetUsage;

  /// No description provided for @inventoryFieldSlicerPreset.
  ///
  /// In en, this message translates to:
  /// **'Slicer preset'**
  String get inventoryFieldSlicerPreset;

  /// No description provided for @inventorySlicerPresetHint.
  ///
  /// In en, this message translates to:
  /// **'Print profile this spool is added with'**
  String get inventorySlicerPresetHint;

  /// No description provided for @inventorySlicerPresetNone.
  ///
  /// In en, this message translates to:
  /// **'No preset'**
  String get inventorySlicerPresetNone;

  /// No description provided for @inventorySlicerPresetSearch.
  ///
  /// In en, this message translates to:
  /// **'Search presets…'**
  String get inventorySlicerPresetSearch;

  /// No description provided for @inventorySlicerPresetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No slicer presets available. Enable slicing on the server (and connect Bambu Cloud for cloud presets).'**
  String get inventorySlicerPresetUnavailable;

  /// No description provided for @inventorySectionPrinterPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets per printer model'**
  String get inventorySectionPrinterPresets;

  /// No description provided for @inventoryPrinterPresetsHint.
  ///
  /// In en, this message translates to:
  /// **'A pick here wins over the spool\'s own preset.'**
  String get inventoryPrinterPresetsHint;

  /// No description provided for @inventoryPrinterPresetDefault.
  ///
  /// In en, this message translates to:
  /// **'As on the spool'**
  String get inventoryPrinterPresetDefault;

  /// Label of a per-model preset row that applies to one nozzle size only. Written by the web spool form; the app writes rows that cover the whole model.
  ///
  /// In en, this message translates to:
  /// **'{model} · {diameter} nozzle'**
  String inventoryPrinterPresetNozzle(String model, String diameter);

  /// No description provided for @inventoryPrinterPresetsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Not read — saving leaves them alone.'**
  String get inventoryPrinterPresetsLoadFailed;

  /// No description provided for @inventoryPrinterPresetsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Spool saved, its per-model presets were not.'**
  String get inventoryPrinterPresetsSaveFailed;

  /// No description provided for @inventoryFieldMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get inventoryFieldMaterial;

  /// No description provided for @inventoryFieldBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get inventoryFieldBrand;

  /// No description provided for @inventoryFieldSubtype.
  ///
  /// In en, this message translates to:
  /// **'Variant'**
  String get inventoryFieldSubtype;

  /// No description provided for @inventoryFieldColorName.
  ///
  /// In en, this message translates to:
  /// **'Color name'**
  String get inventoryFieldColorName;

  /// No description provided for @inventoryFieldColorHex.
  ///
  /// In en, this message translates to:
  /// **'Color (hex)'**
  String get inventoryFieldColorHex;

  /// No description provided for @inventoryFieldLabelWeight.
  ///
  /// In en, this message translates to:
  /// **'Spool weight (g)'**
  String get inventoryFieldLabelWeight;

  /// No description provided for @inventoryFieldWeightUsed.
  ///
  /// In en, this message translates to:
  /// **'Used (g)'**
  String get inventoryFieldWeightUsed;

  /// No description provided for @inventoryFieldCostPerKg.
  ///
  /// In en, this message translates to:
  /// **'Cost per kg'**
  String get inventoryFieldCostPerKg;

  /// No description provided for @inventoryFieldLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low-stock threshold (%)'**
  String get inventoryFieldLowStock;

  /// No description provided for @inventoryFieldLocation.
  ///
  /// In en, this message translates to:
  /// **'Storage location'**
  String get inventoryFieldLocation;

  /// No description provided for @inventoryFieldNozzleMin.
  ///
  /// In en, this message translates to:
  /// **'Nozzle min (°C)'**
  String get inventoryFieldNozzleMin;

  /// No description provided for @inventoryFieldNozzleMax.
  ///
  /// In en, this message translates to:
  /// **'Nozzle max (°C)'**
  String get inventoryFieldNozzleMax;

  /// No description provided for @inventoryFieldNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get inventoryFieldNote;

  /// No description provided for @inventoryFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get inventoryFieldRequired;

  /// No description provided for @inventoryFieldInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get inventoryFieldInvalidNumber;

  /// No description provided for @inventoryFieldRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max}'**
  String inventoryFieldRange(int min, int max);

  /// Numeric inventory fields with no explicit range. The server stores a negative core weight without complaint and it corrupts every remaining-weight sum built on it, so the refusal has to happen here.
  ///
  /// In en, this message translates to:
  /// **'Enter a value of 0 or more'**
  String get inventoryFieldNegative;

  /// No description provided for @inventorySectionBasics.
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get inventorySectionBasics;

  /// No description provided for @inventorySectionWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight & cost'**
  String get inventorySectionWeight;

  /// No description provided for @inventorySectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get inventorySectionDetails;

  /// No description provided for @inventorySectionFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get inventorySectionFilament;

  /// No description provided for @inventorySectionColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get inventorySectionColor;

  /// No description provided for @inventorySectionAdditional.
  ///
  /// In en, this message translates to:
  /// **'Additional'**
  String get inventorySectionAdditional;

  /// No description provided for @inventoryFieldEmptySpoolWeight.
  ///
  /// In en, this message translates to:
  /// **'Empty spool weight (g)'**
  String get inventoryFieldEmptySpoolWeight;

  /// No description provided for @inventoryCoreWeightSelect.
  ///
  /// In en, this message translates to:
  /// **'Select…'**
  String get inventoryCoreWeightSelect;

  /// No description provided for @inventoryCoreWeightSearch.
  ///
  /// In en, this message translates to:
  /// **'Search spools…'**
  String get inventoryCoreWeightSearch;

  /// No description provided for @inventoryFieldRemainingWeight.
  ///
  /// In en, this message translates to:
  /// **'Remaining weight (g)'**
  String get inventoryFieldRemainingWeight;

  /// No description provided for @inventoryFieldMeasuredWeight.
  ///
  /// In en, this message translates to:
  /// **'Measured weight (g)'**
  String get inventoryFieldMeasuredWeight;

  /// No description provided for @inventoryFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get inventoryFieldCategory;

  /// No description provided for @inventoryFieldExtraColors.
  ///
  /// In en, this message translates to:
  /// **'Extra colors'**
  String get inventoryFieldExtraColors;

  /// No description provided for @inventoryExtraColorsHint.
  ///
  /// In en, this message translates to:
  /// **'2–8 hex stops, comma-separated'**
  String get inventoryExtraColorsHint;

  /// No description provided for @inventoryFieldEffect.
  ///
  /// In en, this message translates to:
  /// **'Effect'**
  String get inventoryFieldEffect;

  /// No description provided for @inventoryEffectNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get inventoryEffectNone;

  /// No description provided for @inventoryColorCommon.
  ///
  /// In en, this message translates to:
  /// **'Common colors'**
  String get inventoryColorCommon;

  /// No description provided for @inventoryColorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search colors…'**
  String get inventoryColorSearchHint;

  /// No description provided for @inventoryColorPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a color'**
  String get inventoryColorPickTitle;

  /// No description provided for @inventoryColorSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get inventoryColorSelect;

  /// No description provided for @inventoryColorNone.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get inventoryColorNone;

  /// No description provided for @inventoryLowStockHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the global threshold'**
  String get inventoryLowStockHint;

  /// No description provided for @inventoryRemainingOfLabel.
  ///
  /// In en, this message translates to:
  /// **'of {total} g'**
  String inventoryRemainingOfLabel(int total);

  /// No description provided for @inventoryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete spool?'**
  String get inventoryDeleteTitle;

  /// No description provided for @inventoryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {name}? This cannot be undone.'**
  String inventoryDeleteConfirm(String name);

  /// No description provided for @inventoryResetUsageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset the consumed-filament counter to zero? Future prints count from zero again — the remaining weight is not changed.'**
  String get inventoryResetUsageConfirm;

  /// No description provided for @inventorySpoolCreated.
  ///
  /// In en, this message translates to:
  /// **'Spool added'**
  String get inventorySpoolCreated;

  /// No description provided for @inventorySpoolsCreated.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{spool} other{spools}} added'**
  String inventorySpoolsCreated(int count);

  /// No description provided for @inventorySpoolUpdated.
  ///
  /// In en, this message translates to:
  /// **'Spool updated'**
  String get inventorySpoolUpdated;

  /// No description provided for @inventorySpoolDeleted.
  ///
  /// In en, this message translates to:
  /// **'Spool deleted'**
  String get inventorySpoolDeleted;

  /// No description provided for @inventorySpoolArchived.
  ///
  /// In en, this message translates to:
  /// **'Spool archived'**
  String get inventorySpoolArchived;

  /// No description provided for @inventorySpoolRestored.
  ///
  /// In en, this message translates to:
  /// **'Spool restored'**
  String get inventorySpoolRestored;

  /// No description provided for @inventoryUsageReset.
  ///
  /// In en, this message translates to:
  /// **'Counter reset'**
  String get inventoryUsageReset;

  /// No description provided for @inventorySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save spool'**
  String get inventorySaveFailed;

  /// No description provided for @inventoryActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get inventoryActionFailed;

  /// No description provided for @inventoryUnassign.
  ///
  /// In en, this message translates to:
  /// **'Unassign'**
  String get inventoryUnassign;

  /// No description provided for @inventoryAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign to slot'**
  String get inventoryAssign;

  /// No description provided for @inventoryAssignPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get inventoryAssignPrinter;

  /// No description provided for @inventoryAssignNoPrinters.
  ///
  /// In en, this message translates to:
  /// **'No printers available'**
  String get inventoryAssignNoPrinters;

  /// No description provided for @inventorySlotAms.
  ///
  /// In en, this message translates to:
  /// **'AMS slot'**
  String get inventorySlotAms;

  /// No description provided for @inventoryAssignUnit.
  ///
  /// In en, this message translates to:
  /// **'AMS unit'**
  String get inventoryAssignUnit;

  /// No description provided for @inventoryAssignSlot.
  ///
  /// In en, this message translates to:
  /// **'Slot'**
  String get inventoryAssignSlot;

  /// No description provided for @inventoryAssignExtruder.
  ///
  /// In en, this message translates to:
  /// **'Extruder'**
  String get inventoryAssignExtruder;

  /// No description provided for @inventoryAssignExternalHint.
  ///
  /// In en, this message translates to:
  /// **'Assigns to the external spool holder'**
  String get inventoryAssignExternalHint;

  /// No description provided for @inventoryAssignConfirm.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get inventoryAssignConfirm;

  /// No description provided for @inventoryAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign spool'**
  String get inventoryAssignTitle;

  /// No description provided for @inventoryAssignCurrent.
  ///
  /// In en, this message translates to:
  /// **'Currently in this slot'**
  String get inventoryAssignCurrent;

  /// No description provided for @inventoryAssignPick.
  ///
  /// In en, this message translates to:
  /// **'Pick a spool'**
  String get inventoryAssignPick;

  /// No description provided for @inventoryReassignTitle.
  ///
  /// In en, this message translates to:
  /// **'Move spool?'**
  String get inventoryReassignTitle;

  /// No description provided for @inventoryReassignMessage.
  ///
  /// In en, this message translates to:
  /// **'This spool is currently in {slot}. It will be removed from there and assigned to this slot.'**
  String inventoryReassignMessage(String slot);

  /// No description provided for @inventoryReassignAction.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get inventoryReassignAction;

  /// No description provided for @inventorySpoolAssigned.
  ///
  /// In en, this message translates to:
  /// **'Spool assigned'**
  String get inventorySpoolAssigned;

  /// No description provided for @inventorySpoolUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Spool unassigned'**
  String get inventorySpoolUnassigned;

  /// No description provided for @inventoryFromSlot.
  ///
  /// In en, this message translates to:
  /// **'Add to inventory'**
  String get inventoryFromSlot;

  /// No description provided for @inventoryFromSlotHint.
  ///
  /// In en, this message translates to:
  /// **'Register the tagged spool the printer reports in this slot'**
  String get inventoryFromSlotHint;

  /// No description provided for @inventoryFromSlotDone.
  ///
  /// In en, this message translates to:
  /// **'Spool added and assigned to the slot'**
  String get inventoryFromSlotDone;

  /// No description provided for @inventoryFromSlotNoTag.
  ///
  /// In en, this message translates to:
  /// **'The printer no longer reports a tagged spool in this slot'**
  String get inventoryFromSlotNoTag;

  /// No description provided for @inventoryFromSlotOffline.
  ///
  /// In en, this message translates to:
  /// **'The printer is not connected, so it cannot say what is in the slot'**
  String get inventoryFromSlotOffline;

  /// No description provided for @inventoryFromSlotUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server version cannot add a spool straight from a slot'**
  String get inventoryFromSlotUnsupported;

  /// No description provided for @inventoryScanSpool.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get inventoryScanSpool;

  /// No description provided for @inventoryScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan spool QR'**
  String get inventoryScanTitle;

  /// No description provided for @inventoryScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the spool\'s QR code'**
  String get inventoryScanHint;

  /// No description provided for @inventoryScanPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access needed'**
  String get inventoryScanPermissionTitle;

  /// No description provided for @inventoryScanPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access to scan spool QR codes.'**
  String get inventoryScanPermissionBody;

  /// No description provided for @inventoryScanOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get inventoryScanOpenSettings;

  /// No description provided for @inventoryScanInvalid.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized QR code'**
  String get inventoryScanInvalid;

  /// No description provided for @inventoryScanNotFound.
  ///
  /// In en, this message translates to:
  /// **'Spool #{id} not found'**
  String inventoryScanNotFound(int id);

  /// No description provided for @inventorySelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String inventorySelectedCount(int count);

  /// No description provided for @inventorySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get inventorySelectAll;

  /// No description provided for @inventoryBulkArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive {count} {count, plural, one{spool} other{spools}}?'**
  String inventoryBulkArchiveTitle(int count);

  /// No description provided for @inventoryBulkArchiveBody.
  ///
  /// In en, this message translates to:
  /// **'They will be hidden from the active list. You can restore them later.'**
  String get inventoryBulkArchiveBody;

  /// No description provided for @inventoryBulkRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore {count} {count, plural, one{spool} other{spools}}?'**
  String inventoryBulkRestoreTitle(int count);

  /// No description provided for @inventoryBulkRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'They will return to the active list.'**
  String get inventoryBulkRestoreBody;

  /// No description provided for @inventoryBulkDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} {count, plural, one{spool} other{spools}}?'**
  String inventoryBulkDeleteTitle(int count);

  /// No description provided for @inventoryBulkDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes them and cannot be undone.'**
  String get inventoryBulkDeleteBody;

  /// No description provided for @inventoryBulkResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset usage on {count} {count, plural, one{spool} other{spools}}?'**
  String inventoryBulkResetTitle(int count);

  /// No description provided for @inventoryBulkResetBody.
  ///
  /// In en, this message translates to:
  /// **'Their consumed-filament counters go back to zero. Remaining weights are not changed.'**
  String get inventoryBulkResetBody;

  /// No description provided for @inventoryBulkDone.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{spool} other{spools}} updated'**
  String inventoryBulkDone(int count);

  /// No description provided for @inventoryBulkPartial.
  ///
  /// In en, this message translates to:
  /// **'{ok} done, {failed} failed'**
  String inventoryBulkPartial(int ok, int failed);

  /// No description provided for @inventoryBulkSkipped.
  ///
  /// In en, this message translates to:
  /// **'{ok} done, {skipped} already there'**
  String inventoryBulkSkipped(int ok, int skipped);

  /// No description provided for @inventoryBulkPartialSkipped.
  ///
  /// In en, this message translates to:
  /// **'{ok} done, {skipped} already there, {failed} failed'**
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed);

  /// No description provided for @inventoryBulkEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit fields'**
  String get inventoryBulkEdit;

  /// No description provided for @inventoryBulkEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {count} {count, plural, one{spool} other{spools}}'**
  String inventoryBulkEditTitle(int count);

  /// No description provided for @inventoryBulkEditHint.
  ///
  /// In en, this message translates to:
  /// **'Only the fields you fill in change. Leave the rest blank.'**
  String get inventoryBulkEditHint;

  /// No description provided for @inventoryBulkEditUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get inventoryBulkEditUnchanged;

  /// No description provided for @inventoryBulkEditApply.
  ///
  /// In en, this message translates to:
  /// **'Apply to {count} {count, plural, one{spool} other{spools}}'**
  String inventoryBulkEditApply(int count);

  /// No description provided for @inventoryBulkEditConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Change {count} {count, plural, one{spool} other{spools}}?'**
  String inventoryBulkEditConfirmTitle(int count);

  /// No description provided for @inventoryBulkEditConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{fields} {fields, plural, one{field} other{fields}} will be overwritten on every selected spool.'**
  String inventoryBulkEditConfirmBody(int fields);

  /// No description provided for @inventoryBulkEditUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server is too old for mass edit. Update bambuddy, or edit the spools one at a time.'**
  String get inventoryBulkEditUnsupported;

  /// No description provided for @inventoryApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get inventoryApply;

  /// No description provided for @inventoryLabelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Print spool labels'**
  String get inventoryLabelsTitle;

  /// No description provided for @inventoryLabelsPrint.
  ///
  /// In en, this message translates to:
  /// **'Print labels'**
  String get inventoryLabelsPrint;

  /// No description provided for @inventoryLabelsPrintAll.
  ///
  /// In en, this message translates to:
  /// **'Print labels for all'**
  String get inventoryLabelsPrintAll;

  /// No description provided for @inventoryClimateTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage conditions'**
  String get inventoryClimateTitle;

  /// No description provided for @inventoryClimateTitleAlerting.
  ///
  /// In en, this message translates to:
  /// **'Storage conditions: outside the alert range'**
  String get inventoryClimateTitleAlerting;

  /// No description provided for @inventoryClimateSource.
  ///
  /// In en, this message translates to:
  /// **'The server reads these from Home Assistant. Sensors are bound to a location in Bambuddy\'s web interface.'**
  String get inventoryClimateSource;

  /// No description provided for @inventoryClimateNoReading.
  ///
  /// In en, this message translates to:
  /// **'no reading'**
  String get inventoryClimateNoReading;

  /// Spoken form of a storage-location sensor pill.
  ///
  /// In en, this message translates to:
  /// **'{name}: {value}'**
  String inventoryClimateReading(String name, String value);

  /// Spoken form of a sensor pill whose reading trips the binding's threshold; the warm colour of the pill says this to everyone else.
  ///
  /// In en, this message translates to:
  /// **'{name}: {value}, outside the alert range'**
  String inventoryClimateReadingAlerting(String name, String value);

  /// Spoken form of a sensor pill showing its last known value because the server could not reach the entity.
  ///
  /// In en, this message translates to:
  /// **'{name}: {value}, sensor unreachable'**
  String inventoryClimateReadingStale(String name, String value);

  /// No description provided for @inventoryLabelsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, brand, or #ID'**
  String get inventoryLabelsSearchHint;

  /// No description provided for @inventoryLabelsPickSpools.
  ///
  /// In en, this message translates to:
  /// **'Pick which spools to print labels for:'**
  String get inventoryLabelsPickSpools;

  /// No description provided for @inventoryLabelsMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material:'**
  String get inventoryLabelsMaterial;

  /// No description provided for @inventoryLabelsAllMaterials.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inventoryLabelsAllMaterials;

  /// No description provided for @inventoryLabelsSort.
  ///
  /// In en, this message translates to:
  /// **'Sort:'**
  String get inventoryLabelsSort;

  /// No description provided for @inventoryLabelsSortById.
  ///
  /// In en, this message translates to:
  /// **'By ID'**
  String get inventoryLabelsSortById;

  /// No description provided for @inventoryLabelsSortByColor.
  ///
  /// In en, this message translates to:
  /// **'By colour'**
  String get inventoryLabelsSortByColor;

  /// No description provided for @inventoryLabelsSelectVisible.
  ///
  /// In en, this message translates to:
  /// **'Select visible'**
  String get inventoryLabelsSelectVisible;

  /// No description provided for @inventoryLabelsDeselectVisible.
  ///
  /// In en, this message translates to:
  /// **'Deselect visible'**
  String get inventoryLabelsDeselectVisible;

  /// No description provided for @inventoryLabelsClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get inventoryLabelsClearAll;

  /// No description provided for @inventoryLabelsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No spools match the current search or filter.'**
  String get inventoryLabelsNoMatches;

  /// No description provided for @inventoryLabelsMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome (black & white printer)'**
  String get inventoryLabelsMonochrome;

  /// No description provided for @inventoryLabelsMonochromeHint.
  ///
  /// In en, this message translates to:
  /// **'Drops the colour swatch and widens the text'**
  String get inventoryLabelsMonochromeHint;

  /// No description provided for @inventoryLabelsShare.
  ///
  /// In en, this message translates to:
  /// **'Share PDF instead of printing'**
  String get inventoryLabelsShare;

  /// No description provided for @inventoryLabelsPickTemplate.
  ///
  /// In en, this message translates to:
  /// **'Pick a label size to print:'**
  String get inventoryLabelsPickTemplate;

  /// No description provided for @inventoryLabelsTooMany.
  ///
  /// In en, this message translates to:
  /// **'Pick at most {max} spools per print'**
  String inventoryLabelsTooMany(int max);

  /// No description provided for @inventoryLabelsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not generate labels'**
  String get inventoryLabelsFailed;

  /// No description provided for @inventoryLabelsAmsSmall.
  ///
  /// In en, this message translates to:
  /// **'AMS holder — small (74 × 33 mm)'**
  String get inventoryLabelsAmsSmall;

  /// No description provided for @inventoryLabelsAmsSmallHint.
  ///
  /// In en, this message translates to:
  /// **'One per page; matches the printable label from MakerWorld model 752566.'**
  String get inventoryLabelsAmsSmallHint;

  /// No description provided for @inventoryLabelsAmsLarge.
  ///
  /// In en, this message translates to:
  /// **'AMS holder — large (75 × 55 mm)'**
  String get inventoryLabelsAmsLarge;

  /// No description provided for @inventoryLabelsAmsLargeHint.
  ///
  /// In en, this message translates to:
  /// **'One per page; fits the cardstock-insert variant of the same holder.'**
  String get inventoryLabelsAmsLargeHint;

  /// No description provided for @inventoryLabelsBox40.
  ///
  /// In en, this message translates to:
  /// **'Box label (40 × 30 mm)'**
  String get inventoryLabelsBox40;

  /// No description provided for @inventoryLabelsBox40Hint.
  ///
  /// In en, this message translates to:
  /// **'One per page; common DK/Brother roll size, good for bags and bins.'**
  String get inventoryLabelsBox40Hint;

  /// No description provided for @inventoryLabelsBox62.
  ///
  /// In en, this message translates to:
  /// **'Box label (62 × 29 mm)'**
  String get inventoryLabelsBox62;

  /// No description provided for @inventoryLabelsBox62Hint.
  ///
  /// In en, this message translates to:
  /// **'One per page; sized for Brother PT/QL and Dymo small labels.'**
  String get inventoryLabelsBox62Hint;

  /// No description provided for @inventoryLabelsAveryL7160.
  ///
  /// In en, this message translates to:
  /// **'Avery L7160 — A4 sheet (38.1 × 63.5 mm × 21)'**
  String get inventoryLabelsAveryL7160;

  /// No description provided for @inventoryLabelsAveryL7160Hint.
  ///
  /// In en, this message translates to:
  /// **'EU sheet stock; 21 labels per A4 page.'**
  String get inventoryLabelsAveryL7160Hint;

  /// No description provided for @inventoryLabelsAvery5160.
  ///
  /// In en, this message translates to:
  /// **'Avery 5160 — US Letter sheet (25.4 × 66.7 mm × 30)'**
  String get inventoryLabelsAvery5160;

  /// No description provided for @inventoryLabelsAvery5160Hint.
  ///
  /// In en, this message translates to:
  /// **'US sheet stock; 30 labels per Letter page.'**
  String get inventoryLabelsAvery5160Hint;

  /// No description provided for @inventoryLabelsStartTitle.
  ///
  /// In en, this message translates to:
  /// **'First free label'**
  String get inventoryLabelsStartTitle;

  /// No description provided for @inventoryLabelsStartHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the slot the first label should print in — the ones before it stay blank, so a part-used sheet gets finished instead of started over.'**
  String get inventoryLabelsStartHint;

  /// No description provided for @inventoryLabelsStartSlot.
  ///
  /// In en, this message translates to:
  /// **'Position {position}'**
  String inventoryLabelsStartSlot(int position);

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

  /// No description provided for @maintenanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get maintenanceSaved;

  /// No description provided for @maintenanceSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance settings'**
  String get maintenanceSettingsTitle;

  /// No description provided for @maintenanceOverridesTitle.
  ///
  /// In en, this message translates to:
  /// **'Interval overrides'**
  String get maintenanceOverridesTitle;

  /// No description provided for @maintenanceOverridesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mute tasks or customize intervals per printer'**
  String get maintenanceOverridesSubtitle;

  /// No description provided for @maintenanceTabStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get maintenanceTabStatus;

  /// No description provided for @maintenanceTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get maintenanceTabSettings;

  /// No description provided for @maintenanceMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get maintenanceMute;

  /// No description provided for @maintenanceUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get maintenanceUnmute;

  /// No description provided for @maintenanceMuted.
  ///
  /// In en, this message translates to:
  /// **'Task muted'**
  String get maintenanceMuted;

  /// No description provided for @maintenanceUnmuted.
  ///
  /// In en, this message translates to:
  /// **'Task unmuted'**
  String get maintenanceUnmuted;

  /// No description provided for @maintenanceEditInterval.
  ///
  /// In en, this message translates to:
  /// **'Edit interval'**
  String get maintenanceEditInterval;

  /// No description provided for @maintenanceResetInterval.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get maintenanceResetInterval;

  /// No description provided for @maintenanceTypesTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance types'**
  String get maintenanceTypesTitle;

  /// No description provided for @maintenanceTypesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System types and your custom tasks'**
  String get maintenanceTypesSubtitle;

  /// No description provided for @maintenanceRestoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get maintenanceRestoreDefaults;

  /// No description provided for @maintenanceRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore all hidden default maintenance types?'**
  String get maintenanceRestoreConfirm;

  /// No description provided for @maintenanceAddType.
  ///
  /// In en, this message translates to:
  /// **'Add custom type'**
  String get maintenanceAddType;

  /// No description provided for @maintenanceEditType.
  ///
  /// In en, this message translates to:
  /// **'Edit type'**
  String get maintenanceEditType;

  /// No description provided for @maintenanceSystemType.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get maintenanceSystemType;

  /// No description provided for @maintenanceEveryHours.
  ///
  /// In en, this message translates to:
  /// **'Every {count} h'**
  String maintenanceEveryHours(int count);

  /// No description provided for @maintenanceEveryDays.
  ///
  /// In en, this message translates to:
  /// **'Every {count} days'**
  String maintenanceEveryDays(int count);

  /// No description provided for @maintenanceDeleteTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete maintenance type?'**
  String get maintenanceDeleteTypeTitle;

  /// No description provided for @maintenanceDeleteTypeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String maintenanceDeleteTypeConfirm(String name);

  /// No description provided for @maintenanceHideTypeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Hide the default type \"{name}\"? You can restore it later.'**
  String maintenanceHideTypeConfirm(String name);

  /// No description provided for @maintenanceFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get maintenanceFieldName;

  /// No description provided for @maintenanceFieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Replace HEPA filter'**
  String get maintenanceFieldNameHint;

  /// No description provided for @maintenanceFieldIntervalType.
  ///
  /// In en, this message translates to:
  /// **'Interval type'**
  String get maintenanceFieldIntervalType;

  /// No description provided for @maintenanceFieldInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get maintenanceFieldInterval;

  /// No description provided for @maintenanceIntervalHours.
  ///
  /// In en, this message translates to:
  /// **'Print hours'**
  String get maintenanceIntervalHours;

  /// No description provided for @maintenanceIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get maintenanceIntervalDays;

  /// No description provided for @maintenanceIntervalInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a value ≥ 1'**
  String get maintenanceIntervalInvalid;

  /// No description provided for @maintenanceFieldIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get maintenanceFieldIcon;

  /// No description provided for @maintenanceFieldDocLink.
  ///
  /// In en, this message translates to:
  /// **'Documentation link (optional)'**
  String get maintenanceFieldDocLink;

  /// No description provided for @maintenanceAssignPrinters.
  ///
  /// In en, this message translates to:
  /// **'Assign to printers'**
  String get maintenanceAssignPrinters;

  /// No description provided for @maintenanceSelectPrinter.
  ///
  /// In en, this message translates to:
  /// **'Select at least one printer'**
  String get maintenanceSelectPrinter;

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

  /// No description provided for @navMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get navMenu;

  /// No description provided for @menuStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get menuStatistics;

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statsTitle;

  /// No description provided for @statsRangeAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get statsRangeAllTime;

  /// No description provided for @statsRangeLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get statsRangeLast7Days;

  /// No description provided for @statsRangeLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get statsRangeLast30Days;

  /// No description provided for @statsRangeLast90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get statsRangeLast90Days;

  /// No description provided for @statsRangeThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get statsRangeThisYear;

  /// No description provided for @statsRangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get statsRangeCustom;

  /// No description provided for @statsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No prints in this period'**
  String get statsEmpty;

  /// No description provided for @statsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load statistics'**
  String get statsLoadFailed;

  /// No description provided for @statsOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get statsOverview;

  /// No description provided for @statsTotalPrints.
  ///
  /// In en, this message translates to:
  /// **'Total prints'**
  String get statsTotalPrints;

  /// No description provided for @statsPrintTime.
  ///
  /// In en, this message translates to:
  /// **'Print time'**
  String get statsPrintTime;

  /// No description provided for @statsFilamentUsed.
  ///
  /// In en, this message translates to:
  /// **'Filament used'**
  String get statsFilamentUsed;

  /// No description provided for @statsFilamentCost.
  ///
  /// In en, this message translates to:
  /// **'Filament cost'**
  String get statsFilamentCost;

  /// No description provided for @statsEnergyUsed.
  ///
  /// In en, this message translates to:
  /// **'Energy used'**
  String get statsEnergyUsed;

  /// No description provided for @statsEnergyCost.
  ///
  /// In en, this message translates to:
  /// **'Energy cost'**
  String get statsEnergyCost;

  /// No description provided for @statsTotalCost.
  ///
  /// In en, this message translates to:
  /// **'Total cost'**
  String get statsTotalCost;

  /// No description provided for @statsEnergyWarmingUp.
  ///
  /// In en, this message translates to:
  /// **'Energy data is still warming up'**
  String get statsEnergyWarmingUp;

  /// No description provided for @statsSuccessRate.
  ///
  /// In en, this message translates to:
  /// **'Success rate'**
  String get statsSuccessRate;

  /// No description provided for @statsSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Successful: {count}'**
  String statsSuccessful(int count);

  /// No description provided for @statsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {count}'**
  String statsFailed(int count);

  /// No description provided for @statsCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: {count}'**
  String statsCancelled(int count);

  /// No description provided for @statsAllUsers.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get statsAllUsers;

  /// No description provided for @statsNoUser.
  ///
  /// In en, this message translates to:
  /// **'No User (System)'**
  String get statsNoUser;

  /// No description provided for @statsTimeAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Time accuracy'**
  String get statsTimeAccuracy;

  /// No description provided for @statsTimeAccuracyHint.
  ///
  /// In en, this message translates to:
  /// **'100% = perfect estimate'**
  String get statsTimeAccuracyHint;

  /// No description provided for @statsByMaterial.
  ///
  /// In en, this message translates to:
  /// **'Prints by material'**
  String get statsByMaterial;

  /// No description provided for @statsByPrinter.
  ///
  /// In en, this message translates to:
  /// **'Prints by printer'**
  String get statsByPrinter;

  /// No description provided for @statsTimeAccuracyByPrinter.
  ///
  /// In en, this message translates to:
  /// **'Time accuracy by printer'**
  String get statsTimeAccuracyByPrinter;

  /// No description provided for @statsPrintsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} print} other{{count} prints}}'**
  String statsPrintsCount(int count);

  /// No description provided for @statsHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String statsHours(String hours);

  /// No description provided for @statsPrinterFallback.
  ///
  /// In en, this message translates to:
  /// **'Printer #{id}'**
  String statsPrinterFallback(String id);

  /// No description provided for @statsMetricWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get statsMetricWeight;

  /// No description provided for @statsMetricPrints.
  ///
  /// In en, this message translates to:
  /// **'Prints'**
  String get statsMetricPrints;

  /// No description provided for @statsMetricTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get statsMetricTime;

  /// No description provided for @statsFailureAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Failure analysis'**
  String get statsFailureAnalysis;

  /// No description provided for @statsFailureRate.
  ///
  /// In en, this message translates to:
  /// **'Failure rate'**
  String get statsFailureRate;

  /// No description provided for @statsFailurePeriod.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String statsFailurePeriod(int days);

  /// No description provided for @statsFailedOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{failed} / {total} prints failed'**
  String statsFailedOfTotal(int failed, int total);

  /// No description provided for @statsTopFailureReasons.
  ///
  /// In en, this message translates to:
  /// **'Top failure reasons'**
  String get statsTopFailureReasons;

  /// No description provided for @statsNoFailures.
  ///
  /// In en, this message translates to:
  /// **'No failures in this period'**
  String get statsNoFailures;

  /// No description provided for @statsPrintActivity.
  ///
  /// In en, this message translates to:
  /// **'Print activity'**
  String get statsPrintActivity;

  /// No description provided for @statsHeatmapLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get statsHeatmapLess;

  /// No description provided for @statsHeatmapMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get statsHeatmapMore;

  /// No description provided for @statsRecords.
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get statsRecords;

  /// No description provided for @statsLongestPrint.
  ///
  /// In en, this message translates to:
  /// **'Longest print'**
  String get statsLongestPrint;

  /// No description provided for @statsHeaviestPrint.
  ///
  /// In en, this message translates to:
  /// **'Heaviest print'**
  String get statsHeaviestPrint;

  /// No description provided for @statsMostExpensive.
  ///
  /// In en, this message translates to:
  /// **'Most expensive'**
  String get statsMostExpensive;

  /// No description provided for @statsBusiestDay.
  ///
  /// In en, this message translates to:
  /// **'Busiest day'**
  String get statsBusiestDay;

  /// No description provided for @statsSuccessStreak.
  ///
  /// In en, this message translates to:
  /// **'Success streak'**
  String get statsSuccessStreak;

  /// No description provided for @statsConsecutive.
  ///
  /// In en, this message translates to:
  /// **'{count} consecutive'**
  String statsConsecutive(int count);

  /// No description provided for @statsFilamentTrends.
  ///
  /// In en, this message translates to:
  /// **'Filament trends'**
  String get statsFilamentTrends;

  /// No description provided for @statsPeriodFilament.
  ///
  /// In en, this message translates to:
  /// **'Period filament'**
  String get statsPeriodFilament;

  /// No description provided for @statsPeriodCost.
  ///
  /// In en, this message translates to:
  /// **'Period cost'**
  String get statsPeriodCost;

  /// No description provided for @statsAvgPerPrint.
  ///
  /// In en, this message translates to:
  /// **'Avg per print'**
  String get statsAvgPerPrint;

  /// No description provided for @statsUsageOverTime.
  ///
  /// In en, this message translates to:
  /// **'Usage over time'**
  String get statsUsageOverTime;

  /// No description provided for @statsEnergyOverTime.
  ///
  /// In en, this message translates to:
  /// **'Energy over time'**
  String get statsEnergyOverTime;

  /// No description provided for @statsMostEnergy.
  ///
  /// In en, this message translates to:
  /// **'Most energy used'**
  String get statsMostEnergy;

  /// No description provided for @statsKwh.
  ///
  /// In en, this message translates to:
  /// **'{value} kWh'**
  String statsKwh(String value);

  /// No description provided for @statsByMaterialTitle.
  ///
  /// In en, this message translates to:
  /// **'By material'**
  String get statsByMaterialTitle;

  /// No description provided for @statsSuccessByMaterial.
  ///
  /// In en, this message translates to:
  /// **'Success by material'**
  String get statsSuccessByMaterial;

  /// No description provided for @statsColorDistribution.
  ///
  /// In en, this message translates to:
  /// **'Color distribution'**
  String get statsColorDistribution;

  /// No description provided for @statsColorShareHint.
  ///
  /// In en, this message translates to:
  /// **'Share of filament used, by weight'**
  String get statsColorShareHint;

  /// No description provided for @statsColorsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{color} other{colors}}'**
  String statsColorsCount(int count);

  /// No description provided for @statsMoreCount.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String statsMoreCount(int count);

  /// No description provided for @statsPrintDuration.
  ///
  /// In en, this message translates to:
  /// **'Print duration'**
  String get statsPrintDuration;

  /// No description provided for @statsPrintHabits.
  ///
  /// In en, this message translates to:
  /// **'Print habits'**
  String get statsPrintHabits;

  /// No description provided for @statsPrintTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Print time of day'**
  String get statsPrintTimeOfDay;

  /// No description provided for @aboutMenu.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutMenu;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Native Android client for bambuddy — a self-hosted Bambu Lab printer manager.'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutLicenseHeader.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicenseHeader;

  /// No description provided for @aboutLicenseBody.
  ///
  /// In en, this message translates to:
  /// **'Bambuddy is free software released under the GNU Affero General Public License v3.0 (AGPL-3.0). You may use, study, share and modify it; if you run a modified version as a network service, you must offer its source to its users.'**
  String get aboutLicenseBody;

  /// No description provided for @aboutViewLicense.
  ///
  /// In en, this message translates to:
  /// **'Read the AGPL-3.0 license'**
  String get aboutViewLicense;

  /// No description provided for @aboutSourceHeader.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceHeader;

  /// No description provided for @aboutSourceBody.
  ///
  /// In en, this message translates to:
  /// **'The full source is available on GitHub.'**
  String get aboutSourceBody;

  /// No description provided for @aboutSourceLink.
  ///
  /// In en, this message translates to:
  /// **'Open source repository'**
  String get aboutSourceLink;

  /// No description provided for @aboutThirdParty.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutThirdParty;

  /// No description provided for @aboutThirdPartySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Licenses of the bundled libraries'**
  String get aboutThirdPartySubtitle;

  /// No description provided for @aboutOpenLinkError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link'**
  String get aboutOpenLinkError;

  /// Drawer entry: File Manager
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get fileManagerMenu;

  /// No description provided for @fileManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get fileManagerTitle;

  /// No description provided for @fmRoot.
  ///
  /// In en, this message translates to:
  /// **'All Files'**
  String get fmRoot;

  /// No description provided for @fmSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files…'**
  String get fmSearchHint;

  /// No description provided for @fmEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get fmEmpty;

  /// No description provided for @fmNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No files match your filters'**
  String get fmNoMatches;

  /// No description provided for @fmSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get fmSortBy;

  /// No description provided for @fmSortDateNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get fmSortDateNewest;

  /// No description provided for @fmSortDateOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get fmSortDateOldest;

  /// No description provided for @fmSortNameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get fmSortNameAZ;

  /// No description provided for @fmSortNameZA.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get fmSortNameZA;

  /// No description provided for @fmSortSizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Largest first'**
  String get fmSortSizeLargest;

  /// No description provided for @fmSortSizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Smallest first'**
  String get fmSortSizeSmallest;

  /// No description provided for @fmFilterType.
  ///
  /// In en, this message translates to:
  /// **'File type'**
  String get fmFilterType;

  /// No description provided for @fmAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get fmAllTypes;

  /// No description provided for @fmNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get fmNewFolder;

  /// No description provided for @fmFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get fmFolderName;

  /// No description provided for @fmFileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fmFileName;

  /// No description provided for @fmSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get fmSave;

  /// No description provided for @fmRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fmRename;

  /// No description provided for @fmRenameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get fmRenameFolder;

  /// No description provided for @fmRenameFile.
  ///
  /// In en, this message translates to:
  /// **'Rename file'**
  String get fmRenameFile;

  /// No description provided for @fmRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get fmRenamed;

  /// No description provided for @fmFolderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created'**
  String get fmFolderCreated;

  /// No description provided for @fmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get fmDelete;

  /// No description provided for @fmDeleted.
  ///
  /// In en, this message translates to:
  /// **'Moved to trash'**
  String get fmDeleted;

  /// No description provided for @fmDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get fmDeleteFile;

  /// No description provided for @fmDeleteFileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to trash?'**
  String fmDeleteFileConfirm(String name);

  /// No description provided for @fmDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get fmDeleteFolder;

  /// No description provided for @fmDeleteFolderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete folder \"{name}\" and all its contents?'**
  String fmDeleteFolderConfirm(String name);

  /// No description provided for @fmDeleteSelectedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move {count} {count, plural, one{file} other{files}} to trash?'**
  String fmDeleteSelectedConfirm(int count);

  /// No description provided for @fmMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get fmMoveTo;

  /// No description provided for @fmMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get fmMoved;

  /// No description provided for @fmFolderItems.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{item} other{items}}'**
  String fmFolderItems(int count);

  /// No description provided for @fmPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get fmPrint;

  /// No description provided for @fmAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get fmAddToQueue;

  /// No description provided for @fmAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get fmAddedToQueue;

  /// No description provided for @fmGroupAsVariants.
  ///
  /// In en, this message translates to:
  /// **'Group as alternatives'**
  String get fmGroupAsVariants;

  /// No description provided for @fmQueueAsVariants.
  ///
  /// In en, this message translates to:
  /// **'Queue as one job'**
  String get fmQueueAsVariants;

  /// No description provided for @fmUngroupVariants.
  ///
  /// In en, this message translates to:
  /// **'Ungroup alternatives'**
  String get fmUngroupVariants;

  /// No description provided for @fmVariantsGrouped.
  ///
  /// In en, this message translates to:
  /// **'{count} files grouped as alternatives'**
  String fmVariantsGrouped(int count);

  /// No description provided for @fmVariantsUngrouped.
  ///
  /// In en, this message translates to:
  /// **'Alternatives ungrouped'**
  String get fmVariantsUngrouped;

  /// No description provided for @fmVariantsMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} alternatives'**
  String fmVariantsMemberCount(int count);

  /// No description provided for @fmVariantsGone.
  ///
  /// In en, this message translates to:
  /// **'This group no longer exists'**
  String get fmVariantsGone;

  /// No description provided for @fmUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get fmUpload;

  /// No description provided for @fmUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get fmUploading;

  /// No description provided for @fmUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded {name}'**
  String fmUploaded(String name);

  /// No description provided for @fmUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get fmUploadFailed;

  /// No description provided for @fmSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String fmSelectedCount(int count);

  /// No description provided for @fmStatsFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{file} other{files}}'**
  String fmStatsFiles(int count);

  /// No description provided for @fmStatsFolders.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{folder} other{folders}}'**
  String fmStatsFolders(int count);

  /// No description provided for @fmStatsFree.
  ///
  /// In en, this message translates to:
  /// **'{size} free'**
  String fmStatsFree(String size);

  /// No description provided for @fmTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get fmTrash;

  /// No description provided for @fmTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get fmTrashTitle;

  /// No description provided for @fmTrashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get fmTrashEmpty;

  /// No description provided for @fmRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get fmRestore;

  /// No description provided for @fmRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get fmRestored;

  /// No description provided for @fmEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get fmEmptyTrash;

  /// No description provided for @fmEmptyTrashConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all files in trash? This cannot be undone.'**
  String get fmEmptyTrashConfirm;

  /// No description provided for @fmHardDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get fmHardDelete;

  /// No description provided for @fmHardDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete \"{name}\"? This cannot be undone.'**
  String fmHardDeleteConfirm(String name);

  /// No description provided for @fmDeletedForever.
  ///
  /// In en, this message translates to:
  /// **'Permanently deleted'**
  String get fmDeletedForever;

  /// No description provided for @fmTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get fmTags;

  /// No description provided for @fmTagsFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter by tags'**
  String get fmTagsFilterTitle;

  /// No description provided for @fmTagsFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Tags search the whole library — the current folder is ignored.'**
  String get fmTagsFilterHint;

  /// No description provided for @fmTagsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage tags'**
  String get fmTagsManage;

  /// No description provided for @fmTagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get fmTagsEmpty;

  /// No description provided for @fmTagsNone.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get fmTagsNone;

  /// No description provided for @fmTagsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get fmTagsApply;

  /// No description provided for @fmTagNew.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get fmTagNew;

  /// No description provided for @fmTagName.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get fmTagName;

  /// No description provided for @fmTagRename.
  ///
  /// In en, this message translates to:
  /// **'Rename tag'**
  String get fmTagRename;

  /// No description provided for @fmTagDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get fmTagDelete;

  /// No description provided for @fmTagDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete tag \"{name}\"? Files keep everything else — they only lose this label.'**
  String fmTagDeleteConfirm(String name);

  /// No description provided for @fmTagCreated.
  ///
  /// In en, this message translates to:
  /// **'Tag created'**
  String get fmTagCreated;

  /// No description provided for @fmTagDeleted.
  ///
  /// In en, this message translates to:
  /// **'Tag deleted'**
  String get fmTagDeleted;

  /// No description provided for @fmTagExists.
  ///
  /// In en, this message translates to:
  /// **'A tag with this name already exists'**
  String get fmTagExists;

  /// No description provided for @fmTagsSaved.
  ///
  /// In en, this message translates to:
  /// **'Tags updated'**
  String get fmTagsSaved;

  /// No description provided for @fmTagsPartial.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} of {total} files — the rest are not yours to edit'**
  String fmTagsPartial(int count, int total);

  /// No description provided for @fmTagsBulkTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag {count} {count, plural, one{file} other{files}}'**
  String fmTagsBulkTitle(int count);

  /// No description provided for @fmTagsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get fmTagsAdd;

  /// No description provided for @fmTagsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get fmTagsRemove;

  /// No description provided for @fmTagsReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get fmTagsReplace;

  /// No description provided for @fmTagsReplaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace all tags on {count} {count, plural, one{file} other{files}} with the selected ones?'**
  String fmTagsReplaceConfirm(int count);

  /// No description provided for @fmTagsPickSome.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one tag'**
  String get fmTagsPickSome;

  /// Drawer entry: MakerWorld import
  ///
  /// In en, this message translates to:
  /// **'MakerWorld'**
  String get makerworldMenu;

  /// No description provided for @makerworldTitle.
  ///
  /// In en, this message translates to:
  /// **'MakerWorld'**
  String get makerworldTitle;

  /// No description provided for @mwIntro.
  ///
  /// In en, this message translates to:
  /// **'Paste a MakerWorld model URL to import and print it directly from Bambuddy.'**
  String get mwIntro;

  /// No description provided for @mwUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://makerworld.com/en/models/… or any MakerWorld link'**
  String get mwUrlHint;

  /// No description provided for @mwResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get mwResolve;

  /// No description provided for @mwEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a MakerWorld URL'**
  String get mwEnterUrl;

  /// No description provided for @mwUntitledModel.
  ///
  /// In en, this message translates to:
  /// **'Untitled model'**
  String get mwUntitledModel;

  /// No description provided for @mwPlatesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No plates} =1{1 plate} other{{count} plates}}'**
  String mwPlatesCount(int count);

  /// No description provided for @mwNoPlates.
  ///
  /// In en, this message translates to:
  /// **'No plates found for this model.'**
  String get mwNoPlates;

  /// No description provided for @mwImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get mwImport;

  /// No description provided for @mwShowAllPlates.
  ///
  /// In en, this message translates to:
  /// **'Show all {count} plates'**
  String mwShowAllPlates(int count);

  /// No description provided for @mwShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get mwShowLess;

  /// No description provided for @mwInLibrary.
  ///
  /// In en, this message translates to:
  /// **'In library'**
  String get mwInLibrary;

  /// No description provided for @mwImported.
  ///
  /// In en, this message translates to:
  /// **'Imported to your library'**
  String get mwImported;

  /// No description provided for @mwAlreadyInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Already in your library'**
  String get mwAlreadyInLibrary;

  /// No description provided for @mwViewInFiles.
  ///
  /// In en, this message translates to:
  /// **'View in File Manager'**
  String get mwViewInFiles;

  /// No description provided for @mwRecentImports.
  ///
  /// In en, this message translates to:
  /// **'Recent imports'**
  String get mwRecentImports;

  /// No description provided for @mwNoRecent.
  ///
  /// In en, this message translates to:
  /// **'No recent imports yet'**
  String get mwNoRecent;

  /// No description provided for @mwOpenOnMakerworld.
  ///
  /// In en, this message translates to:
  /// **'Open on MakerWorld'**
  String get mwOpenOnMakerworld;

  /// No description provided for @mwLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your Bambu Cloud account to download MakerWorld models.'**
  String get mwLoginRequired;

  /// Drawer entry: Bambu Cloud login/account
  ///
  /// In en, this message translates to:
  /// **'Bambu Cloud account'**
  String get cloudAccountMenu;

  /// No description provided for @cloudAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Bambu Cloud'**
  String get cloudAccountTitle;

  /// No description provided for @cloudCredsNote.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Bambu Lab account. These credentials are used only to download models from MakerWorld.'**
  String get cloudCredsNote;

  /// No description provided for @cloudEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get cloudEmail;

  /// No description provided for @cloudPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get cloudPassword;

  /// No description provided for @cloudRegionGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get cloudRegionGlobal;

  /// No description provided for @cloudRegionChina.
  ///
  /// In en, this message translates to:
  /// **'China'**
  String get cloudRegionChina;

  /// No description provided for @cloudSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get cloudSignIn;

  /// No description provided for @cloudSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get cloudSignOut;

  /// No description provided for @cloudSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get cloudSignedIn;

  /// No description provided for @cloudSignedInOk.
  ///
  /// In en, this message translates to:
  /// **'Signed in to Bambu Cloud'**
  String get cloudSignedInOk;

  /// No description provided for @cloudSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get cloudSignInFailed;

  /// No description provided for @cloudFillCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and password'**
  String get cloudFillCredentials;

  /// No description provided for @cloudVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get cloudVerify;

  /// No description provided for @cloudVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get cloudVerificationCode;

  /// No description provided for @cloudVerificationPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code to finish signing in.'**
  String get cloudVerificationPrompt;

  /// No description provided for @cloudEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code'**
  String get cloudEnterCode;

  /// Drawer entry: filament swatch codes
  ///
  /// In en, this message translates to:
  /// **'Swatch Codes'**
  String get swatchCodesMenu;

  /// No description provided for @swatchCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Swatch Codes'**
  String get swatchCodesTitle;

  /// No description provided for @swatchSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by code or name'**
  String get swatchSearchHint;

  /// No description provided for @swatchSectionCodes.
  ///
  /// In en, this message translates to:
  /// **'Codes'**
  String get swatchSectionCodes;

  /// No description provided for @swatchSectionUncoded.
  ///
  /// In en, this message translates to:
  /// **'Inventory filaments without codes'**
  String get swatchSectionUncoded;

  /// No description provided for @swatchNoCodes.
  ///
  /// In en, this message translates to:
  /// **'No swatch codes yet'**
  String get swatchNoCodes;

  /// No description provided for @swatchNoCodesHint.
  ///
  /// In en, this message translates to:
  /// **'Create a code to label a filament sample.'**
  String get swatchNoCodesHint;

  /// No description provided for @swatchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No codes match \"{query}\"'**
  String swatchNoMatch(String query);

  /// No description provided for @swatchAllCoded.
  ///
  /// In en, this message translates to:
  /// **'All inventory filaments have codes'**
  String get swatchAllCoded;

  /// No description provided for @swatchNewCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get swatchNewCode;

  /// No description provided for @swatchGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get swatchGenerate;

  /// No description provided for @swatchGenerateCode.
  ///
  /// In en, this message translates to:
  /// **'Generate code'**
  String get swatchGenerateCode;

  /// No description provided for @swatchExists.
  ///
  /// In en, this message translates to:
  /// **'That filament already has a code'**
  String get swatchExists;

  /// No description provided for @swatchCreatedSnack.
  ///
  /// In en, this message translates to:
  /// **'Created code {code}'**
  String swatchCreatedSnack(String code);

  /// No description provided for @swatchUpdatedSnack.
  ///
  /// In en, this message translates to:
  /// **'Updated code {code}'**
  String swatchUpdatedSnack(String code);

  /// No description provided for @swatchCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {code}'**
  String swatchCopied(String code);

  /// No description provided for @swatchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get swatchDelete;

  /// No description provided for @swatchDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete code?'**
  String get swatchDeleteTitle;

  /// No description provided for @swatchDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Code {code} for {name} will be removed.'**
  String swatchDeleteBody(String code, String name);

  /// No description provided for @swatchExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get swatchExport;

  /// No description provided for @swatchImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get swatchImport;

  /// No description provided for @swatchExportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No codes to export'**
  String get swatchExportEmpty;

  /// No description provided for @swatchExported.
  ///
  /// In en, this message translates to:
  /// **'Exported {count, plural, =1{1 code} other{{count} codes}}'**
  String swatchExported(int count);

  /// No description provided for @swatchExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get swatchExportFailed;

  /// No description provided for @swatchImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import codes?'**
  String get swatchImportTitle;

  /// No description provided for @swatchImportWarning.
  ///
  /// In en, this message translates to:
  /// **'This replaces all {existing} existing codes with {incoming} codes from the file. This cannot be undone.'**
  String swatchImportWarning(int existing, int incoming);

  /// No description provided for @swatchImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get swatchImportConfirm;

  /// No description provided for @swatchImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {count, plural, =1{1 code} other{{count} codes}}'**
  String swatchImported(int count);

  /// No description provided for @swatchImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file'**
  String get swatchImportFailed;

  /// No description provided for @swatchImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No codes found in file'**
  String get swatchImportEmpty;

  /// No description provided for @swatchFormTitle.
  ///
  /// In en, this message translates to:
  /// **'New swatch code'**
  String get swatchFormTitle;

  /// No description provided for @swatchEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit code'**
  String get swatchEditTitle;

  /// No description provided for @swatchSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get swatchSave;

  /// No description provided for @swatchRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get swatchRegenerate;

  /// No description provided for @swatchFieldCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get swatchFieldCode;

  /// No description provided for @swatchCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use 6 characters: digits and letters, no 0, 1, I, L or O'**
  String get swatchCodeInvalid;

  /// No description provided for @swatchCodeTaken.
  ///
  /// In en, this message translates to:
  /// **'That code is already in use'**
  String get swatchCodeTaken;

  /// No description provided for @swatchFieldBrand.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer'**
  String get swatchFieldBrand;

  /// No description provided for @swatchFieldMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get swatchFieldMaterial;

  /// No description provided for @swatchFieldVariant.
  ///
  /// In en, this message translates to:
  /// **'Variant'**
  String get swatchFieldVariant;

  /// No description provided for @swatchFieldColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get swatchFieldColor;

  /// No description provided for @swatchFieldHex.
  ///
  /// In en, this message translates to:
  /// **'Color hex'**
  String get swatchFieldHex;

  /// No description provided for @swatchMaterialRequired.
  ///
  /// In en, this message translates to:
  /// **'Material is required'**
  String get swatchMaterialRequired;

  /// No description provided for @swatchNoCatalogColors.
  ///
  /// In en, this message translates to:
  /// **'No catalog colors available. Enter a color name and hex manually.'**
  String get swatchNoCatalogColors;

  /// No description provided for @projectsMenu.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsMenu;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @projectsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get projectsEmpty;

  /// No description provided for @projectsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get projectsFilterAll;

  /// No description provided for @projectCreate.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get projectCreate;

  /// No description provided for @projectEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get projectEdit;

  /// No description provided for @projectDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get projectDelete;

  /// No description provided for @projectDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get projectDeleteTitle;

  /// No description provided for @projectDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be removed. Linked prints stay in the archive.'**
  String projectDeleteBody(String name);

  /// No description provided for @projectDeleted.
  ///
  /// In en, this message translates to:
  /// **'Project deleted'**
  String get projectDeleted;

  /// No description provided for @projectDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete project'**
  String get projectDeleteFailed;

  /// No description provided for @projectSaved.
  ///
  /// In en, this message translates to:
  /// **'Project saved'**
  String get projectSaved;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get projectName;

  /// No description provided for @projectNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get projectNameRequired;

  /// No description provided for @projectDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get projectDescription;

  /// No description provided for @projectNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get projectNotes;

  /// No description provided for @projectStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get projectStatus;

  /// No description provided for @projectPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get projectPriority;

  /// No description provided for @projectColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get projectColor;

  /// No description provided for @projectDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get projectDueDate;

  /// No description provided for @projectDueDateClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get projectDueDateClear;

  /// No description provided for @projectBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get projectBudget;

  /// No description provided for @projectTargetCount.
  ///
  /// In en, this message translates to:
  /// **'Target plates'**
  String get projectTargetCount;

  /// No description provided for @projectTargetPartsCount.
  ///
  /// In en, this message translates to:
  /// **'Target parts'**
  String get projectTargetPartsCount;

  /// No description provided for @projectTargetSets.
  ///
  /// In en, this message translates to:
  /// **'Target sets'**
  String get projectTargetSets;

  /// No description provided for @projectTargetSetsHint.
  ///
  /// In en, this message translates to:
  /// **'How many times each file in the project should be printed'**
  String get projectTargetSetsHint;

  /// No description provided for @projectTags.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get projectTags;

  /// No description provided for @projectUrl.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get projectUrl;

  /// No description provided for @projectParent.
  ///
  /// In en, this message translates to:
  /// **'Parent project'**
  String get projectParent;

  /// No description provided for @projectParentNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get projectParentNone;

  /// No description provided for @projectSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get projectSave;

  /// No description provided for @projectStatusPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get projectStatusPlanning;

  /// No description provided for @projectStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get projectStatusActive;

  /// No description provided for @projectStatusOnHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get projectStatusOnHold;

  /// No description provided for @projectStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get projectStatusCompleted;

  /// No description provided for @projectStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get projectStatusArchived;

  /// No description provided for @projectPriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get projectPriorityLow;

  /// No description provided for @projectPriorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get projectPriorityNormal;

  /// No description provided for @projectPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get projectPriorityHigh;

  /// No description provided for @projectPriorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get projectPriorityUrgent;

  /// No description provided for @projectTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get projectTabOverview;

  /// No description provided for @projectTabArchives.
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get projectTabArchives;

  /// No description provided for @projectTabBom.
  ///
  /// In en, this message translates to:
  /// **'BOM'**
  String get projectTabBom;

  /// No description provided for @projectTabQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get projectTabQueue;

  /// No description provided for @projectTabTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get projectTabTimeline;

  /// No description provided for @projectTabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get projectTabFiles;

  /// No description provided for @projectTabAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get projectTabAttachments;

  /// No description provided for @projectStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get projectStatsTitle;

  /// No description provided for @projectStatProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get projectStatProgress;

  /// No description provided for @projectStatPartsProgress.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get projectStatPartsProgress;

  /// No description provided for @projectStatSets.
  ///
  /// In en, this message translates to:
  /// **'Complete sets'**
  String get projectStatSets;

  /// No description provided for @projectSetsOfTarget.
  ///
  /// In en, this message translates to:
  /// **'{done} of {target}'**
  String projectSetsOfTarget(int done, int target);

  /// No description provided for @projectStatPrints.
  ///
  /// In en, this message translates to:
  /// **'Plates'**
  String get projectStatPrints;

  /// No description provided for @projectStatCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get projectStatCompleted;

  /// No description provided for @projectStatFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get projectStatFailed;

  /// No description provided for @projectStatQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get projectStatQueued;

  /// No description provided for @projectStatInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get projectStatInProgress;

  /// No description provided for @projectStatPrintTime.
  ///
  /// In en, this message translates to:
  /// **'Print time'**
  String get projectStatPrintTime;

  /// No description provided for @projectStatFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get projectStatFilament;

  /// No description provided for @projectStatCost.
  ///
  /// In en, this message translates to:
  /// **'Est. cost'**
  String get projectStatCost;

  /// No description provided for @projectStatEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get projectStatEnergy;

  /// No description provided for @projectStatEnergyCost.
  ///
  /// In en, this message translates to:
  /// **'Energy cost'**
  String get projectStatEnergyCost;

  /// No description provided for @projectStatRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get projectStatRemaining;

  /// No description provided for @projectStatBom.
  ///
  /// In en, this message translates to:
  /// **'BOM'**
  String get projectStatBom;

  /// No description provided for @projectChildren.
  ///
  /// In en, this message translates to:
  /// **'Sub-projects'**
  String get projectChildren;

  /// No description provided for @projectNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get projectNoDescription;

  /// No description provided for @projectDueOn.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String projectDueOn(String date);

  /// No description provided for @projectAddArchives.
  ///
  /// In en, this message translates to:
  /// **'Add archives'**
  String get projectAddArchives;

  /// No description provided for @projectRemoveArchive.
  ///
  /// In en, this message translates to:
  /// **'Remove from project'**
  String get projectRemoveArchive;

  /// No description provided for @projectArchivesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archives linked'**
  String get projectArchivesEmpty;

  /// No description provided for @projectArchiveRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from project'**
  String get projectArchiveRemoved;

  /// No description provided for @archiveAddToProject.
  ///
  /// In en, this message translates to:
  /// **'Add to project'**
  String get archiveAddToProject;

  /// No description provided for @projectArchivesAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to project'**
  String get projectArchivesAdded;

  /// No description provided for @projectPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a project'**
  String get projectPickTitle;

  /// No description provided for @projectBomEmpty.
  ///
  /// In en, this message translates to:
  /// **'No BOM items'**
  String get projectBomEmpty;

  /// No description provided for @bomAdd.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get bomAdd;

  /// No description provided for @bomEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get bomEditTitle;

  /// No description provided for @bomAddTitle.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get bomAddTitle;

  /// No description provided for @bomName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get bomName;

  /// No description provided for @bomQtyNeeded.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get bomQtyNeeded;

  /// No description provided for @bomQtyAcquired.
  ///
  /// In en, this message translates to:
  /// **'Acquired'**
  String get bomQtyAcquired;

  /// No description provided for @bomUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get bomUnitPrice;

  /// No description provided for @bomSourcingUrl.
  ///
  /// In en, this message translates to:
  /// **'Source URL'**
  String get bomSourcingUrl;

  /// No description provided for @bomRemarks.
  ///
  /// In en, this message translates to:
  /// **'Remarks'**
  String get bomRemarks;

  /// No description provided for @bomComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get bomComplete;

  /// No description provided for @bomDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get bomDelete;

  /// No description provided for @bomDeleted.
  ///
  /// In en, this message translates to:
  /// **'Item deleted'**
  String get bomDeleted;

  /// No description provided for @projectQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No queue items'**
  String get projectQueueEmpty;

  /// No description provided for @projectTimelineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No events yet'**
  String get projectTimelineEmpty;

  /// No description provided for @projectAttachmentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No attachments'**
  String get projectAttachmentsEmpty;

  /// No description provided for @projectFilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No printable files'**
  String get projectFilesEmpty;

  /// No description provided for @projectAttachmentUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get projectAttachmentUpload;

  /// No description provided for @projectAttachmentDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get projectAttachmentDownload;

  /// No description provided for @projectAttachmentDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get projectAttachmentDelete;

  /// No description provided for @projectAttachmentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Attachment deleted'**
  String get projectAttachmentDeleted;

  /// No description provided for @projectAttachmentUploaded.
  ///
  /// In en, this message translates to:
  /// **'Attachment uploaded'**
  String get projectAttachmentUploaded;

  /// No description provided for @projectFileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String projectFileSaved(String path);

  /// No description provided for @projectDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get projectDownloadFailed;

  /// No description provided for @projectCoverUpload.
  ///
  /// In en, this message translates to:
  /// **'Set cover image'**
  String get projectCoverUpload;

  /// No description provided for @projectCoverDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove cover image'**
  String get projectCoverDelete;

  /// No description provided for @projectCoverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get projectCoverUpdated;

  /// No description provided for @projectCoverRemoved.
  ///
  /// In en, this message translates to:
  /// **'Cover removed'**
  String get projectCoverRemoved;

  /// No description provided for @projectMenuExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get projectMenuExport;

  /// No description provided for @projectMenuCreateTemplate.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get projectMenuCreateTemplate;

  /// No description provided for @projectMenuImport.
  ///
  /// In en, this message translates to:
  /// **'Import project'**
  String get projectMenuImport;

  /// No description provided for @projectFromTemplate.
  ///
  /// In en, this message translates to:
  /// **'Create from template'**
  String get projectFromTemplate;

  /// No description provided for @projectTemplateNone.
  ///
  /// In en, this message translates to:
  /// **'No templates'**
  String get projectTemplateNone;

  /// No description provided for @projectTemplatePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a template'**
  String get projectTemplatePickTitle;

  /// No description provided for @projectTemplateNamePrompt.
  ///
  /// In en, this message translates to:
  /// **'New project name'**
  String get projectTemplateNamePrompt;

  /// No description provided for @projectExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String projectExported(String path);

  /// No description provided for @projectExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get projectExportFailed;

  /// No description provided for @projectTemplateCreated.
  ///
  /// In en, this message translates to:
  /// **'Template created'**
  String get projectTemplateCreated;

  /// No description provided for @projectImported.
  ///
  /// In en, this message translates to:
  /// **'Project imported'**
  String get projectImported;

  /// No description provided for @projectImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get projectImportFailed;

  /// No description provided for @projectUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get projectUploading;

  /// No description provided for @projectLinkFolder.
  ///
  /// In en, this message translates to:
  /// **'Link folder'**
  String get projectLinkFolder;

  /// No description provided for @projectNoFoldersToLink.
  ///
  /// In en, this message translates to:
  /// **'No folders available to link'**
  String get projectNoFoldersToLink;

  /// No description provided for @projectUnlinkFolder.
  ///
  /// In en, this message translates to:
  /// **'Unlink folder'**
  String get projectUnlinkFolder;

  /// No description provided for @projectFolderLinked.
  ///
  /// In en, this message translates to:
  /// **'Folder linked'**
  String get projectFolderLinked;

  /// No description provided for @projectFolderUnlinked.
  ///
  /// In en, this message translates to:
  /// **'Folder unlinked'**
  String get projectFolderUnlinked;

  /// No description provided for @projectNotesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get projectNotesEmpty;

  /// No description provided for @projectFolderFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} file} other{{count} files}}'**
  String projectFolderFileCount(int count);

  /// No description provided for @projectRemainingShort.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String projectRemainingShort(int count);

  /// No description provided for @sliceAction.
  ///
  /// In en, this message translates to:
  /// **'Slice'**
  String get sliceAction;

  /// No description provided for @sliceTitle.
  ///
  /// In en, this message translates to:
  /// **'Slice file'**
  String get sliceTitle;

  /// No description provided for @slicePrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get slicePrinter;

  /// No description provided for @sliceProcess.
  ///
  /// In en, this message translates to:
  /// **'Process / Quality'**
  String get sliceProcess;

  /// No description provided for @sliceBedType.
  ///
  /// In en, this message translates to:
  /// **'Build plate'**
  String get sliceBedType;

  /// No description provided for @sliceBedDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (from preset)'**
  String get sliceBedDefault;

  /// No description provided for @sliceFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get sliceFilament;

  /// No description provided for @sliceFilamentNumbered.
  ///
  /// In en, this message translates to:
  /// **'Filament {n}'**
  String sliceFilamentNumbered(String n);

  /// No description provided for @sliceAutoOrient.
  ///
  /// In en, this message translates to:
  /// **'Auto orient'**
  String get sliceAutoOrient;

  /// No description provided for @sliceAutoOrientHint.
  ///
  /// In en, this message translates to:
  /// **'Turns each object onto its best printing side.'**
  String get sliceAutoOrientHint;

  /// No description provided for @sliceAutoArrange.
  ///
  /// In en, this message translates to:
  /// **'Auto arrange'**
  String get sliceAutoArrange;

  /// No description provided for @sliceAutoArrangeHint.
  ///
  /// In en, this message translates to:
  /// **'Lays the objects out on the plate again.'**
  String get sliceAutoArrangeHint;

  /// No description provided for @sliceDesignedFor.
  ///
  /// In en, this message translates to:
  /// **'This file is for {printer}'**
  String sliceDesignedFor(String printer);

  /// No description provided for @sliceUseDesignedPrinter.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get sliceUseDesignedPrinter;

  /// No description provided for @sliceAsDesigned.
  ///
  /// In en, this message translates to:
  /// **'Use the file\'s own settings'**
  String get sliceAsDesigned;

  /// No description provided for @sliceAsDesignedHint.
  ///
  /// In en, this message translates to:
  /// **'The designer\'s settings instead of the profiles above.'**
  String get sliceAsDesignedHint;

  /// No description provided for @sliceAsDesignedInactive.
  ///
  /// In en, this message translates to:
  /// **'Not used — the file decides'**
  String get sliceAsDesignedInactive;

  /// No description provided for @sliceFilamentUnused.
  ///
  /// In en, this message translates to:
  /// **'Not used by this plate'**
  String get sliceFilamentUnused;

  /// No description provided for @processSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Process settings'**
  String get processSettingsTitle;

  /// No description provided for @sliceProcessSettingsNeedsProcess.
  ///
  /// In en, this message translates to:
  /// **'Pick a process preset first'**
  String get sliceProcessSettingsNeedsProcess;

  /// No description provided for @sliceProcessSettingsUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Using the preset as it is'**
  String get sliceProcessSettingsUnchanged;

  /// No description provided for @sliceProcessSettingsChanged.
  ///
  /// In en, this message translates to:
  /// **'{count} changed'**
  String sliceProcessSettingsChanged(int count);

  /// No description provided for @processSettingsModeSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get processSettingsModeSimple;

  /// No description provided for @processSettingsModeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get processSettingsModeAdvanced;

  /// No description provided for @processSettingsModeExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get processSettingsModeExpert;

  /// No description provided for @processSettingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get processSettingsSearchHint;

  /// No description provided for @processSettingsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No settings match this search.'**
  String get processSettingsNoMatches;

  /// No description provided for @processSettingsRevert.
  ///
  /// In en, this message translates to:
  /// **'Reset to the preset\'s value'**
  String get processSettingsRevert;

  /// No description provided for @processSettingsRevertAll.
  ///
  /// In en, this message translates to:
  /// **'Reset {count}'**
  String processSettingsRevertAll(int count);

  /// No description provided for @processSettingsOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'The slicer accepts {range}'**
  String processSettingsOutOfRange(String range);

  /// No description provided for @processSettingsDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'The slicer ignores this with your current settings.'**
  String get processSettingsDisabledHint;

  /// No description provided for @processSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server cannot report process settings for the selected preset.'**
  String get processSettingsUnavailable;

  /// No description provided for @processSettingsDefaultsOutdatedSidecar.
  ///
  /// In en, this message translates to:
  /// **'Showing slicer defaults: your slicer sidecar is older than this feature and cannot report a preset\'s values. Update the sidecar image to see them. Anything you do not change still uses the preset.'**
  String get processSettingsDefaultsOutdatedSidecar;

  /// No description provided for @processSettingsDefaultsNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Showing slicer defaults: no slicer sidecar is configured, so a preset\'s values cannot be read. Anything you do not change still uses the preset.'**
  String get processSettingsDefaultsNotConfigured;

  /// No description provided for @processSettingsDefaultsSidecarUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Showing slicer defaults: the slicer sidecar did not answer, so a preset\'s values cannot be read. Anything you do not change still uses the preset.'**
  String get processSettingsDefaultsSidecarUnavailable;

  /// No description provided for @processSettingsDefaultsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Showing slicer defaults: the selected preset\'s own values could not be read. Anything you do not change still uses the preset.'**
  String get processSettingsDefaultsUnavailable;

  /// No description provided for @processSettingsFilamentDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (the region\'s own filament)'**
  String get processSettingsFilamentDefault;

  /// No description provided for @processSettingsFilamentSlot.
  ///
  /// In en, this message translates to:
  /// **'{slot}: {name}'**
  String processSettingsFilamentSlot(String slot, String name);

  /// No description provided for @processSettingsFilamentSlotMissing.
  ///
  /// In en, this message translates to:
  /// **'Slot {slot} — this file has no such slot'**
  String processSettingsFilamentSlotMissing(String slot);

  /// No description provided for @sliceSelect.
  ///
  /// In en, this message translates to:
  /// **'Tap to select'**
  String get sliceSelect;

  /// No description provided for @sliceStart.
  ///
  /// In en, this message translates to:
  /// **'Slice'**
  String get sliceStart;

  /// No description provided for @sliceShowAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get sliceShowAll;

  /// No description provided for @sliceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search presets'**
  String get sliceSearchHint;

  /// No description provided for @sliceOwnedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching presets for your printer and filaments. Turn on \"All\" to browse the full catalog.'**
  String get sliceOwnedEmpty;

  /// No description provided for @sliceNoPresets.
  ///
  /// In en, this message translates to:
  /// **'No presets available'**
  String get sliceNoPresets;

  /// No description provided for @sliceInProgress.
  ///
  /// In en, this message translates to:
  /// **'Slicing…'**
  String get sliceInProgress;

  /// No description provided for @sliceDone.
  ///
  /// In en, this message translates to:
  /// **'Slice complete'**
  String get sliceDone;

  /// No description provided for @sliceFailed.
  ///
  /// In en, this message translates to:
  /// **'Slice failed'**
  String get sliceFailed;

  /// No description provided for @sliceExternalFallback.
  ///
  /// In en, this message translates to:
  /// **'Saved in the server\'s library — the file\'s own folder could not take it.'**
  String get sliceExternalFallback;

  /// No description provided for @sliceExternalReadonly.
  ///
  /// In en, this message translates to:
  /// **'That folder is set to read-only.'**
  String get sliceExternalReadonly;

  /// No description provided for @sliceExternalNoPath.
  ///
  /// In en, this message translates to:
  /// **'That folder has no path configured.'**
  String get sliceExternalNoPath;

  /// No description provided for @sliceExternalUnreachable.
  ///
  /// In en, this message translates to:
  /// **'That folder\'s path is not reachable right now.'**
  String get sliceExternalUnreachable;

  /// No description provided for @sliceExternalNotWritable.
  ///
  /// In en, this message translates to:
  /// **'The server cannot write to that folder.'**
  String get sliceExternalNotWritable;

  /// No description provided for @sliceExternalInvalidName.
  ///
  /// In en, this message translates to:
  /// **'That folder would not take the file\'s name.'**
  String get sliceExternalInvalidName;

  /// No description provided for @sliceClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sliceClose;

  /// No description provided for @sliceResultTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated time: {time}'**
  String sliceResultTime(String time);

  /// No description provided for @sliceRefusedStep.
  ///
  /// In en, this message translates to:
  /// **'STEP files cannot be sliced. Export the model as an STL or a 3MF from your CAD first.'**
  String get sliceRefusedStep;

  /// No description provided for @sliceRefusedFormat.
  ///
  /// In en, this message translates to:
  /// **'The source has to be an STL or a 3MF.'**
  String get sliceRefusedFormat;

  /// No description provided for @sliceRefusedNoSource.
  ///
  /// In en, this message translates to:
  /// **'This archive kept only the G-code it printed, not the model — there is nothing to slice again.'**
  String get sliceRefusedNoSource;

  /// No description provided for @sliceResultFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament: {grams} g'**
  String sliceResultFilament(String grams);

  /// No description provided for @sliceTierLocal.
  ///
  /// In en, this message translates to:
  /// **'Local preset'**
  String get sliceTierLocal;

  /// No description provided for @sliceTierCloud.
  ///
  /// In en, this message translates to:
  /// **'Bambu Cloud'**
  String get sliceTierCloud;

  /// No description provided for @sliceTierOrcaCloud.
  ///
  /// In en, this message translates to:
  /// **'Orca Cloud'**
  String get sliceTierOrcaCloud;

  /// No description provided for @sliceTierStandard.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get sliceTierStandard;

  /// No description provided for @pipelineSection.
  ///
  /// In en, this message translates to:
  /// **'Pipeline'**
  String get pipelineSection;

  /// No description provided for @pipelineApply.
  ///
  /// In en, this message translates to:
  /// **'Apply pipeline…'**
  String get pipelineApply;

  /// No description provided for @pipelineApplyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved pipelines'**
  String get pipelineApplyEmpty;

  /// No description provided for @pipelineApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied \"{name}\"'**
  String pipelineApplied(String name);

  /// No description provided for @pipelineSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as pipeline'**
  String get pipelineSaveAs;

  /// No description provided for @pipelineNameHint.
  ///
  /// In en, this message translates to:
  /// **'Pipeline name'**
  String get pipelineNameHint;

  /// No description provided for @pipelineSaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get pipelineSaveConfirm;

  /// No description provided for @pipelineSaved.
  ///
  /// In en, this message translates to:
  /// **'Pipeline saved'**
  String get pipelineSaved;

  /// No description provided for @pipelineSaveHint.
  ///
  /// In en, this message translates to:
  /// **'The printer, process, filaments and plate above, under a name you can reapply to the next file.'**
  String get pipelineSaveHint;

  /// No description provided for @pipelinesMenu.
  ///
  /// In en, this message translates to:
  /// **'Pipelines'**
  String get pipelinesMenu;

  /// No description provided for @pipelinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Pipelines'**
  String get pipelinesTitle;

  /// No description provided for @pipelinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pipelines yet'**
  String get pipelinesEmpty;

  /// No description provided for @pipelinesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Save one from the slice form — printer, process, filaments and plate as a bundle you can reapply in one tap.'**
  String get pipelinesEmptyHint;

  /// No description provided for @pipelineProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get pipelineProfiles;

  /// No description provided for @pipelineFilamentsCount.
  ///
  /// In en, this message translates to:
  /// **'Filaments ({count})'**
  String pipelineFilamentsCount(int count);

  /// No description provided for @pipelineHistory.
  ///
  /// In en, this message translates to:
  /// **'Run history'**
  String get pipelineHistory;

  /// No description provided for @pipelineCardActions.
  ///
  /// In en, this message translates to:
  /// **'Pipeline actions'**
  String get pipelineCardActions;

  /// No description provided for @pipelineSlotNumbered.
  ///
  /// In en, this message translates to:
  /// **'Filament {n}'**
  String pipelineSlotNumbered(int n);

  /// No description provided for @pipelineBed.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get pipelineBed;

  /// No description provided for @pipelinePresetGone.
  ///
  /// In en, this message translates to:
  /// **'No longer in the catalog'**
  String get pipelinePresetGone;

  /// No description provided for @pipelineNeedsTarget.
  ///
  /// In en, this message translates to:
  /// **'Set a target before running this pipeline.'**
  String get pipelineNeedsTarget;

  /// No description provided for @pipelineNoTargetChip.
  ///
  /// In en, this message translates to:
  /// **'No target'**
  String get pipelineNoTargetChip;

  /// No description provided for @pipelineEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit pipeline'**
  String get pipelineEditTitle;

  /// No description provided for @pipelineDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get pipelineDescriptionHint;

  /// No description provided for @pipelineTargetType.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get pipelineTargetType;

  /// No description provided for @pipelineTargetSpecific.
  ///
  /// In en, this message translates to:
  /// **'One printer'**
  String get pipelineTargetSpecific;

  /// No description provided for @pipelineTargetClass.
  ///
  /// In en, this message translates to:
  /// **'Printer model'**
  String get pipelineTargetClass;

  /// No description provided for @pipelineTargetPickPrinter.
  ///
  /// In en, this message translates to:
  /// **'Pick a printer'**
  String get pipelineTargetPickPrinter;

  /// No description provided for @pipelineTargetPickClass.
  ///
  /// In en, this message translates to:
  /// **'Pick a model'**
  String get pipelineTargetPickClass;

  /// No description provided for @pipelineTargetNone.
  ///
  /// In en, this message translates to:
  /// **'— no target —'**
  String get pipelineTargetNone;

  /// No description provided for @pipelineTargetPrinterGone.
  ///
  /// In en, this message translates to:
  /// **'Printer #{id} (gone)'**
  String pipelineTargetPrinterGone(int id);

  /// No description provided for @pipelineFanout.
  ///
  /// In en, this message translates to:
  /// **'Spreading the copies'**
  String get pipelineFanout;

  /// No description provided for @pipelineFanoutMaxParallel.
  ///
  /// In en, this message translates to:
  /// **'Max parallel — across any idle matching printer'**
  String get pipelineFanoutMaxParallel;

  /// No description provided for @pipelineFanoutRoundRobin.
  ///
  /// In en, this message translates to:
  /// **'Round robin — cycle through eligible printers'**
  String get pipelineFanoutRoundRobin;

  /// No description provided for @pipelineFanoutFillOneFirst.
  ///
  /// In en, this message translates to:
  /// **'Fill one first — every copy on one printer'**
  String get pipelineFanoutFillOneFirst;

  /// No description provided for @pipelineDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete pipeline'**
  String get pipelineDelete;

  /// No description provided for @pipelineDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Runs already made keep their name.'**
  String pipelineDeleteConfirm(String name);

  /// No description provided for @pipelineDeleted.
  ///
  /// In en, this message translates to:
  /// **'Pipeline deleted'**
  String get pipelineDeleted;

  /// No description provided for @pipelineDescriptionNoClear.
  ///
  /// In en, this message translates to:
  /// **'A description cannot be emptied once saved — this server only ever writes a new one.'**
  String get pipelineDescriptionNoClear;

  /// No description provided for @pipelineRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get pipelineRun;

  /// No description provided for @pipelineRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Run \"{name}\"'**
  String pipelineRunTitle(String name);

  /// No description provided for @pipelineRunCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get pipelineRunCopies;

  /// No description provided for @pipelineRunStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get pipelineRunStart;

  /// No description provided for @pipelineRunStarted.
  ///
  /// In en, this message translates to:
  /// **'Run started'**
  String get pipelineRunStarted;

  /// No description provided for @pipelineRunAnyway.
  ///
  /// In en, this message translates to:
  /// **'Run anyway'**
  String get pipelineRunAnyway;

  /// No description provided for @pipelineRunMaxCopies.
  ///
  /// In en, this message translates to:
  /// **'This server allows {max} at most.'**
  String pipelineRunMaxCopies(int max);

  /// No description provided for @pipelineCheckingEligibility.
  ///
  /// In en, this message translates to:
  /// **'Checking printers…'**
  String get pipelineCheckingEligibility;

  /// No description provided for @pipelineEligibilityOk.
  ///
  /// In en, this message translates to:
  /// **'Ready to run.'**
  String get pipelineEligibilityOk;

  /// No description provided for @pipelineEligibilityClassCount.
  ///
  /// In en, this message translates to:
  /// **'{ok} of {total} printers ready'**
  String pipelineEligibilityClassCount(int ok, int total);

  /// No description provided for @pipelineEligibilityBlocked.
  ///
  /// In en, this message translates to:
  /// **'Nothing can take this run right now.'**
  String get pipelineEligibilityBlocked;

  /// No description provided for @pipelineEligibilityAdvisory.
  ///
  /// In en, this message translates to:
  /// **'Worth a look before you start.'**
  String get pipelineEligibilityAdvisory;

  /// No description provided for @pipelineIssuePrinterNotSet.
  ///
  /// In en, this message translates to:
  /// **'This pipeline has no target printer.'**
  String get pipelineIssuePrinterNotSet;

  /// No description provided for @pipelineIssuePrinterNotFound.
  ///
  /// In en, this message translates to:
  /// **'The target printer no longer exists.'**
  String get pipelineIssuePrinterNotFound;

  /// No description provided for @pipelineIssuePrinterDisabled.
  ///
  /// In en, this message translates to:
  /// **'The target printer is switched off in bambuddy.'**
  String get pipelineIssuePrinterDisabled;

  /// No description provided for @pipelineIssuePrinterOffline.
  ///
  /// In en, this message translates to:
  /// **'The target printer is offline.'**
  String get pipelineIssuePrinterOffline;

  /// No description provided for @pipelineIssueFilamentType.
  ///
  /// In en, this message translates to:
  /// **'Wrong filament type loaded.'**
  String get pipelineIssueFilamentType;

  /// No description provided for @pipelineIssueFilamentColor.
  ///
  /// In en, this message translates to:
  /// **'The loaded filament is a different colour.'**
  String get pipelineIssueFilamentColor;

  /// No description provided for @pipelineIssueAmsSlotMissing.
  ///
  /// In en, this message translates to:
  /// **'The AMS has fewer slots than this pipeline needs.'**
  String get pipelineIssueAmsSlotMissing;

  /// No description provided for @pipelineIssueFilamentUnverified.
  ///
  /// In en, this message translates to:
  /// **'This filament preset cannot be checked from here — worth confirming yourself.'**
  String get pipelineIssueFilamentUnverified;

  /// No description provided for @pipelineIssueNoClassMatches.
  ///
  /// In en, this message translates to:
  /// **'No printer of this model is installed.'**
  String get pipelineIssueNoClassMatches;

  /// No description provided for @pipelineIssueClassNotSet.
  ///
  /// In en, this message translates to:
  /// **'This pipeline has no printer model set.'**
  String get pipelineIssueClassNotSet;

  /// No description provided for @pipelineIssueSlot.
  ///
  /// In en, this message translates to:
  /// **'Slot {n}'**
  String pipelineIssueSlot(int n);

  /// No description provided for @pipelineIssueWantedGot.
  ///
  /// In en, this message translates to:
  /// **'wanted {expected}, loaded {actual}'**
  String pipelineIssueWantedGot(String expected, String actual);

  /// No description provided for @pipelineIssueWanted.
  ///
  /// In en, this message translates to:
  /// **'wanted {expected}'**
  String pipelineIssueWanted(String expected);

  /// No description provided for @pipelineRunsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pipeline runs'**
  String get pipelineRunsTitle;

  /// No description provided for @pipelineRunsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get pipelineRunsEmpty;

  /// No description provided for @pipelineRunsNoneMatch.
  ///
  /// In en, this message translates to:
  /// **'No run matches these filters'**
  String get pipelineRunsNoneMatch;

  /// No description provided for @pipelineRunsFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter runs'**
  String get pipelineRunsFilter;

  /// No description provided for @pipelineCopiesLess.
  ///
  /// In en, this message translates to:
  /// **'One fewer copy'**
  String get pipelineCopiesLess;

  /// No description provided for @pipelineCopiesMore.
  ///
  /// In en, this message translates to:
  /// **'One more copy'**
  String get pipelineCopiesMore;

  /// No description provided for @pipelineEligible.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get pipelineEligible;

  /// No description provided for @pipelineIneligible.
  ///
  /// In en, this message translates to:
  /// **'Not ready'**
  String get pipelineIneligible;

  /// No description provided for @pipelineRunsFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Filter runs ({count} active)'**
  String pipelineRunsFilterActive(int count);

  /// No description provided for @pipelineRunsFilterAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get pipelineRunsFilterAny;

  /// No description provided for @pipelineRunsFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get pipelineRunsFilterStatus;

  /// No description provided for @pipelineRunsFilterStatusHint.
  ///
  /// In en, this message translates to:
  /// **'Matches the last status written down, so a run can still answer to the step before the one it is on.'**
  String get pipelineRunsFilterStatusHint;

  /// No description provided for @pipelineRunsFilterTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get pipelineRunsFilterTarget;

  /// No description provided for @pipelineRunsFilterTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Where the pipeline points now — re-targeting one moves its whole history.'**
  String get pipelineRunsFilterTargetHint;

  /// No description provided for @pipelineRunsFilterPipelineHint.
  ///
  /// In en, this message translates to:
  /// **'Runs of a deleted pipeline cannot be filtered to.'**
  String get pipelineRunsFilterPipelineHint;

  /// No description provided for @pipelineRunsFilterClear.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get pipelineRunsFilterClear;

  /// No description provided for @pipelineRunsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get pipelineRunsLoadMore;

  /// No description provided for @pipelineRunsShowingAll.
  ///
  /// In en, this message translates to:
  /// **'All {count} shown'**
  String pipelineRunsShowingAll(int count);

  /// No description provided for @pipelineRunsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pipelineRunsDone;

  /// No description provided for @pipelineRunsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get pipelineRunsClear;

  /// No description provided for @pipelineRunsCleared.
  ///
  /// In en, this message translates to:
  /// **'{count} removed'**
  String pipelineRunsCleared(int count);

  /// No description provided for @pipelineRunsClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove every finished run from this list?'**
  String get pipelineRunsClearConfirm;

  /// No description provided for @pipelineRunCopiesProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} copies'**
  String pipelineRunCopiesProgress(int done, int total);

  /// No description provided for @pipelineRunCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel run'**
  String get pipelineRunCancel;

  /// No description provided for @pipelineRunCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this run? Copies not yet sent are dropped; anything already printing has to be stopped on the printer itself.'**
  String get pipelineRunCancelConfirm;

  /// No description provided for @pipelineRunCancelled.
  ///
  /// In en, this message translates to:
  /// **'Run cancelled'**
  String get pipelineRunCancelled;

  /// No description provided for @pipelineRunRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry failed'**
  String get pipelineRunRetry;

  /// No description provided for @pipelineRunRetryStarted.
  ///
  /// In en, this message translates to:
  /// **'Retrying {count} copies'**
  String pipelineRunRetryStarted(int count);

  /// No description provided for @pipelineRunOverridden.
  ///
  /// In en, this message translates to:
  /// **'Started past a failed check'**
  String get pipelineRunOverridden;

  /// No description provided for @pipelineRunDeletedPipeline.
  ///
  /// In en, this message translates to:
  /// **'Deleted pipeline'**
  String get pipelineRunDeletedPipeline;

  /// No description provided for @pipelineRunSource.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String pipelineRunSource(String name);

  /// No description provided for @pipelineRunRetryOf.
  ///
  /// In en, this message translates to:
  /// **'Retry of run #{id}'**
  String pipelineRunRetryOf(int id);

  /// No description provided for @pipelineRunOnPrinter.
  ///
  /// In en, this message translates to:
  /// **'On {printer}'**
  String pipelineRunOnPrinter(String printer);

  /// No description provided for @pipelineRunOnClass.
  ///
  /// In en, this message translates to:
  /// **'On any {model}'**
  String pipelineRunOnClass(String model);

  /// No description provided for @pipelineStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get pipelineStatusQueued;

  /// No description provided for @pipelineStatusSlicing.
  ///
  /// In en, this message translates to:
  /// **'Slicing'**
  String get pipelineStatusSlicing;

  /// No description provided for @pipelineStatusDispatching.
  ///
  /// In en, this message translates to:
  /// **'Dispatching'**
  String get pipelineStatusDispatching;

  /// No description provided for @pipelineStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get pipelineStatusInProgress;

  /// No description provided for @pipelineStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get pipelineStatusCompleted;

  /// No description provided for @pipelineStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pipelineStatusFailed;

  /// No description provided for @pipelineStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partly failed'**
  String get pipelineStatusPartial;

  /// No description provided for @pipelineStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get pipelineStatusCancelled;

  /// No description provided for @pipelineStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get pipelineStatusUnknown;

  /// No description provided for @pipelineJobCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy {n}'**
  String pipelineJobCopy(int n);

  /// No description provided for @pipelineJobPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pipelineJobPending;

  /// No description provided for @pipelineJobAwaitingPrinter.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a printer'**
  String get pipelineJobAwaitingPrinter;

  /// No description provided for @pipelineJobQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get pipelineJobQueued;

  /// No description provided for @pipelineJobPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get pipelineJobPrinting;

  /// No description provided for @pipelineJobCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pipelineJobCompleted;

  /// No description provided for @pipelineJobFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pipelineJobFailed;

  /// No description provided for @pipelineJobCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get pipelineJobCancelled;

  /// No description provided for @pipelineJobUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get pipelineJobUnknown;

  /// No description provided for @queueFilamentMapping.
  ///
  /// In en, this message translates to:
  /// **'Filament mapping'**
  String get queueFilamentMapping;

  /// No description provided for @mappingNoPrinter.
  ///
  /// In en, this message translates to:
  /// **'Assign a printer to this item first to map its AMS slots.'**
  String get mappingNoPrinter;

  /// No description provided for @mappingNoSlots.
  ///
  /// In en, this message translates to:
  /// **'No filament information for this file.'**
  String get mappingNoSlots;

  /// No description provided for @mappingNoAms.
  ///
  /// In en, this message translates to:
  /// **'No AMS filaments loaded on {printer}.'**
  String mappingNoAms(String printer);

  /// No description provided for @mappingPickTray.
  ///
  /// In en, this message translates to:
  /// **'Select AMS slot'**
  String get mappingPickTray;

  /// No description provided for @mappingExternalSpool.
  ///
  /// In en, this message translates to:
  /// **'External spool'**
  String get mappingExternalSpool;

  /// No description provided for @mappingAmsSlot.
  ///
  /// In en, this message translates to:
  /// **'AMS {unit} · slot {slot}'**
  String mappingAmsSlot(String unit, String slot);

  /// No description provided for @mappingSaved.
  ///
  /// In en, this message translates to:
  /// **'Filament mapping saved'**
  String get mappingSaved;

  /// No description provided for @plateClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Is the plate clear?'**
  String get plateClearTitle;

  /// No description provided for @plateClearBody.
  ///
  /// In en, this message translates to:
  /// **'Make sure the build plate is empty before starting this print.'**
  String get plateClearBody;

  /// No description provided for @plateClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Plate is clear'**
  String get plateClearConfirm;

  /// Tooltip of the checkmark button in the printer card's plate-clear banner — not a visible label, so it may be a full sentence. The watch says the same thing in wearClearPlate and has to be shorter; do not align the two.
  ///
  /// In en, this message translates to:
  /// **'Mark plate as cleared'**
  String get plateClearAction;

  /// Sentence beside that checkmark button. It is what lets the button be an icon alone — shorten this and the banner stops saying what it is about.
  ///
  /// In en, this message translates to:
  /// **'Plate not cleared'**
  String get plateClearBadge;

  /// No description provided for @plateClearedSnack.
  ///
  /// In en, this message translates to:
  /// **'Plate marked as cleared'**
  String get plateClearedSnack;

  /// No description provided for @plateClearNeedsOnline.
  ///
  /// In en, this message translates to:
  /// **'This server releases the plate only while the printer is connected. Update bambuddy to do it on a printer that is switched off.'**
  String get plateClearNeedsOnline;

  /// No description provided for @pfmTitle.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get pfmTitle;

  /// No description provided for @pfmTooltip.
  ///
  /// In en, this message translates to:
  /// **'Files on printer'**
  String get pfmTooltip;

  /// No description provided for @pfmStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'Used: {size}'**
  String pfmStorageUsed(String size);

  /// No description provided for @pfmTabRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get pfmTabRoot;

  /// No description provided for @pfmTabCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get pfmTabCache;

  /// No description provided for @pfmTabModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get pfmTabModels;

  /// No description provided for @pfmTabTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Timelapse'**
  String get pfmTabTimelapse;

  /// No description provided for @pfmSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter files…'**
  String get pfmSearchHint;

  /// No description provided for @pfmSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get pfmSortTooltip;

  /// No description provided for @pfmRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get pfmRefreshTooltip;

  /// No description provided for @pfmSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get pfmSortNameAsc;

  /// No description provided for @pfmSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name (Z–A)'**
  String get pfmSortNameDesc;

  /// No description provided for @pfmSortSizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Size (largest)'**
  String get pfmSortSizeLargest;

  /// No description provided for @pfmSortSizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Size (smallest)'**
  String get pfmSortSizeSmallest;

  /// No description provided for @pfmSortDateNewest.
  ///
  /// In en, this message translates to:
  /// **'Date (newest)'**
  String get pfmSortDateNewest;

  /// No description provided for @pfmSortDateOldest.
  ///
  /// In en, this message translates to:
  /// **'Date (oldest)'**
  String get pfmSortDateOldest;

  /// Tooltip and screen-reader name for the back arrow in the printer file manager's path bar — it goes up a directory, not back through the app.
  ///
  /// In en, this message translates to:
  /// **'Up one folder'**
  String get pfmUp;

  /// No description provided for @pfmSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get pfmSelectAll;

  /// No description provided for @pfmDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get pfmDeselectAll;

  /// No description provided for @pfmSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String pfmSelected(int count);

  /// No description provided for @pfmEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get pfmEmpty;

  /// No description provided for @pfmNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No files match your filter'**
  String get pfmNoMatches;

  /// No description provided for @pfmPrinterUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The printer did not answer, so its files could not be listed'**
  String get pfmPrinterUnavailable;

  /// No description provided for @pfmDownloadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The selection is too large for the server to bundle'**
  String get pfmDownloadTooLarge;

  /// No description provided for @pfmDownloadNoServerSpace.
  ///
  /// In en, this message translates to:
  /// **'The server has no room to prepare this download'**
  String get pfmDownloadNoServerSpace;

  /// No description provided for @pfmDownloadTookTooLong.
  ///
  /// In en, this message translates to:
  /// **'Preparing the download took too long and the server gave up'**
  String get pfmDownloadTookTooLong;

  /// No description provided for @pfmPreparingOnServer.
  ///
  /// In en, this message translates to:
  /// **'Preparing on the server…'**
  String get pfmPreparingOnServer;

  /// No description provided for @pfmDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get pfmDownloading;

  /// No description provided for @pfmDownloadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Download cancelled'**
  String get pfmDownloadCancelled;

  /// No description provided for @pfmDownloadPrepareFailed.
  ///
  /// In en, this message translates to:
  /// **'The server could not prepare this download'**
  String get pfmDownloadPrepareFailed;

  /// No description provided for @pfmDownloadPartial.
  ///
  /// In en, this message translates to:
  /// **'Left out {count, plural, one{one file} other{{count} files}} that could not be read from the printer'**
  String pfmDownloadPartial(int count);

  /// No description provided for @pfmDownloadSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get pfmDownloadSaved;

  /// No description provided for @pfmDownloadNotSaved.
  ///
  /// In en, this message translates to:
  /// **'The file could not be saved where you chose'**
  String get pfmDownloadNotSaved;

  /// No description provided for @pfmDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get pfmDownload;

  /// No description provided for @pfmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get pfmDelete;

  /// No description provided for @pfmDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete files?'**
  String get pfmDeleteConfirmTitle;

  /// No description provided for @pfmDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {count} {count, plural, one{file} other{files}} from the printer? This cannot be undone.'**
  String pfmDeleteConfirmBody(int count);

  /// No description provided for @pfmDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} {count, plural, one{file} other{files}}'**
  String pfmDeleted(int count);

  /// No description provided for @wearConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get wearConnectionFailed;

  /// No description provided for @wearNoPrinters.
  ///
  /// In en, this message translates to:
  /// **'No printers'**
  String get wearNoPrinters;

  /// No description provided for @wearPrinterUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Printer unavailable'**
  String get wearPrinterUnavailable;

  /// No description provided for @wearNoActions.
  ///
  /// In en, this message translates to:
  /// **'No actions available'**
  String get wearNoActions;

  /// Watch button, and the whole statement that the plate is waiting — the watch has no badge beside it. Worded here rather than reused from plateClearAction because that sentence wraps to a second line on a watch: every wear* label has to fit one line, which is why this family exists at all.
  ///
  /// In en, this message translates to:
  /// **'Clear plate'**
  String get wearClearPlate;

  /// Confirmation toast after that button. Short for the same reason as wearClearPlate — the phone's plateClearedSnack does not fit.
  ///
  /// In en, this message translates to:
  /// **'Plate cleared'**
  String get wearPlateCleared;

  /// No description provided for @wearPlateNeedsOnline.
  ///
  /// In en, this message translates to:
  /// **'This server needs the printer online'**
  String get wearPlateNeedsOnline;

  /// No description provided for @wearStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get wearStarted;

  /// No description provided for @wearPhoneUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Phone unreachable'**
  String get wearPhoneUnreachable;

  /// No description provided for @wearPhoneNoResponse.
  ///
  /// In en, this message translates to:
  /// **'Phone did not respond'**
  String get wearPhoneNoResponse;

  /// No description provided for @wearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get wearConfirm;

  /// No description provided for @wearServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get wearServerUrl;

  /// No description provided for @wearConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get wearConnect;

  /// No description provided for @wearAuthKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get wearAuthKey;

  /// No description provided for @wearAuthLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get wearAuthLogin;

  /// No description provided for @wearUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get wearUsername;

  /// No description provided for @wearSetupPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up from your phone'**
  String get wearSetupPhoneTitle;

  /// No description provided for @wearSetupPhoneBody.
  ///
  /// In en, this message translates to:
  /// **'Open Bambuddy on your paired phone — the watch takes the server and sign-in from it.'**
  String get wearSetupPhoneBody;

  /// No description provided for @wearSetupPhoneCheck.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get wearSetupPhoneCheck;

  /// No description provided for @wearSetupPhoneEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing from the phone yet.'**
  String get wearSetupPhoneEmpty;

  /// No description provided for @wearSetupManual.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get wearSetupManual;

  /// Watch setup: one tap into demo mode, no typing. Short by necessity — the phone's 'Try the demo' does not fit a line on a watch.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get wearSetupDemo;

  /// No description provided for @wearSetupTapToType.
  ///
  /// In en, this message translates to:
  /// **'Tap to type'**
  String get wearSetupTapToType;

  /// No description provided for @wearSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get wearSettingsTitle;

  /// No description provided for @wearFromPhone.
  ///
  /// In en, this message translates to:
  /// **'From your phone'**
  String get wearFromPhone;

  /// No description provided for @wearFromPhoneUse.
  ///
  /// In en, this message translates to:
  /// **'Use this server'**
  String get wearFromPhoneUse;

  /// No description provided for @wearFromPhoneLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get wearFromPhoneLater;

  /// No description provided for @wearAuthNone.
  ///
  /// In en, this message translates to:
  /// **'No sign-in'**
  String get wearAuthNone;

  /// No description provided for @wearFromPhoneWaiting.
  ///
  /// In en, this message translates to:
  /// **'The phone offers a different server.'**
  String get wearFromPhoneWaiting;

  /// No description provided for @wearCurrentServer.
  ///
  /// In en, this message translates to:
  /// **'Current server'**
  String get wearCurrentServer;

  /// Watch toast: the line under a transient message, saying a tap takes it away rather than waiting it out. Two letters because the message above it is what the room is for.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get wearOk;

  /// No description provided for @commonOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @commonAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get commonAuto;

  /// No description provided for @queueEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get queueEdit;

  /// No description provided for @queueEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Queue Item'**
  String get queueEditTitle;

  /// No description provided for @queueEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get queueEditSave;

  /// No description provided for @queueEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Queue item updated'**
  String get queueEditSaved;

  /// No description provided for @queueCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get queueCreateTitle;

  /// No description provided for @queueCreateSubmit.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get queueCreateSubmit;

  /// No description provided for @queueCreateAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get queueCreateAdded;

  /// No description provided for @queueEditPrintJob.
  ///
  /// In en, this message translates to:
  /// **'Print Job'**
  String get queueEditPrintJob;

  /// No description provided for @queueEditTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get queueEditTarget;

  /// No description provided for @queueEditSpecificPrinter.
  ///
  /// In en, this message translates to:
  /// **'Specific Printer'**
  String get queueEditSpecificPrinter;

  /// No description provided for @queueEditAnyModel.
  ///
  /// In en, this message translates to:
  /// **'Any {model}'**
  String queueEditAnyModel(String model);

  /// No description provided for @queueEditAnyModelGeneric.
  ///
  /// In en, this message translates to:
  /// **'Any Model'**
  String get queueEditAnyModelGeneric;

  /// No description provided for @queueEditTargetModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get queueEditTargetModel;

  /// No description provided for @queueEditTargetLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get queueEditTargetLocation;

  /// No description provided for @queueEditAnyLocation.
  ///
  /// In en, this message translates to:
  /// **'Any location'**
  String get queueEditAnyLocation;

  /// No description provided for @queueEditMappingNeedsPrinter.
  ///
  /// In en, this message translates to:
  /// **'Select a printer to map filaments'**
  String get queueEditMappingNeedsPrinter;

  /// No description provided for @queueEditMappingSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{slot} other{slots}} mapped'**
  String queueEditMappingSummary(int count);

  /// No description provided for @queueEditMappingAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (no manual mapping)'**
  String get queueEditMappingAuto;

  /// No description provided for @queueEditPlate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get queueEditPlate;

  /// No description provided for @queueEditPlateSelected.
  ///
  /// In en, this message translates to:
  /// **'Plate {plate}'**
  String queueEditPlateSelected(int plate);

  /// Plate number plus the plate's own name from the 3MF, when it has one
  ///
  /// In en, this message translates to:
  /// **'Plate {plate} · {name}'**
  String queueEditPlateNamed(int plate, String name);

  /// No description provided for @queueEditPlateFixed.
  ///
  /// In en, this message translates to:
  /// **'This job prints plate {plate}'**
  String queueEditPlateFixed(int plate);

  /// No description provided for @queuePlatePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Which plate?'**
  String get queuePlatePickTitle;

  /// No description provided for @queuePlateObjects.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No objects} =1{1 object} other{{count} objects}}'**
  String queuePlateObjects(int count);

  /// No description provided for @queueEditPrintOptions.
  ///
  /// In en, this message translates to:
  /// **'Print Options'**
  String get queueEditPrintOptions;

  /// No description provided for @queueOptBedLevelling.
  ///
  /// In en, this message translates to:
  /// **'Bed Levelling'**
  String get queueOptBedLevelling;

  /// No description provided for @queueOptBedLevellingDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-level bed before print'**
  String get queueOptBedLevellingDesc;

  /// No description provided for @queueOptFlowCali.
  ///
  /// In en, this message translates to:
  /// **'Flow Calibration'**
  String get queueOptFlowCali;

  /// No description provided for @queueOptFlowCaliDesc.
  ///
  /// In en, this message translates to:
  /// **'Calibrate extrusion flow'**
  String get queueOptFlowCaliDesc;

  /// No description provided for @queueOptVibrationCali.
  ///
  /// In en, this message translates to:
  /// **'Vibration Calibration'**
  String get queueOptVibrationCali;

  /// No description provided for @queueOptVibrationCaliDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduce ringing artifacts'**
  String get queueOptVibrationCaliDesc;

  /// No description provided for @queueOptLayerInspect.
  ///
  /// In en, this message translates to:
  /// **'First Layer Inspection'**
  String get queueOptLayerInspect;

  /// No description provided for @queueOptLayerInspectDesc.
  ///
  /// In en, this message translates to:
  /// **'AI inspection of first layer'**
  String get queueOptLayerInspectDesc;

  /// No description provided for @queueOptTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Timelapse'**
  String get queueOptTimelapse;

  /// No description provided for @queueOptTimelapseDesc.
  ///
  /// In en, this message translates to:
  /// **'Record timelapse video'**
  String get queueOptTimelapseDesc;

  /// No description provided for @queueOptNozzleOffset.
  ///
  /// In en, this message translates to:
  /// **'Nozzle Offset Calibration'**
  String get queueOptNozzleOffset;

  /// No description provided for @queueOptNozzleOffsetDesc.
  ///
  /// In en, this message translates to:
  /// **'Calibrate nozzle offsets between extruders'**
  String get queueOptNozzleOffsetDesc;

  /// No description provided for @queueEditPreheat.
  ///
  /// In en, this message translates to:
  /// **'Preheat & Heat Soak'**
  String get queueEditPreheat;

  /// No description provided for @queueEditPreheatDesc.
  ///
  /// In en, this message translates to:
  /// **'Heat the bed and chamber before this print starts. Defaults to the global Settings → Workflow toggle.'**
  String get queueEditPreheatDesc;

  /// No description provided for @queuePreheatInherit.
  ///
  /// In en, this message translates to:
  /// **'Inherit'**
  String get queuePreheatInherit;

  /// No description provided for @queueEditChamberTarget.
  ///
  /// In en, this message translates to:
  /// **'Chamber target override (°C, blank = filament default)'**
  String get queueEditChamberTarget;

  /// No description provided for @queueEditChamberTargetRange.
  ///
  /// In en, this message translates to:
  /// **'0–{max} °C'**
  String queueEditChamberTargetRange(int max);

  /// No description provided for @queueEditWhenToPrint.
  ///
  /// In en, this message translates to:
  /// **'When to print'**
  String get queueEditWhenToPrint;

  /// No description provided for @queueScheduleAsap.
  ///
  /// In en, this message translates to:
  /// **'ASAP'**
  String get queueScheduleAsap;

  /// No description provided for @queueScheduleQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueScheduleQueue;

  /// No description provided for @queueScheduleSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get queueScheduleSchedule;

  /// No description provided for @queueEditPickTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date & time'**
  String get queueEditPickTime;

  /// No description provided for @queueEditRequireManualStart.
  ///
  /// In en, this message translates to:
  /// **'Require manual start'**
  String get queueEditRequireManualStart;

  /// No description provided for @queueEditRequirePrevious.
  ///
  /// In en, this message translates to:
  /// **'Only start if previous print succeeded'**
  String get queueEditRequirePrevious;

  /// No description provided for @queueEditPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Power off printer when done'**
  String get queueEditPowerOff;

  /// No description provided for @queueEditGcodeInjection.
  ///
  /// In en, this message translates to:
  /// **'Inject auto-print G-code'**
  String get queueEditGcodeInjection;

  /// No description provided for @queueEditGcodeInjectionNoSnippet.
  ///
  /// In en, this message translates to:
  /// **'No G-code snippet for {model} — nothing will be injected.'**
  String queueEditGcodeInjectionNoSnippet(String model);

  /// No description provided for @queueEditNoModel.
  ///
  /// In en, this message translates to:
  /// **'Select a target model'**
  String get queueEditNoModel;

  /// No description provided for @queueEditNoPrinter.
  ///
  /// In en, this message translates to:
  /// **'Select a printer'**
  String get queueEditNoPrinter;

  /// No description provided for @queueEditFilamentOverride.
  ///
  /// In en, this message translates to:
  /// **'Filament Override'**
  String get queueEditFilamentOverride;

  /// No description provided for @queueEditFilamentOverrideDesc.
  ///
  /// In en, this message translates to:
  /// **'Optionally override filaments for model-based assignment. The scheduler matches against your selected filaments instead of the original 3MF values.'**
  String get queueEditFilamentOverrideDesc;

  /// No description provided for @queueEditNoFilamentReqs.
  ///
  /// In en, this message translates to:
  /// **'No filament requirements for this job.'**
  String get queueEditNoFilamentReqs;

  /// No description provided for @queueEditOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get queueEditOriginal;

  /// No description provided for @queueEditSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'Slot {slot} · {type}'**
  String queueEditSlotLabel(String slot, String type);

  /// No description provided for @queueEditForceColorMatch.
  ///
  /// In en, this message translates to:
  /// **'Force color match'**
  String get queueEditForceColorMatch;

  /// No description provided for @queueEditNozzleRack.
  ///
  /// In en, this message translates to:
  /// **'Nozzle rack'**
  String get queueEditNozzleRack;

  /// No description provided for @queueEditNozzleRackDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose which rack nozzle each filament prints from. Left automatic, a fitting position is picked when the print starts.'**
  String get queueEditNozzleRackDesc;

  /// No description provided for @queueEditRackGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Filament {slots} · {nozzle}'**
  String queueEditRackGroupLabel(String slots, String nozzle);

  /// No description provided for @queueEditRackAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get queueEditRackAuto;

  /// No description provided for @queueEditRackPosition.
  ///
  /// In en, this message translates to:
  /// **'Position {position} · {nozzle}'**
  String queueEditRackPosition(int position, String nozzle);

  /// No description provided for @queueEditRackPositionTaken.
  ///
  /// In en, this message translates to:
  /// **'Position {position} · {nozzle} — already chosen'**
  String queueEditRackPositionTaken(int position, String nozzle);

  /// No description provided for @queueEditRackPositionUnfit.
  ///
  /// In en, this message translates to:
  /// **'Position {position} · {nozzle} — does not fit'**
  String queueEditRackPositionUnfit(int position, String nozzle);

  /// No description provided for @queueEditRackEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get queueEditRackEmpty;

  /// No description provided for @queueEditRackPickStale.
  ///
  /// In en, this message translates to:
  /// **'The chosen position no longer fits this filament — pick another, or the print is refused at start.'**
  String get queueEditRackPickStale;

  /// No description provided for @queueEditRackNoFit.
  ///
  /// In en, this message translates to:
  /// **'No rack position holds a {nozzle} nozzle — fit one, or the printer decides for itself.'**
  String queueEditRackNoFit(String nozzle);

  /// No description provided for @nozzleFlowStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get nozzleFlowStandard;

  /// No description provided for @nozzleFlowHigh.
  ///
  /// In en, this message translates to:
  /// **'High flow'**
  String get nozzleFlowHigh;

  /// No description provided for @bugReportMenu.
  ///
  /// In en, this message translates to:
  /// **'Report a bug or an idea'**
  String get bugReportMenu;

  /// No description provided for @bugReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a bug or an idea'**
  String get bugReportTitle;

  /// No description provided for @bugReportIntroHeader.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get bugReportIntroHeader;

  /// No description provided for @bugReportStepRecord.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get bugReportStepRecord;

  /// No description provided for @bugReportStepReproduce.
  ///
  /// In en, this message translates to:
  /// **'Reproduce the problem'**
  String get bugReportStepReproduce;

  /// No description provided for @bugReportStepFinish.
  ///
  /// In en, this message translates to:
  /// **'Come back and finish'**
  String get bugReportStepFinish;

  /// No description provided for @bugReportLogScreens.
  ///
  /// In en, this message translates to:
  /// **'Screens you open and buttons you press'**
  String get bugReportLogScreens;

  /// No description provided for @bugReportLogRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests to the server and its answers'**
  String get bugReportLogRequests;

  /// No description provided for @bugReportLogService.
  ///
  /// In en, this message translates to:
  /// **'The live view, and which notifications the background service posted or skipped'**
  String get bugReportLogService;

  /// No description provided for @bugReportLogErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors and crashes, including the ones you never see'**
  String get bugReportLogErrors;

  /// No description provided for @bugReportLogSetup.
  ///
  /// In en, this message translates to:
  /// **'App and server version, your phone, your language'**
  String get bugReportLogSetup;

  /// No description provided for @bugReportLogNoKey.
  ///
  /// In en, this message translates to:
  /// **'Your API key or password'**
  String get bugReportLogNoKey;

  /// No description provided for @bugReportLogNoTyping.
  ///
  /// In en, this message translates to:
  /// **'The text you type'**
  String get bugReportLogNoTyping;

  /// No description provided for @bugReportLogNoAddress.
  ///
  /// In en, this message translates to:
  /// **'Your server address — only http or https, name or IP, and the port'**
  String get bugReportLogNoAddress;

  /// No description provided for @bugReportLogNoData.
  ///
  /// In en, this message translates to:
  /// **'Printer serial numbers, or the names of your files, models and spools'**
  String get bugReportLogNoData;

  /// No description provided for @bugReportReviewFirst.
  ///
  /// In en, this message translates to:
  /// **'You read all of it before it leaves the phone.'**
  String get bugReportReviewFirst;

  /// No description provided for @bugReportPrivacyHeader.
  ///
  /// In en, this message translates to:
  /// **'What ends up in the log'**
  String get bugReportPrivacyHeader;

  /// No description provided for @bugReportStart.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get bugReportStart;

  /// No description provided for @bugReportRecordingHeader.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get bugReportRecordingHeader;

  /// No description provided for @bugReportRecordingBody.
  ///
  /// In en, this message translates to:
  /// **'Go back to the app and reproduce the problem. The recording bar stays with you — drag it aside or collapse it if it gets in the way, and use it to mark the moment it breaks and to finish.'**
  String get bugReportRecordingBody;

  /// No description provided for @bugReportMark.
  ///
  /// In en, this message translates to:
  /// **'Mark the moment'**
  String get bugReportMark;

  /// No description provided for @bugReportMarked.
  ///
  /// In en, this message translates to:
  /// **'Moment marked'**
  String get bugReportMarked;

  /// No description provided for @bugReportStop.
  ///
  /// In en, this message translates to:
  /// **'Finish recording'**
  String get bugReportStop;

  /// No description provided for @bugReportStopShort.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get bugReportStopShort;

  /// No description provided for @bugReportBannerLabel.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get bugReportBannerLabel;

  /// No description provided for @bugReportBarMove.
  ///
  /// In en, this message translates to:
  /// **'Move the recording bar'**
  String get bugReportBarMove;

  /// No description provided for @bugReportBarCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse the recording bar'**
  String get bugReportBarCollapse;

  /// No description provided for @bugReportBarExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand the recording bar'**
  String get bugReportBarExpand;

  /// No description provided for @bugReportReviewHeader.
  ///
  /// In en, this message translates to:
  /// **'Review before sending'**
  String get bugReportReviewHeader;

  /// No description provided for @bugReportReviewBody.
  ///
  /// In en, this message translates to:
  /// **'This is everything that was recorded. Read it through — below you choose whether it stays on the phone or goes out as a public issue.'**
  String get bugReportReviewBody;

  /// No description provided for @bugReportSummary.
  ///
  /// In en, this message translates to:
  /// **'{records} records · {errors} errors · {warnings} warnings'**
  String bugReportSummary(int records, int errors, int warnings);

  /// No description provided for @bugReportMarkers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 marked moment} other{{count} marked moments}}'**
  String bugReportMarkers(int count);

  /// No description provided for @bugReportTruncated.
  ///
  /// In en, this message translates to:
  /// **'The session was long — the oldest records were dropped.'**
  String get bugReportTruncated;

  /// No description provided for @bugReportEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing was recorded.'**
  String get bugReportEmpty;

  /// No description provided for @bugReportShowRaw.
  ///
  /// In en, this message translates to:
  /// **'Show raw log'**
  String get bugReportShowRaw;

  /// No description provided for @bugReportHideRaw.
  ///
  /// In en, this message translates to:
  /// **'Hide raw log'**
  String get bugReportHideRaw;

  /// No description provided for @bugReportRawClipped.
  ///
  /// In en, this message translates to:
  /// **'The first {kb} kB are not shown here. The file you save holds the whole session.'**
  String bugReportRawClipped(int kb);

  /// No description provided for @bugReportSave.
  ///
  /// In en, this message translates to:
  /// **'Save to a file'**
  String get bugReportSave;

  /// No description provided for @bugReportSaveShort.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bugReportSaveShort;

  /// No description provided for @bugReportSaved.
  ///
  /// In en, this message translates to:
  /// **'Log saved to the file'**
  String get bugReportSaved;

  /// No description provided for @bugReportSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The log could not be saved.'**
  String get bugReportSaveFailed;

  /// No description provided for @bugReportDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get bugReportDiscard;

  /// No description provided for @bugReportDiscardQuestion.
  ///
  /// In en, this message translates to:
  /// **'Discard this recording?'**
  String get bugReportDiscardQuestion;

  /// No description provided for @bugReportDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The log will be deleted from the phone.'**
  String get bugReportDiscardBody;

  /// No description provided for @bugReportDiscardBodyQueued.
  ///
  /// In en, this message translates to:
  /// **'The log will be deleted from the phone and the queued report cancelled.'**
  String get bugReportDiscardBodyQueued;

  /// No description provided for @bugReportLimit.
  ///
  /// In en, this message translates to:
  /// **'A recording stops by itself after {minutes} minutes.'**
  String bugReportLimit(int minutes);

  /// No description provided for @bugReportLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Recording finished — the {minutes} minute limit was reached.'**
  String bugReportLimitReached(int minutes);

  /// No description provided for @bugReportSizeLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Recording finished — the log reached its {megabytes} MB limit.'**
  String bugReportSizeLimitReached(int megabytes);

  /// No description provided for @bugReportShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get bugReportShow;

  /// No description provided for @bugReportRecoveredHeader.
  ///
  /// In en, this message translates to:
  /// **'A recording survived a crash'**
  String get bugReportRecoveredHeader;

  /// No description provided for @bugReportRecoveredBody.
  ///
  /// In en, this message translates to:
  /// **'The app closed while it was recording. What it had written down is still on the phone — look at it, or throw it away.'**
  String get bugReportRecoveredBody;

  /// No description provided for @bugReportDestinationHeader.
  ///
  /// In en, this message translates to:
  /// **'What happens to this log'**
  String get bugReportDestinationHeader;

  /// No description provided for @bugReportDestinationFile.
  ///
  /// In en, this message translates to:
  /// **'Save to a file'**
  String get bugReportDestinationFile;

  /// No description provided for @bugReportDestinationIssue.
  ///
  /// In en, this message translates to:
  /// **'Report on GitHub'**
  String get bugReportDestinationIssue;

  /// No description provided for @bugReportDestinationFileBody.
  ///
  /// In en, this message translates to:
  /// **'The log is saved where you choose and stays on your phone. You decide whether to send it anywhere.'**
  String get bugReportDestinationFileBody;

  /// No description provided for @bugReportDestinationIssueBody.
  ///
  /// In en, this message translates to:
  /// **'The log and your description are posted as a public issue on GitHub, where anyone can read them and they stay for good. Go through the log below first.'**
  String get bugReportDestinationIssueBody;

  /// No description provided for @bugReportDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'What went wrong?'**
  String get bugReportDescriptionLabel;

  /// No description provided for @bugReportDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What were you doing, what did you expect, what happened instead.'**
  String get bugReportDescriptionHint;

  /// No description provided for @bugReportDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Say what went wrong — a log with no description is nearly unusable.'**
  String get bugReportDescriptionRequired;

  /// No description provided for @bugReportSend.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get bugReportSend;

  /// No description provided for @bugReportSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get bugReportSending;

  /// No description provided for @bugReportSendWaiting.
  ///
  /// In en, this message translates to:
  /// **'Sending in {clock}'**
  String bugReportSendWaiting(String clock);

  /// No description provided for @bugReportSendWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'The relay spaces reports out. You can leave this screen — it goes on its own.'**
  String get bugReportSendWaitingBody;

  /// No description provided for @bugReportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get bugReportSent;

  /// No description provided for @bugReportSentBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you. The issue is open and the log is attached to it.'**
  String get bugReportSentBody;

  /// No description provided for @bugReportOpenIssue.
  ///
  /// In en, this message translates to:
  /// **'Open the issue'**
  String get bugReportOpenIssue;

  /// No description provided for @bugReportDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get bugReportDone;

  /// No description provided for @bugReportSendFailedNotYet.
  ///
  /// In en, this message translates to:
  /// **'The relay is not accepting reports right now. Try again later, or save the log to a file.'**
  String get bugReportSendFailedNotYet;

  /// No description provided for @bugReportSendFailedRefused.
  ///
  /// In en, this message translates to:
  /// **'The relay refused this report. Save the log to a file and attach it yourself.'**
  String get bugReportSendFailedRefused;

  /// No description provided for @bugReportSendFailedDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This one has already been reported.'**
  String get bugReportSendFailedDuplicate;

  /// No description provided for @bugReportSendFailedUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the relay. Check the connection, or save the log to a file.'**
  String get bugReportSendFailedUnreachable;

  /// No description provided for @bugReportSendFailedRejected.
  ///
  /// In en, this message translates to:
  /// **'The relay rejected this report. Save the log to a file and attach it yourself.'**
  String get bugReportSendFailedRejected;

  /// No description provided for @bugReportSendFailedDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode does not publish reports. Save the log to a file instead.'**
  String get bugReportSendFailedDemo;

  /// No description provided for @bugReportKindQuestion.
  ///
  /// In en, this message translates to:
  /// **'What are you reporting?'**
  String get bugReportKindQuestion;

  /// No description provided for @bugReportKindBug.
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get bugReportKindBug;

  /// No description provided for @bugReportKindChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get bugReportKindChange;

  /// No description provided for @bugReportKindFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get bugReportKindFeature;

  /// No description provided for @bugReportChangeHeader.
  ///
  /// In en, this message translates to:
  /// **'Request a change'**
  String get bugReportChangeHeader;

  /// No description provided for @bugReportChangeBody.
  ///
  /// In en, this message translates to:
  /// **'Something works, but not the way it should.'**
  String get bugReportChangeBody;

  /// No description provided for @bugReportChangeLabel.
  ///
  /// In en, this message translates to:
  /// **'What should change?'**
  String get bugReportChangeLabel;

  /// No description provided for @bugReportChangeHint.
  ///
  /// In en, this message translates to:
  /// **'What it does now, and what it should do instead.'**
  String get bugReportChangeHint;

  /// No description provided for @bugReportFeatureHeader.
  ///
  /// In en, this message translates to:
  /// **'Request a feature'**
  String get bugReportFeatureHeader;

  /// No description provided for @bugReportFeatureBody.
  ///
  /// In en, this message translates to:
  /// **'Something the app cannot do yet.'**
  String get bugReportFeatureBody;

  /// No description provided for @bugReportFeatureLabel.
  ///
  /// In en, this message translates to:
  /// **'What is missing?'**
  String get bugReportFeatureLabel;

  /// No description provided for @bugReportFeatureHint.
  ///
  /// In en, this message translates to:
  /// **'What you want to do, and why the app does not let you.'**
  String get bugReportFeatureHint;

  /// No description provided for @bugReportRequestPrivacyHeader.
  ///
  /// In en, this message translates to:
  /// **'What gets sent'**
  String get bugReportRequestPrivacyHeader;

  /// No description provided for @bugReportRequestWhatYouWrite.
  ///
  /// In en, this message translates to:
  /// **'What you write'**
  String get bugReportRequestWhatYouWrite;

  /// No description provided for @bugReportRequestVersions.
  ///
  /// In en, this message translates to:
  /// **'App and server version'**
  String get bugReportRequestVersions;

  /// No description provided for @bugReportRequestNoLog.
  ///
  /// In en, this message translates to:
  /// **'No log, no recording'**
  String get bugReportRequestNoLog;

  /// No description provided for @bugReportRequestNoData.
  ///
  /// In en, this message translates to:
  /// **'Nothing about your printers or your phone'**
  String get bugReportRequestNoData;

  /// No description provided for @bugReportRequestPublic.
  ///
  /// In en, this message translates to:
  /// **'It becomes a public issue on GitHub — anyone can read it, and it stays.'**
  String get bugReportRequestPublic;

  /// No description provided for @bugReportRequestRequired.
  ///
  /// In en, this message translates to:
  /// **'Write what you are asking for — an empty request cannot be acted on.'**
  String get bugReportRequestRequired;

  /// No description provided for @bugReportRequestSentBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you. The issue is open.'**
  String get bugReportRequestSentBody;

  /// No description provided for @bugReportCancelSend.
  ///
  /// In en, this message translates to:
  /// **'Cancel sending'**
  String get bugReportCancelSend;

  /// No description provided for @bugReportRequestFailedNotYet.
  ///
  /// In en, this message translates to:
  /// **'The relay is not accepting reports right now. Try again later.'**
  String get bugReportRequestFailedNotYet;

  /// No description provided for @bugReportRequestFailedRefused.
  ///
  /// In en, this message translates to:
  /// **'The relay refused this request. You can open the issue yourself on GitHub.'**
  String get bugReportRequestFailedRefused;

  /// No description provided for @bugReportRequestFailedUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the relay. Check the connection and try again.'**
  String get bugReportRequestFailedUnreachable;

  /// No description provided for @bugReportRequestFailedDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode does not publish reports.'**
  String get bugReportRequestFailedDemo;

  /// No description provided for @bugReportRequestNotPrepared.
  ///
  /// In en, this message translates to:
  /// **'The app could not put the report together. Nothing was sent — try again.'**
  String get bugReportRequestNotPrepared;

  /// No description provided for @usersTitle.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersTitle;

  /// No description provided for @usersMenu.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersMenu;

  /// No description provided for @usersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts on this server.'**
  String get usersEmpty;

  /// No description provided for @usersYou.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get usersYou;

  /// No description provided for @usersRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get usersRoleAdmin;

  /// No description provided for @usersRoleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get usersRoleUser;

  /// No description provided for @usersInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get usersInactive;

  /// No description provided for @usersEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get usersEmailLabel;

  /// No description provided for @usersEmailNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get usersEmailNone;

  /// No description provided for @usersGroupsLabel.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get usersGroupsLabel;

  /// No description provided for @usersNoGroups.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get usersNoGroups;

  /// No description provided for @usersPermissionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get usersPermissionsLabel;

  /// No description provided for @usersPermissionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none} =1{1 permission} other{{count} permissions}}'**
  String usersPermissionsCount(int count);

  /// No description provided for @usersPermissionsUnknown.
  ///
  /// In en, this message translates to:
  /// **'not reported by the server'**
  String get usersPermissionsUnknown;

  /// No description provided for @usersAuthSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Sign-in'**
  String get usersAuthSourceLabel;

  /// No description provided for @usersAuthSourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local account'**
  String get usersAuthSourceLocal;

  /// No description provided for @usersCreatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get usersCreatedLabel;

  /// No description provided for @usersOwnedTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATED BY THIS ACCOUNT'**
  String get usersOwnedTitle;

  /// No description provided for @usersOwnedArchives.
  ///
  /// In en, this message translates to:
  /// **'Prints'**
  String get usersOwnedArchives;

  /// No description provided for @usersOwnedQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get usersOwnedQueue;

  /// No description provided for @usersOwnedLibrary.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get usersOwnedLibrary;

  /// No description provided for @usersOwnedFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read what this account owns.'**
  String get usersOwnedFailed;

  /// No description provided for @usersCreate.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get usersCreate;

  /// No description provided for @usersCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get usersCreateTitle;

  /// No description provided for @usersEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get usersEdit;

  /// No description provided for @usersEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get usersEditTitle;

  /// No description provided for @usersDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get usersDelete;

  /// No description provided for @usersSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get usersSave;

  /// No description provided for @usersSaved.
  ///
  /// In en, this message translates to:
  /// **'Account saved'**
  String get usersSaved;

  /// No description provided for @usersSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The account could not be saved.'**
  String get usersSaveFailed;

  /// No description provided for @usersDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get usersDeleted;

  /// No description provided for @usersFieldUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usersFieldUsername;

  /// No description provided for @usersFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail (optional)'**
  String get usersFieldEmail;

  /// No description provided for @usersFieldEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get usersFieldEmailRequired;

  /// No description provided for @usersFieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get usersFieldPassword;

  /// No description provided for @usersFieldNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get usersFieldNewPassword;

  /// No description provided for @usersFieldConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat the password'**
  String get usersFieldConfirmPassword;

  /// No description provided for @usersFieldActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get usersFieldActive;

  /// No description provided for @usersFieldGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get usersFieldGroups;

  /// No description provided for @usersGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'(built-in)'**
  String get usersGroupSystem;

  /// No description provided for @usersFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Fill this in'**
  String get usersFieldRequired;

  /// No description provided for @usersPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords are different.'**
  String get usersPasswordsDoNotMatch;

  /// No description provided for @usersGroupsAdminHint.
  ///
  /// In en, this message translates to:
  /// **'Membership of Administrators is what makes an account an admin.'**
  String get usersGroupsAdminHint;

  /// No description provided for @usersActiveHint.
  ///
  /// In en, this message translates to:
  /// **'An inactive account cannot sign in.'**
  String get usersActiveHint;

  /// No description provided for @usersEmailAdvancedHint.
  ///
  /// In en, this message translates to:
  /// **'This server mails the password, so it needs an address.'**
  String get usersEmailAdvancedHint;

  /// No description provided for @usersPasswordMailed.
  ///
  /// In en, this message translates to:
  /// **'The server picks the password itself and mails it to this address. Nobody, including you, gets to see it.'**
  String get usersPasswordMailed;

  /// No description provided for @usersNoSmtpWarning.
  ///
  /// In en, this message translates to:
  /// **'No mail server is configured, so that message will not arrive — the account would be created with a password nobody knows.'**
  String get usersNoSmtpWarning;

  /// No description provided for @usersLdapPasswordNote.
  ///
  /// In en, this message translates to:
  /// **'This account signs in through the directory (LDAP). Its password lives there and cannot be set from here.'**
  String get usersLdapPasswordNote;

  /// No description provided for @usersPasswordKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the current password.'**
  String get usersPasswordKeepHint;

  /// No description provided for @usersPasswordRulesHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, with an upper and lower case letter, a digit and a symbol.'**
  String get usersPasswordRulesHint;

  /// No description provided for @usersPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters.'**
  String get usersPasswordTooShort;

  /// No description provided for @usersPasswordNoUppercase.
  ///
  /// In en, this message translates to:
  /// **'Add an upper case letter.'**
  String get usersPasswordNoUppercase;

  /// No description provided for @usersPasswordNoLowercase.
  ///
  /// In en, this message translates to:
  /// **'Add a lower case letter.'**
  String get usersPasswordNoLowercase;

  /// No description provided for @usersPasswordNoDigit.
  ///
  /// In en, this message translates to:
  /// **'Add a digit.'**
  String get usersPasswordNoDigit;

  /// No description provided for @usersPasswordNoSpecial.
  ///
  /// In en, this message translates to:
  /// **'Add a symbol.'**
  String get usersPasswordNoSpecial;

  /// No description provided for @usersDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {username}?'**
  String usersDeleteTitle(String username);

  /// No description provided for @usersDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The account, its API keys and its sign-in state are removed. This cannot be undone.'**
  String get usersDeleteBody;

  /// No description provided for @usersDeleteOwnsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This account created 1 item} other{This account created {count} items}}'**
  String usersDeleteOwnsCount(int count);

  /// No description provided for @usersDeleteItemsToo.
  ///
  /// In en, this message translates to:
  /// **'Delete them too'**
  String get usersDeleteItemsToo;

  /// No description provided for @usersDeleteItemsTooHint.
  ///
  /// In en, this message translates to:
  /// **'Their prints, queue items and files are deleted with the account.'**
  String get usersDeleteItemsTooHint;

  /// No description provided for @usersDeleteItemsKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Their prints, queue items and files stay, with no owner.'**
  String get usersDeleteItemsKeepHint;

  /// No description provided for @usersDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get usersDeleteConfirm;

  /// No description provided for @usersErrLastAdmin.
  ///
  /// In en, this message translates to:
  /// **'This is the last admin — the server keeps one.'**
  String get usersErrLastAdmin;

  /// No description provided for @usersErrLastAdminDelete.
  ///
  /// In en, this message translates to:
  /// **'The last admin cannot be deleted — the server would be left with nobody who can manage it.'**
  String get usersErrLastAdminDelete;

  /// No description provided for @usersErrLastAdminDeactivate.
  ///
  /// In en, this message translates to:
  /// **'The last admin cannot be deactivated — the server would be left with nobody who can manage it.'**
  String get usersErrLastAdminDeactivate;

  /// No description provided for @usersErrLastAdminRole.
  ///
  /// In en, this message translates to:
  /// **'The last admin cannot be demoted — the server would be left with nobody who can manage it.'**
  String get usersErrLastAdminRole;

  /// No description provided for @usersErrSelfDelete.
  ///
  /// In en, this message translates to:
  /// **'You cannot delete the account you are signed in with.'**
  String get usersErrSelfDelete;

  /// No description provided for @usersErrUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'That username is taken.'**
  String get usersErrUsernameTaken;

  /// No description provided for @usersErrEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'That e-mail is already on another account.'**
  String get usersErrEmailTaken;

  /// No description provided for @usersErrLdapPassword.
  ///
  /// In en, this message translates to:
  /// **'The password of a directory (LDAP) account cannot be set here.'**
  String get usersErrLdapPassword;

  /// No description provided for @usersErrEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'This server needs an e-mail address for a new account.'**
  String get usersErrEmailRequired;

  /// No description provided for @usersErrPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'This server needs a password for a new account.'**
  String get usersErrPasswordRequired;

  /// No description provided for @usersErrGroupsInvalid.
  ///
  /// In en, this message translates to:
  /// **'One of the groups no longer exists — reopen the form.'**
  String get usersErrGroupsInvalid;

  /// No description provided for @groupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsTitle;

  /// No description provided for @groupsMenu.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsMenu;

  /// No description provided for @groupsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No groups on this server.'**
  String get groupsEmpty;

  /// No description provided for @groupsNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get groupsNoDescription;

  /// No description provided for @groupsSystemPill.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get groupsSystemPill;

  /// No description provided for @groupsSystemNote.
  ///
  /// In en, this message translates to:
  /// **'A built-in group cannot be renamed and what it grants is fixed — only who is in it can change.'**
  String get groupsSystemNote;

  /// No description provided for @groupsMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no accounts} =1{1 account} other{{count} accounts}}'**
  String groupsMemberCount(int count);

  /// No description provided for @groupsPermissionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no permissions} =1{1 permission} other{{count} permissions}}'**
  String groupsPermissionCount(int count);

  /// No description provided for @groupsMembersHeader.
  ///
  /// In en, this message translates to:
  /// **'MEMBERS'**
  String get groupsMembersHeader;

  /// No description provided for @groupsNoMembers.
  ///
  /// In en, this message translates to:
  /// **'Nobody is in this group.'**
  String get groupsNoMembers;

  /// No description provided for @groupsAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get groupsAddMember;

  /// No description provided for @groupsAddMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to {group}'**
  String groupsAddMemberTitle(String group);

  /// No description provided for @groupsEveryoneIsIn.
  ///
  /// In en, this message translates to:
  /// **'Every account is already in this group.'**
  String get groupsEveryoneIsIn;

  /// No description provided for @groupsRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get groupsRemoveMember;

  /// No description provided for @groupsRemoveMemberQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove {username} from {group}?'**
  String groupsRemoveMemberQuestion(String username, String group);

  /// No description provided for @groupsRemoveMemberBody.
  ///
  /// In en, this message translates to:
  /// **'The account stays, and loses what this group granted it.'**
  String get groupsRemoveMemberBody;

  /// No description provided for @groupsCreate.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupsCreate;

  /// No description provided for @groupsCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupsCreateTitle;

  /// No description provided for @groupsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get groupsEditTitle;

  /// No description provided for @groupsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupsDelete;

  /// No description provided for @groupsSaved.
  ///
  /// In en, this message translates to:
  /// **'Group saved'**
  String get groupsSaved;

  /// No description provided for @groupsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Group deleted'**
  String get groupsDeleted;

  /// No description provided for @groupsDeleteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete {group}?'**
  String groupsDeleteQuestion(String group);

  /// No description provided for @groupsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The permissions it grants disappear with it.'**
  String get groupsDeleteBody;

  /// No description provided for @groupsDeleteBodyWithMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account is in it and stays — it just loses what this group granted.} other{{count} accounts are in it and stay — they just lose what this group granted.}}'**
  String groupsDeleteBodyWithMembers(int count);

  /// No description provided for @groupsFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get groupsFieldName;

  /// No description provided for @groupsFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'What it is for'**
  String get groupsFieldDescription;

  /// No description provided for @groupsSystemFormNote.
  ///
  /// In en, this message translates to:
  /// **'A built-in group: its name and permissions are fixed by the server. Only the description can be changed here.'**
  String get groupsSystemFormNote;

  /// No description provided for @groupsPermissionsHeader.
  ///
  /// In en, this message translates to:
  /// **'PERMISSIONS'**
  String get groupsPermissionsHeader;

  /// No description provided for @groupsPermissionsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String groupsPermissionsSelected(int count);

  /// No description provided for @groupsAdvancedPermissions.
  ///
  /// In en, this message translates to:
  /// **'Server administration'**
  String get groupsAdvancedPermissions;

  /// No description provided for @groupsAdvancedHint.
  ///
  /// In en, this message translates to:
  /// **'Users, API keys, settings, backups — everything the app itself has no screen for.'**
  String get groupsAdvancedHint;

  /// No description provided for @adminMenu.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get adminMenu;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get adminTitle;

  /// No description provided for @adminSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {username}'**
  String adminSignedInAs(String username);

  /// No description provided for @adminUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who has an account, and what each of them may do'**
  String get adminUsersSubtitle;

  /// No description provided for @adminGroupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permission sets and who holds them'**
  String get adminGroupsSubtitle;

  /// No description provided for @adminApiKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Credentials for everything that is not this app'**
  String get adminApiKeysSubtitle;

  /// No description provided for @apiKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get apiKeysTitle;

  /// No description provided for @apiKeysEmpty.
  ///
  /// In en, this message translates to:
  /// **'No keys have been issued.'**
  String get apiKeysEmpty;

  /// No description provided for @apiKeysCreate.
  ///
  /// In en, this message translates to:
  /// **'New key'**
  String get apiKeysCreate;

  /// No description provided for @apiKeysCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New API key'**
  String get apiKeysCreateTitle;

  /// No description provided for @apiKeysEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit key'**
  String get apiKeysEditTitle;

  /// No description provided for @apiKeysSaved.
  ///
  /// In en, this message translates to:
  /// **'Key saved'**
  String get apiKeysSaved;

  /// No description provided for @apiKeysRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get apiKeysRevoke;

  /// No description provided for @apiKeysRevoked.
  ///
  /// In en, this message translates to:
  /// **'Key revoked'**
  String get apiKeysRevoked;

  /// No description provided for @apiKeysRevokeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Revoke {name}?'**
  String apiKeysRevokeQuestion(String name);

  /// No description provided for @apiKeysRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'Whatever uses this key stops working at once. This cannot be undone — a new key would have to be issued.'**
  String get apiKeysRevokeBody;

  /// No description provided for @apiKeysLastUsed.
  ///
  /// In en, this message translates to:
  /// **'last used {date}'**
  String apiKeysLastUsed(String date);

  /// No description provided for @apiKeysNeverUsed.
  ///
  /// In en, this message translates to:
  /// **'never used'**
  String get apiKeysNeverUsed;

  /// No description provided for @apiKeysDisabled.
  ///
  /// In en, this message translates to:
  /// **'Switched off'**
  String get apiKeysDisabled;

  /// No description provided for @apiKeysExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get apiKeysExpired;

  /// No description provided for @apiKeysExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'until {date}'**
  String apiKeysExpiresOn(String date);

  /// No description provided for @apiKeysPrinterLimited.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 printer} other{{count} printers}}'**
  String apiKeysPrinterLimited(int count);

  /// No description provided for @apiKeysLegacy.
  ///
  /// In en, this message translates to:
  /// **'No owner'**
  String get apiKeysLegacy;

  /// No description provided for @apiKeysFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get apiKeysFieldName;

  /// No description provided for @apiKeysFieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'What holds this key — \"Home Assistant\", \"SpoolBuddy\".'**
  String get apiKeysFieldNameHint;

  /// No description provided for @apiKeysFieldEnabled.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get apiKeysFieldEnabled;

  /// No description provided for @apiKeysFieldEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Switching it off stops the key working without deleting it.'**
  String get apiKeysFieldEnabledHint;

  /// No description provided for @apiKeysScopesHeader.
  ///
  /// In en, this message translates to:
  /// **'WHAT IT MAY DO'**
  String get apiKeysScopesHeader;

  /// No description provided for @apiKeysScopesHint.
  ///
  /// In en, this message translates to:
  /// **'A key can never manage accounts, groups, keys or settings — the server refuses those to every key.'**
  String get apiKeysScopesHint;

  /// No description provided for @apiKeysPrintersHeader.
  ///
  /// In en, this message translates to:
  /// **'PRINTERS'**
  String get apiKeysPrintersHeader;

  /// No description provided for @apiKeysAllPrinters.
  ///
  /// In en, this message translates to:
  /// **'All printers'**
  String get apiKeysAllPrinters;

  /// No description provided for @apiKeysAllPrintersHint.
  ///
  /// In en, this message translates to:
  /// **'Off: pick which printers this key may touch.'**
  String get apiKeysAllPrintersHint;

  /// No description provided for @apiKeysExpiryHeader.
  ///
  /// In en, this message translates to:
  /// **'EXPIRY'**
  String get apiKeysExpiryHeader;

  /// No description provided for @apiKeysNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'Does not expire'**
  String get apiKeysNoExpiry;

  /// No description provided for @apiKeysExpiryHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to pick a date after which the key stops working.'**
  String get apiKeysExpiryHint;

  /// No description provided for @apiKeysExpiryClear.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get apiKeysExpiryClear;

  /// No description provided for @apiKeysCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Key created'**
  String get apiKeysCreatedTitle;

  /// No description provided for @apiKeysCreatedWarning.
  ///
  /// In en, this message translates to:
  /// **'Copy it now. The server keeps only a hash — this is the last time it can be shown.'**
  String get apiKeysCreatedWarning;

  /// No description provided for @apiKeysCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get apiKeysCopy;

  /// No description provided for @apiKeysCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get apiKeysCopied;

  /// No description provided for @apiKeysCreatedDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get apiKeysCreatedDone;

  /// No description provided for @apiKeyScopeRead.
  ///
  /// In en, this message translates to:
  /// **'Read status'**
  String get apiKeyScopeRead;

  /// No description provided for @apiKeyScopeReadHint.
  ///
  /// In en, this message translates to:
  /// **'Printers, queue, archive, library, statistics — reading only.'**
  String get apiKeyScopeReadHint;

  /// No description provided for @apiKeyScopeQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get apiKeyScopeQueue;

  /// No description provided for @apiKeyScopeControl.
  ///
  /// In en, this message translates to:
  /// **'Control printers'**
  String get apiKeyScopeControl;

  /// No description provided for @apiKeyScopeControlHint.
  ///
  /// In en, this message translates to:
  /// **'Pause, stop, temperatures, AMS, smart plugs.'**
  String get apiKeyScopeControlHint;

  /// No description provided for @apiKeyScopeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get apiKeyScopeLibrary;

  /// No description provided for @apiKeyScopeInventory.
  ///
  /// In en, this message translates to:
  /// **'Filaments'**
  String get apiKeyScopeInventory;

  /// No description provided for @apiKeyScopeMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get apiKeyScopeMaintenance;

  /// No description provided for @apiKeyScopeArchives.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get apiKeyScopeArchives;

  /// No description provided for @apiKeyScopeProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get apiKeyScopeProjects;

  /// No description provided for @apiKeyScopeCloud.
  ///
  /// In en, this message translates to:
  /// **'Bambu Cloud'**
  String get apiKeyScopeCloud;

  /// No description provided for @apiKeyScopeCloudHint.
  ///
  /// In en, this message translates to:
  /// **'Reads the cloud on behalf of the account that creates the key. Needs authentication switched on server-side.'**
  String get apiKeyScopeCloudHint;

  /// No description provided for @apiKeyScopeEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy price'**
  String get apiKeyScopeEnergy;

  /// No description provided for @apiKeyScopeEnergyHint.
  ///
  /// In en, this message translates to:
  /// **'The one settings value a key may write — for a dynamic tariff.'**
  String get apiKeyScopeEnergyHint;

  /// No description provided for @printLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Print log'**
  String get printLogTitle;

  /// No description provided for @printLogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search runs'**
  String get printLogSearchHint;

  /// No description provided for @printLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs recorded yet'**
  String get printLogEmpty;

  /// No description provided for @printLogNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No runs match your filters'**
  String get printLogNoMatches;

  /// No description provided for @printLogLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the print log'**
  String get printLogLoadFailed;

  /// No description provided for @printLogFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get printLogFilters;

  /// No description provided for @printLogFilterPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get printLogFilterPrinter;

  /// No description provided for @printLogFilterUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get printLogFilterUser;

  /// No description provided for @printLogFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get printLogFilterStatus;

  /// No description provided for @printLogFilterDates.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get printLogFilterDates;

  /// No description provided for @printLogAnyPrinter.
  ///
  /// In en, this message translates to:
  /// **'Any printer'**
  String get printLogAnyPrinter;

  /// No description provided for @printLogAnyUser.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get printLogAnyUser;

  /// No description provided for @printLogAnyStatus.
  ///
  /// In en, this message translates to:
  /// **'Any status'**
  String get printLogAnyStatus;

  /// No description provided for @printLogNoUser.
  ///
  /// In en, this message translates to:
  /// **'No user'**
  String get printLogNoUser;

  /// No description provided for @printLogOrphan.
  ///
  /// In en, this message translates to:
  /// **'Archive deleted'**
  String get printLogOrphan;

  /// No description provided for @printLogShowing.
  ///
  /// In en, this message translates to:
  /// **'{loaded} of {total}'**
  String printLogShowing(int loaded, int total);

  /// No description provided for @printLogLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get printLogLoadMore;

  /// No description provided for @printLogSort.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get printLogSort;

  /// No description provided for @printLogSortDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get printLogSortDate;

  /// No description provided for @printLogSortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get printLogSortName;

  /// No description provided for @printLogSortPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get printLogSortPrinter;

  /// No description provided for @printLogSortUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get printLogSortUser;

  /// No description provided for @printLogSortStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get printLogSortStatus;

  /// No description provided for @printLogSortDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get printLogSortDuration;

  /// No description provided for @printLogSortFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament used'**
  String get printLogSortFilament;

  /// No description provided for @printLogSortCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get printLogSortCost;

  /// No description provided for @printLogSortEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get printLogSortEnergy;

  /// No description provided for @printLogSortDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get printLogSortDirection;

  /// No description provided for @printLogSortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get printLogSortDescending;

  /// No description provided for @printLogSortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get printLogSortAscending;

  /// No description provided for @printLogStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get printLogStatusCompleted;

  /// No description provided for @printLogStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get printLogStatusFailed;

  /// No description provided for @printLogStatusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get printLogStatusStopped;

  /// No description provided for @printLogStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get printLogStatusCancelled;

  /// No description provided for @printLogStatusSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get printLogStatusSkipped;

  /// No description provided for @printLogStatusAborted.
  ///
  /// In en, this message translates to:
  /// **'Aborted'**
  String get printLogStatusAborted;

  /// No description provided for @printLogEnergy.
  ///
  /// In en, this message translates to:
  /// **'{value} kWh'**
  String printLogEnergy(String value);

  /// No description provided for @printLogClassifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Classify this run'**
  String get printLogClassifyTitle;

  /// No description provided for @printLogDetailStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get printLogDetailStarted;

  /// No description provided for @printLogDetailFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get printLogDetailFinished;

  /// No description provided for @printLogDetailDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get printLogDetailDuration;

  /// No description provided for @printLogDetailFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get printLogDetailFilament;

  /// No description provided for @printLogDetailCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get printLogDetailCost;

  /// No description provided for @printLogDetailEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get printLogDetailEnergy;

  /// No description provided for @printLogFailureCause.
  ///
  /// In en, this message translates to:
  /// **'Failure cause'**
  String get printLogFailureCause;

  /// No description provided for @printLogNoClassification.
  ///
  /// In en, this message translates to:
  /// **'Not classified'**
  String get printLogNoClassification;

  /// No description provided for @printLogStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get printLogStatusLabel;

  /// No description provided for @printLogCountsAsFailure.
  ///
  /// In en, this message translates to:
  /// **'Counted as a failure — this run and its cause show up in failure analysis.'**
  String get printLogCountsAsFailure;

  /// No description provided for @printLogNotCountedAsFailure.
  ///
  /// In en, this message translates to:
  /// **'Not counted as a failure, so the cause stays out of failure analysis.'**
  String get printLogNotCountedAsFailure;

  /// No description provided for @printLogStatusOneWay.
  ///
  /// In en, this message translates to:
  /// **'This server cannot write “{status}” back. Change it and it is gone for good.'**
  String printLogStatusOneWay(String status);

  /// No description provided for @printLogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get printLogSave;

  /// No description provided for @printLogSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the classification'**
  String get printLogSaveFailed;

  /// No description provided for @printLogDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete run'**
  String get printLogDelete;

  /// No description provided for @printLogDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this run?'**
  String get printLogDeleteTitle;

  /// No description provided for @printLogDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It leaves the log, and its filament, cost and time leave the statistics. The archive it points at stays.'**
  String get printLogDeleteBody;

  /// No description provided for @printLogDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the run'**
  String get printLogDeleteFailed;

  /// No description provided for @printLogClear.
  ///
  /// In en, this message translates to:
  /// **'Clear print log'**
  String get printLogClear;

  /// No description provided for @printLogClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the whole print log?'**
  String get printLogClearTitle;

  /// No description provided for @printLogClearBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{The one run in the log goes} other{All {count} runs go}} — everyone\'s, not only yours — and their filament, cost and time leave the statistics. Archives and the queue are untouched. This cannot be undone.'**
  String printLogClearBody(int count);

  /// Shown instead of printLogClearBody when a filter or search is active. The route deletes the whole log and cannot take a filter, so this one quotes no count — printLogClearBody's number is the filtered total and would understate what goes.
  ///
  /// In en, this message translates to:
  /// **'Every run in the log goes — everyone\'s, not only yours, and the filter you have on does not narrow it — and their filament, cost and time leave the statistics. Archives and the queue are untouched. This cannot be undone.'**
  String get printLogClearBodyFiltered;

  /// No description provided for @printLogCleared.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run deleted} other{{count} runs deleted}}'**
  String printLogCleared(int count);

  /// No description provided for @printLogClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the print log'**
  String get printLogClearFailed;

  /// No description provided for @failureReasonAdhesion.
  ///
  /// In en, this message translates to:
  /// **'Adhesion failure'**
  String get failureReasonAdhesion;

  /// No description provided for @failureReasonSpaghetti.
  ///
  /// In en, this message translates to:
  /// **'Spaghetti / detached print'**
  String get failureReasonSpaghetti;

  /// No description provided for @failureReasonLayerShift.
  ///
  /// In en, this message translates to:
  /// **'Layer shift'**
  String get failureReasonLayerShift;

  /// No description provided for @failureReasonCloggedNozzle.
  ///
  /// In en, this message translates to:
  /// **'Clogged nozzle'**
  String get failureReasonCloggedNozzle;

  /// No description provided for @failureReasonFilamentRunout.
  ///
  /// In en, this message translates to:
  /// **'Filament runout'**
  String get failureReasonFilamentRunout;

  /// No description provided for @failureReasonWarping.
  ///
  /// In en, this message translates to:
  /// **'Warping'**
  String get failureReasonWarping;

  /// No description provided for @failureReasonStringing.
  ///
  /// In en, this message translates to:
  /// **'Stringing'**
  String get failureReasonStringing;

  /// No description provided for @failureReasonUnderExtrusion.
  ///
  /// In en, this message translates to:
  /// **'Under-extrusion'**
  String get failureReasonUnderExtrusion;

  /// No description provided for @failureReasonPowerFailure.
  ///
  /// In en, this message translates to:
  /// **'Power failure'**
  String get failureReasonPowerFailure;

  /// No description provided for @failureReasonUserCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the user'**
  String get failureReasonUserCancelled;

  /// No description provided for @failureReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get failureReasonOther;

  /// No description provided for @failureReasonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get failureReasonUnknown;
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
