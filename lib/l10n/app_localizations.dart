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
  /// **'Hotend fan'**
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

  /// No description provided for @ctrlFanPartShort.
  ///
  /// In en, this message translates to:
  /// **'Hotend'**
  String get ctrlFanPartShort;

  /// No description provided for @ctrlFanAuxShort.
  ///
  /// In en, this message translates to:
  /// **'Aux'**
  String get ctrlFanAuxShort;

  /// No description provided for @ctrlFanChamberShort.
  ///
  /// In en, this message translates to:
  /// **'Chamber'**
  String get ctrlFanChamberShort;

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

  /// Snackbar after an object is skipped
  ///
  /// In en, this message translates to:
  /// **'Skipped \"{name}\"'**
  String skipObjectsSkippedToast(String name);

  /// Confirm dialog title before skipping
  ///
  /// In en, this message translates to:
  /// **'Skip this object?'**
  String get skipObjectsConfirmTitle;

  /// Confirm dialog body before skipping an object
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be skipped for the rest of this print. This can\'t be undone.'**
  String skipObjectsConfirmBody(String name);

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

  /// No description provided for @amsHistoryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get amsHistoryCurrent;

  /// No description provided for @amsHistoryAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get amsHistoryAverage;

  /// No description provided for @amsHistoryMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get amsHistoryMin;

  /// No description provided for @amsHistoryMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get amsHistoryMax;

  /// No description provided for @amsHistoryRange6h.
  ///
  /// In en, this message translates to:
  /// **'6h'**
  String get amsHistoryRange6h;

  /// No description provided for @amsHistoryRange24h.
  ///
  /// In en, this message translates to:
  /// **'24h'**
  String get amsHistoryRange24h;

  /// No description provided for @amsHistoryRange48h.
  ///
  /// In en, this message translates to:
  /// **'48h'**
  String get amsHistoryRange48h;

  /// No description provided for @amsHistoryRange7d.
  ///
  /// In en, this message translates to:
  /// **'7d'**
  String get amsHistoryRange7d;

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

  /// No description provided for @amsHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No data for this range'**
  String get amsHistoryEmpty;

  /// No description provided for @amsHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load history'**
  String get amsHistoryError;

  /// No description provided for @amsHistoryRecordingInfo.
  ///
  /// In en, this message translates to:
  /// **'Recorded every 5 minutes while the printer is connected'**
  String get amsHistoryRecordingInfo;

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
  /// **'Reset usage to zero? The spool will count as full again.'**
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
  /// **'Usage reset'**
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
  /// **'The full source is available on Codeberg.'**
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

  /// No description provided for @fmPrintConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Send \"{name}\" to {printer} and start printing?'**
  String fmPrintConfirmBody(String name, String printer);

  /// No description provided for @fmPrintStarted.
  ///
  /// In en, this message translates to:
  /// **'Sent to printer'**
  String get fmPrintStarted;

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

  /// No description provided for @projectActionForbidden.
  ///
  /// In en, this message translates to:
  /// **'Your API key lacks permission for this action'**
  String get projectActionForbidden;

  /// No description provided for @projectActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get projectActionFailed;

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

  /// No description provided for @projectSaveCancelled.
  ///
  /// In en, this message translates to:
  /// **'Save cancelled'**
  String get projectSaveCancelled;

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

  /// No description provided for @plateClearAction.
  ///
  /// In en, this message translates to:
  /// **'Mark plate as cleared'**
  String get plateClearAction;

  /// No description provided for @plateClearBadge.
  ///
  /// In en, this message translates to:
  /// **'Plate not cleared'**
  String get plateClearBadge;

  /// No description provided for @plateClearedSnack.
  ///
  /// In en, this message translates to:
  /// **'Plate marked as cleared'**
  String get plateClearedSnack;

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

  /// No description provided for @pfmDownloadSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get pfmDownloadSaved;

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

  /// No description provided for @wearClearPlate.
  ///
  /// In en, this message translates to:
  /// **'Clear plate'**
  String get wearClearPlate;

  /// No description provided for @wearPlateCleared.
  ///
  /// In en, this message translates to:
  /// **'Plate cleared'**
  String get wearPlateCleared;

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
