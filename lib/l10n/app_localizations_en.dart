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
  String get wsReconnecting => 'No live connection — refreshing every 5 s';

  @override
  String get connLive => 'Live';

  @override
  String get connLiveTooltip => 'Real-time updates over WebSocket';

  @override
  String get connPolling => 'Polling';

  @override
  String get connPollingTooltip => 'No live link — refreshing every 5 s (REST)';

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
  String get clear => 'Clear';

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
  String get ctrlFanPart => 'Hotend fan';

  @override
  String get ctrlFanAux => 'Aux fan';

  @override
  String get ctrlFanChamber => 'Chamber fan';

  @override
  String get ctrlFanPartShort => 'Hotend';

  @override
  String get ctrlFanAuxShort => 'Aux';

  @override
  String get ctrlFanChamberShort => 'Chamber';

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
  String get ctrlPause => 'Pause';

  @override
  String get ctrlResume => 'Resume';

  @override
  String get ctrlStop => 'Stop';

  @override
  String get ctrlStopConfirmTitle => 'Stop print?';

  @override
  String get ctrlStopConfirmBody =>
      'This cancels the current print. It cannot be resumed.';

  @override
  String get ctrlForbidden => 'This API key can\'t control the printer';

  @override
  String get ctrlFailed => 'Couldn\'t send the command';

  @override
  String get speedSilent => 'Silent';

  @override
  String get speedStandard => 'Standard';

  @override
  String get speedSport => 'Sport';

  @override
  String get speedLudicrous => 'Ludicrous';

  @override
  String get smartPlugOn => 'On';

  @override
  String get smartPlugOff => 'Off';

  @override
  String get smartPlugUnreachable => 'Unreachable';

  @override
  String get smartPlugCantPowerOff =>
      'Can\'t cut power while the printer is printing';

  @override
  String get smartPlugOffConfirmTitle => 'Cut power?';

  @override
  String get smartPlugOffConfirmBody => 'The printer loses power immediately.';

  @override
  String get smartPlugTurnOff => 'Turn off';

  @override
  String get smartPlugOnConfirmTitle => 'Power on?';

  @override
  String get smartPlugOnConfirmBody => 'The printer will be powered on.';

  @override
  String get smartPlugTurnOn => 'Turn on';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => 'Total power draw across all plugs';

  @override
  String get queueEmpty => 'The queue is empty';

  @override
  String get queueDeleteTitle => 'Remove from queue?';

  @override
  String get queueDeleteBody => 'This removes the item from the print queue.';

  @override
  String get queueDeleteConfirm => 'Remove';

  @override
  String get queueStart => 'Start now';

  @override
  String get queueStartNext => 'Start next';

  @override
  String get queueCancel => 'Cancel';

  @override
  String get queueNoFreePrinters => 'No free printers right now';

  @override
  String get queuePrintStarted => 'Print started';

  @override
  String get queueStatusPending => 'Waiting';

  @override
  String get queueStatusScheduled => 'Scheduled';

  @override
  String get queueStatusPrinting => 'Printing';

  @override
  String get queueStatusPaused => 'Paused';

  @override
  String get archiveSearchHint => 'Search archive';

  @override
  String get archiveEmpty => 'No archived prints';

  @override
  String archiveSearchFailed(String query) {
    return 'Couldn\'t search for \"$query\". Try a different term.';
  }

  @override
  String get archiveReprint => 'Reprint';

  @override
  String get archiveAddToQueue => 'Add to queue';

  @override
  String get gcodeViewerTitle => 'G-code preview';

  @override
  String get gcodeViewerOpen => 'Preview G-code';

  @override
  String get gcodeViewerError => 'Couldn\'t load the G-code preview.';

  @override
  String get archiveReprintConfirmTitle => 'Start reprint?';

  @override
  String archiveReprintConfirmBody(String printer) {
    return 'This sends the file to $printer and starts printing.';
  }

  @override
  String get archiveReprintStarted => 'Reprint started';

  @override
  String get archiveAddedToQueue => 'Added to queue';

  @override
  String get archiveDelete => 'Delete';

  @override
  String get archiveDeleteTitle => 'Delete print?';

  @override
  String archiveDeleteBody(String name) {
    return 'Remove \"$name\" from the archive.';
  }

  @override
  String get archiveDeletePurgeStats => 'Also remove from statistics';

  @override
  String get archiveDeletePurgeStatsHint =>
      'Otherwise the print is kept in your statistics totals.';

  @override
  String get archiveDeleted => 'Print deleted';

  @override
  String get archiveDeleteFailed => 'Couldn\'t delete the print';

  @override
  String get archiveSelectAll => 'Select all';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count prints?',
      one: 'Delete 1 print?',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody =>
      'Remove the selected prints from the archive.';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prints deleted',
      one: '1 print deleted',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return '$ok deleted, $failed failed';
  }

  @override
  String get archivePurgeOlder => 'Purge old prints…';

  @override
  String get archivePurgeTitle => 'Purge old prints';

  @override
  String get archivePurgeOlderThan => 'Older than';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prints · $size',
      one: '1 print · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing => 'No prints older than this.';

  @override
  String get archivePurgePreviewError => 'Couldn\'t load the preview.';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prints purged',
      one: '1 print purged',
      zero: 'No prints purged',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => 'Choose a printer';

  @override
  String get noPrintersAvailable => 'No printers available';

  @override
  String get detailsShow => 'Details';

  @override
  String get detailsHide => 'Hide details';

  @override
  String get cameraTooltip => 'Camera';

  @override
  String get cameraConnecting => 'Connecting to camera…';

  @override
  String get cameraError => 'Couldn\'t load the camera stream';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'External spool';

  @override
  String get traySlotEmpty => 'Empty';

  @override
  String get extruderLeft => 'Left extruder';

  @override
  String get extruderRight => 'Right extruder';

  @override
  String get extruderLeftShort => 'L';

  @override
  String get extruderRightShort => 'R';

  @override
  String get amsHumidityTooltip => 'AMS humidity';

  @override
  String get amsTempTooltip => 'AMS temperature';

  @override
  String amsHistoryTitle(String ams) {
    return '$ams history';
  }

  @override
  String get amsHistoryHumidity => 'Humidity';

  @override
  String get amsHistoryTemperature => 'Temperature';

  @override
  String get amsHistoryCurrent => 'Current';

  @override
  String get amsHistoryAverage => 'Average';

  @override
  String get amsHistoryMin => 'Min';

  @override
  String get amsHistoryMax => 'Max';

  @override
  String get amsHistoryRange6h => '6h';

  @override
  String get amsHistoryRange24h => '24h';

  @override
  String get amsHistoryRange48h => '48h';

  @override
  String get amsHistoryRange7d => '7d';

  @override
  String get amsHistoryGood => 'Good';

  @override
  String get amsHistoryFair => 'Fair';

  @override
  String get amsHistoryEmpty => 'No data for this range';

  @override
  String get amsHistoryError => 'Couldn\'t load history';

  @override
  String get amsHistoryRecordingInfo =>
      'Recorded every 5 minutes while the printer is connected';

  @override
  String get wifiTooltip => 'Wi-Fi signal';

  @override
  String get doorOpen => 'Door open';

  @override
  String get doorClosed => 'Door closed';

  @override
  String get firmwareUpToDate => 'Firmware up to date';

  @override
  String firmwareUpdateAvailable(String version) {
    return 'Firmware update available: $version';
  }

  @override
  String get statusUnavailable => 'status unavailable';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

  @override
  String get widgetNoPrinter => 'No printer';

  @override
  String get widgetStatusPrinting => 'Printing';

  @override
  String get widgetStatusPaused => 'Paused';

  @override
  String get widgetStatusFinished => 'Finished';

  @override
  String get widgetStatusFailed => 'Failed';

  @override
  String get widgetStatusIdle => 'Idle';

  @override
  String get widgetStatusOffline => 'Offline';

  @override
  String get widgetStatusError => 'Error';

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
  String get errForbidden =>
      'Not allowed — your API key lacks permission for this';

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

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent% · ETA $eta';
  }

  @override
  String notifMorePrints(int count) {
    return '+$count';
  }

  @override
  String get printFinishedTitle => 'Print finished';

  @override
  String printFinishedBody(String name) {
    return '$name is done';
  }

  @override
  String get printFailedTitle => 'Print failed';

  @override
  String printFailedBody(String name) {
    return '$name failed';
  }

  @override
  String get notifStartedTitle => 'Print started';

  @override
  String notifStartedBody(String name) {
    return '$name started printing';
  }

  @override
  String get notifFirstLayerTitle => 'First layer done';

  @override
  String notifFirstLayerBody(String name) {
    return '$name finished its first layer';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return '$percent% printed';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name is $percent% done';
  }

  @override
  String get notifPlateTitle => 'Plate not empty';

  @override
  String notifPlateBody(String printer) {
    return '$printer needs the plate cleared before the next job';
  }

  @override
  String get notifOfflineTitle => 'Printer offline';

  @override
  String notifOfflineBody(String printer) {
    return '$printer lost connection';
  }

  @override
  String get notifErrorTitle => 'Printer error';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer: $detail';
  }

  @override
  String get notifLowFilamentTitle => 'Low filament';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return '$printer has $percent% filament left';
  }

  @override
  String get notifHumidityTitle => 'AMS humidity high';

  @override
  String get notifHumidityHtTitle => 'AMS-HT humidity high';

  @override
  String notifHumidityBody(String printer, int value) {
    return '$printer AMS humidity is $value%';
  }

  @override
  String get notifBedCooledTitle => 'Bed cooled';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return '$printer bed cooled to $temp°C';
  }

  @override
  String get notifSettingsTitle => 'Notifications';

  @override
  String get notifSettingsHint =>
      'Choose which events trigger a notification. Changes apply the next time background monitoring starts.';

  @override
  String get notifMasterTitle => 'Event notifications';

  @override
  String get notifMasterDesc =>
      'Turn off to silence all alerts. The ongoing print-progress notification stays.';

  @override
  String get notifEventsHeader => 'Events';

  @override
  String get notifThresholdsHeader => 'Thresholds';

  @override
  String get notifEvtStarted => 'Print started';

  @override
  String get notifEvtStartedDesc => 'When a print begins';

  @override
  String get notifEvtFinished => 'Print finished';

  @override
  String get notifEvtFinishedDesc => 'When a print completes successfully';

  @override
  String get notifEvtFailed => 'Print failed';

  @override
  String get notifEvtFailedDesc => 'When a print fails';

  @override
  String get notifEvtFirstLayer => 'First layer done';

  @override
  String get notifEvtFirstLayerDesc => 'When the first layer finishes';

  @override
  String get notifEvtMilestones => 'Progress milestones';

  @override
  String get notifEvtMilestonesDesc => 'At 25%, 50% and 75%';

  @override
  String get notifEvtPlate => 'Plate not empty';

  @override
  String get notifEvtPlateDesc =>
      'When the plate must be cleared before the next job';

  @override
  String get notifEvtOffline => 'Printer offline';

  @override
  String get notifEvtOfflineDesc => 'When a printer loses connection';

  @override
  String get notifEvtError => 'Printer error (HMS)';

  @override
  String get notifEvtErrorDesc => 'When the printer reports an HMS error';

  @override
  String get notifEvtLowFilament => 'Low filament';

  @override
  String get notifEvtLowFilamentDesc =>
      'When remaining filament drops below the threshold';

  @override
  String get notifEvtHumidity => 'AMS humidity high';

  @override
  String get notifEvtHumidityDesc =>
      'When AMS humidity rises above the threshold';

  @override
  String get notifEvtBedCooled => 'Bed cooled';

  @override
  String get notifEvtBedCooledDesc => 'When the bed cools down after a print';

  @override
  String notifBedCooledThreshold(int temp) {
    return 'Bed cooled below $temp°C';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'AMS humidity above $value%';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return 'Low filament below $percent%';
  }

  @override
  String get notifEventsMenu => 'Notification events';

  @override
  String get hmsSeverityFatal => 'Fatal';

  @override
  String get hmsSeveritySerious => 'Serious';

  @override
  String get hmsSeverityCommon => 'Common';

  @override
  String get hmsSeverityInfo => 'Info';

  @override
  String get hmsModuleMainboard => 'mainboard';

  @override
  String get hmsModuleAms => 'AMS';

  @override
  String get hmsModuleToolhead => 'toolhead';

  @override
  String get hmsModuleXcam => 'camera';

  @override
  String get hmsModuleMc => 'motion controller';

  @override
  String get hmsErrorsHeader => 'Active errors';

  @override
  String get hmsViewInWiki => 'Open in Bambu wiki';

  @override
  String get batteryOptTitle => 'Reliable background notifications';

  @override
  String get batteryOptBody =>
      'To keep print notifications working when the app is in the background, allow BambuBuddy to run without battery restrictions. On Samsung phones this is essential.';

  @override
  String get batteryOptAllow => 'Open settings';

  @override
  String get batteryOptLater => 'Later';

  @override
  String get batteryOptMenu => 'Background notifications';

  @override
  String get notificationsReady => 'Notifications are all set';

  @override
  String get notificationsBlocked =>
      'Notifications are off — enable them in system settings';

  @override
  String get bgServiceTitle => 'BambuBuddy';

  @override
  String get bgServiceText => 'Monitoring printers';

  @override
  String get bgMonitoringToggle => 'Background monitoring';

  @override
  String get bgMonitoringSubtitle =>
      'Keep watching prints while the app is closed. Shows a persistent notification.';

  @override
  String get bgMonitoringOn => 'Background monitoring on';

  @override
  String get bgMonitoringOff => 'Background monitoring off';

  @override
  String get navDashboard => 'Printers';

  @override
  String get navQueue => 'Queue';

  @override
  String get navArchive => 'Archive';

  @override
  String get navMaintenance => 'Maintenance';

  @override
  String get navFilaments => 'Filaments';

  @override
  String get inventoryEmpty => 'No spools in inventory';

  @override
  String get inventoryNoMatches => 'No filaments match your search';

  @override
  String get inventorySearchHint => 'Search material, brand, color…';

  @override
  String get inventoryShowArchived => 'Show archived';

  @override
  String get inventoryArchived => 'Archived';

  @override
  String get inventoryLowStock => 'Low';

  @override
  String get inventoryFilters => 'Filters';

  @override
  String get inventoryFilterStatus => 'Status';

  @override
  String get inventoryStatusActive => 'Active';

  @override
  String get inventoryStatusArchived => 'Archived';

  @override
  String get inventoryFilterStock => 'Stock';

  @override
  String get inventoryStockAll => 'All';

  @override
  String get inventoryStockLow => 'Low stock';

  @override
  String get inventoryFilterMaterial => 'Material';

  @override
  String get inventoryFilterBrand => 'Brand';

  @override
  String get inventoryFiltersClear => 'Clear all';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return '$grams g left';
  }

  @override
  String inventoryOfTotal(int total) {
    return 'of $total g';
  }

  @override
  String inventoryLoadedIn(String slot) {
    return 'Loaded in $slot';
  }

  @override
  String get inventoryNotLoaded => 'Not loaded in any AMS slot';

  @override
  String get inventoryLocation => 'Location';

  @override
  String get inventoryNozzleTemp => 'Nozzle temp';

  @override
  String inventoryCostPerKg(String cost) {
    return '$cost/kg';
  }

  @override
  String get inventoryNote => 'Note';

  @override
  String get inventoryTag => 'Tag';

  @override
  String get inventoryId => 'Filament ID';

  @override
  String get inventoryUsageHistory => 'Usage history';

  @override
  String get inventoryUsageEmpty => 'No usage recorded yet';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => 'Calibration (K)';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle mm · K $k';
  }

  @override
  String get inventoryAddSpool => 'Add spool';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Add $count $_temp0';
  }

  @override
  String get inventoryNewSpool => 'New spool';

  @override
  String get inventoryEditSpool => 'Edit spool';

  @override
  String get inventorySave => 'Save';

  @override
  String get inventoryFieldQuantity => 'Quantity';

  @override
  String get inventoryQuantityHint => 'Create several identical spools at once';

  @override
  String get inventoryEdit => 'Edit';

  @override
  String get inventoryDelete => 'Delete';

  @override
  String get inventoryArchive => 'Archive';

  @override
  String get inventoryRestore => 'Restore';

  @override
  String get inventoryResetUsage => 'Reset usage';

  @override
  String get inventoryFieldSlicerPreset => 'Slicer preset';

  @override
  String get inventorySlicerPresetHint =>
      'Print profile this spool is added with';

  @override
  String get inventorySlicerPresetNone => 'No preset';

  @override
  String get inventorySlicerPresetSearch => 'Search presets…';

  @override
  String get inventorySlicerPresetUnavailable =>
      'No slicer presets available. Enable slicing on the server (and connect Bambu Cloud for cloud presets).';

  @override
  String get inventoryFieldMaterial => 'Material';

  @override
  String get inventoryFieldBrand => 'Brand';

  @override
  String get inventoryFieldSubtype => 'Variant';

  @override
  String get inventoryFieldColorName => 'Color name';

  @override
  String get inventoryFieldColorHex => 'Color (hex)';

  @override
  String get inventoryFieldLabelWeight => 'Spool weight (g)';

  @override
  String get inventoryFieldWeightUsed => 'Used (g)';

  @override
  String get inventoryFieldCostPerKg => 'Cost per kg';

  @override
  String get inventoryFieldLowStock => 'Low-stock threshold (%)';

  @override
  String get inventoryFieldLocation => 'Storage location';

  @override
  String get inventoryFieldNozzleMin => 'Nozzle min (°C)';

  @override
  String get inventoryFieldNozzleMax => 'Nozzle max (°C)';

  @override
  String get inventoryFieldNote => 'Note';

  @override
  String get inventoryFieldRequired => 'Required';

  @override
  String get inventoryFieldInvalidNumber => 'Enter a number';

  @override
  String get inventorySectionBasics => 'Basics';

  @override
  String get inventorySectionWeight => 'Weight & cost';

  @override
  String get inventorySectionDetails => 'Details';

  @override
  String get inventorySectionFilament => 'Filament';

  @override
  String get inventorySectionColor => 'Color';

  @override
  String get inventorySectionAdditional => 'Additional';

  @override
  String get inventoryFieldEmptySpoolWeight => 'Empty spool weight (g)';

  @override
  String get inventoryCoreWeightSelect => 'Select…';

  @override
  String get inventoryCoreWeightSearch => 'Search spools…';

  @override
  String get inventoryFieldRemainingWeight => 'Remaining weight (g)';

  @override
  String get inventoryFieldMeasuredWeight => 'Measured weight (g)';

  @override
  String get inventoryFieldCategory => 'Category';

  @override
  String get inventoryFieldExtraColors => 'Extra colors';

  @override
  String get inventoryExtraColorsHint => '2–8 hex stops, comma-separated';

  @override
  String get inventoryFieldEffect => 'Effect';

  @override
  String get inventoryEffectNone => 'None';

  @override
  String get inventoryColorCommon => 'Common colors';

  @override
  String get inventoryColorSearchHint => 'Search colors…';

  @override
  String get inventoryColorPickTitle => 'Pick a color';

  @override
  String get inventoryColorSelect => 'Select';

  @override
  String get inventoryColorNone => 'No color';

  @override
  String get inventoryLowStockHint => 'Leave blank to use the global threshold';

  @override
  String inventoryRemainingOfLabel(int total) {
    return 'of $total g';
  }

  @override
  String get inventoryDeleteTitle => 'Delete spool?';

  @override
  String inventoryDeleteConfirm(String name) {
    return 'Permanently delete $name? This cannot be undone.';
  }

  @override
  String get inventoryResetUsageConfirm =>
      'Reset usage to zero? The spool will count as full again.';

  @override
  String get inventorySpoolCreated => 'Spool added';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return '$count $_temp0 added';
  }

  @override
  String get inventorySpoolUpdated => 'Spool updated';

  @override
  String get inventorySpoolDeleted => 'Spool deleted';

  @override
  String get inventorySpoolArchived => 'Spool archived';

  @override
  String get inventorySpoolRestored => 'Spool restored';

  @override
  String get inventoryUsageReset => 'Usage reset';

  @override
  String get inventorySaveFailed => 'Could not save spool';

  @override
  String get inventoryActionFailed => 'Action failed';

  @override
  String get inventoryUnassign => 'Unassign';

  @override
  String get inventoryAssign => 'Assign to slot';

  @override
  String get inventoryAssignPrinter => 'Printer';

  @override
  String get inventoryAssignNoPrinters => 'No printers available';

  @override
  String get inventorySlotAms => 'AMS slot';

  @override
  String get inventoryAssignUnit => 'AMS unit';

  @override
  String get inventoryAssignSlot => 'Slot';

  @override
  String get inventoryAssignExtruder => 'Extruder';

  @override
  String get inventoryAssignExternalHint =>
      'Assigns to the external spool holder';

  @override
  String get inventoryAssignConfirm => 'Assign';

  @override
  String get inventoryAssignTitle => 'Assign spool';

  @override
  String get inventoryAssignCurrent => 'Currently in this slot';

  @override
  String get inventoryAssignPick => 'Pick a spool';

  @override
  String get inventoryReassignTitle => 'Move spool?';

  @override
  String inventoryReassignMessage(String slot) {
    return 'This spool is currently in $slot. It will be removed from there and assigned to this slot.';
  }

  @override
  String get inventoryReassignAction => 'Move';

  @override
  String get inventorySpoolAssigned => 'Spool assigned';

  @override
  String get inventorySpoolUnassigned => 'Spool unassigned';

  @override
  String get inventoryScanSpool => 'Scan QR';

  @override
  String get inventoryScanTitle => 'Scan spool QR';

  @override
  String get inventoryScanHint => 'Point the camera at the spool\'s QR code';

  @override
  String get inventoryScanPermissionTitle => 'Camera access needed';

  @override
  String get inventoryScanPermissionBody =>
      'Allow camera access to scan spool QR codes.';

  @override
  String get inventoryScanOpenSettings => 'Open settings';

  @override
  String get inventoryScanInvalid => 'Unrecognized QR code';

  @override
  String inventoryScanNotFound(int id) {
    return 'Spool #$id not found';
  }

  @override
  String get maintenanceEmpty => 'No maintenance data';

  @override
  String maintenanceTotalHours(int hours) {
    return '$hours h total';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count due';
  }

  @override
  String maintenanceWarningBadge(int count) {
    return '$count soon';
  }

  @override
  String maintenanceDueIn(int hours) {
    return 'Due in $hours h';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return 'Overdue by $hours h';
  }

  @override
  String get maintenancePerform => 'Mark done';

  @override
  String get maintenancePerformConfirm =>
      'Reset the counter for this maintenance task?';

  @override
  String get maintenanceNotesHint => 'Notes (optional)';

  @override
  String get maintenanceHistory => 'History';

  @override
  String get maintenanceHistoryEmpty => 'No history yet';

  @override
  String get maintenanceDone => 'Maintenance marked as done';

  @override
  String get maintenanceFailed => 'Could not update maintenance';

  @override
  String get maintenanceSaved => 'Saved';

  @override
  String get maintenanceSettingsTitle => 'Maintenance settings';

  @override
  String get maintenanceOverridesTitle => 'Interval overrides';

  @override
  String get maintenanceOverridesSubtitle =>
      'Mute tasks or customize intervals per printer';

  @override
  String get maintenanceTabStatus => 'Status';

  @override
  String get maintenanceTabSettings => 'Settings';

  @override
  String get maintenanceMute => 'Mute';

  @override
  String get maintenanceUnmute => 'Unmute';

  @override
  String get maintenanceMuted => 'Task muted';

  @override
  String get maintenanceUnmuted => 'Task unmuted';

  @override
  String get maintenanceEditInterval => 'Edit interval';

  @override
  String get maintenanceResetInterval => 'Reset to default';

  @override
  String get maintenanceTypesTitle => 'Maintenance types';

  @override
  String get maintenanceTypesSubtitle => 'System types and your custom tasks';

  @override
  String get maintenanceRestoreDefaults => 'Restore defaults';

  @override
  String get maintenanceRestoreConfirm =>
      'Restore all hidden default maintenance types?';

  @override
  String get maintenanceAddType => 'Add custom type';

  @override
  String get maintenanceEditType => 'Edit type';

  @override
  String get maintenanceSystemType => 'System';

  @override
  String maintenanceEveryHours(int count) {
    return 'Every $count h';
  }

  @override
  String maintenanceEveryDays(int count) {
    return 'Every $count days';
  }

  @override
  String get maintenanceDeleteTypeTitle => 'Delete maintenance type?';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return 'Hide the default type \"$name\"? You can restore it later.';
  }

  @override
  String get maintenanceFieldName => 'Name';

  @override
  String get maintenanceFieldNameHint => 'e.g. Replace HEPA filter';

  @override
  String get maintenanceFieldIntervalType => 'Interval type';

  @override
  String get maintenanceFieldInterval => 'Interval';

  @override
  String get maintenanceIntervalHours => 'Print hours';

  @override
  String get maintenanceIntervalDays => 'Days';

  @override
  String get maintenanceIntervalInvalid => 'Enter a value ≥ 1';

  @override
  String get maintenanceFieldIcon => 'Icon';

  @override
  String get maintenanceFieldDocLink => 'Documentation link (optional)';

  @override
  String get maintenanceAssignPrinters => 'Assign to printers';

  @override
  String get maintenanceSelectPrinter => 'Select at least one printer';

  @override
  String get notifEvtMaintenance => 'Maintenance due';

  @override
  String get notifEvtMaintenanceDesc =>
      'When a maintenance task becomes overdue';

  @override
  String get maintenanceNotifTitle => 'Maintenance due';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer: $task';
  }

  @override
  String get maintenanceReminderTitle => 'Maintenance reminder';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tasks',
      one: 'task',
    );
    return '$printer has $count overdue maintenance $_temp0';
  }

  @override
  String get maintenanceNotifAction => 'Mark done';

  @override
  String get navMenu => 'Menu';

  @override
  String get menuStatistics => 'Statistics';

  @override
  String get statsTitle => 'Statistics';

  @override
  String get statsRangeAllTime => 'All time';

  @override
  String get statsRangeLast7Days => 'Last 7 days';

  @override
  String get statsRangeLast30Days => 'Last 30 days';

  @override
  String get statsRangeLast90Days => 'Last 90 days';

  @override
  String get statsRangeThisYear => 'This year';

  @override
  String get statsRangeCustom => 'Custom range';

  @override
  String get statsEmpty => 'No prints in this period';

  @override
  String get statsLoadFailed => 'Could not load statistics';

  @override
  String get statsOverview => 'Overview';

  @override
  String get statsTotalPrints => 'Total prints';

  @override
  String get statsPrintTime => 'Print time';

  @override
  String get statsFilamentUsed => 'Filament used';

  @override
  String get statsFilamentCost => 'Filament cost';

  @override
  String get statsEnergyUsed => 'Energy used';

  @override
  String get statsEnergyCost => 'Energy cost';

  @override
  String get statsTotalCost => 'Total cost';

  @override
  String get statsEnergyWarmingUp => 'Energy data is still warming up';

  @override
  String get statsSuccessRate => 'Success rate';

  @override
  String statsSuccessful(int count) {
    return 'Successful: $count';
  }

  @override
  String statsFailed(int count) {
    return 'Failed: $count';
  }

  @override
  String statsCancelled(int count) {
    return 'Cancelled: $count';
  }

  @override
  String get statsAllUsers => 'All Users';

  @override
  String get statsNoUser => 'No User (System)';

  @override
  String get statsTimeAccuracy => 'Time accuracy';

  @override
  String get statsTimeAccuracyHint => '100% = perfect estimate';

  @override
  String get statsByMaterial => 'Prints by material';

  @override
  String get statsByPrinter => 'Prints by printer';

  @override
  String get statsTimeAccuracyByPrinter => 'Time accuracy by printer';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prints',
      one: '$count print',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours h';
  }

  @override
  String statsPrinterFallback(String id) {
    return 'Printer #$id';
  }

  @override
  String get statsMetricWeight => 'Weight';

  @override
  String get statsMetricPrints => 'Prints';

  @override
  String get statsMetricTime => 'Time';

  @override
  String get statsFailureAnalysis => 'Failure analysis';

  @override
  String get statsFailureRate => 'Failure rate';

  @override
  String statsFailurePeriod(int days) {
    return 'Last $days days';
  }

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total prints failed';
  }

  @override
  String get statsTopFailureReasons => 'Top failure reasons';

  @override
  String get statsNoFailures => 'No failures in this period';

  @override
  String get statsPrintActivity => 'Print activity';

  @override
  String get statsHeatmapLess => 'Less';

  @override
  String get statsHeatmapMore => 'More';

  @override
  String get statsRecords => 'Records';

  @override
  String get statsLongestPrint => 'Longest print';

  @override
  String get statsHeaviestPrint => 'Heaviest print';

  @override
  String get statsMostExpensive => 'Most expensive';

  @override
  String get statsBusiestDay => 'Busiest day';

  @override
  String get statsSuccessStreak => 'Success streak';

  @override
  String statsConsecutive(int count) {
    return '$count consecutive';
  }

  @override
  String get statsFilamentTrends => 'Filament trends';

  @override
  String get statsPeriodFilament => 'Period filament';

  @override
  String get statsPeriodCost => 'Period cost';

  @override
  String get statsAvgPerPrint => 'Avg per print';

  @override
  String get statsUsageOverTime => 'Usage over time';

  @override
  String get statsByMaterialTitle => 'By material';

  @override
  String get statsSuccessByMaterial => 'Success by material';

  @override
  String get statsColorDistribution => 'Color distribution';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'colors',
      one: 'color',
    );
    return '$count $_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '+$count more';
  }

  @override
  String get statsPrintDuration => 'Print duration';

  @override
  String get statsPrintHabits => 'Print habits';

  @override
  String get statsPrintTimeOfDay => 'Print time of day';

  @override
  String get aboutMenu => 'About';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutTagline =>
      'Native Android client for bambuddy — a self-hosted Bambu Lab printer manager.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutLicenseHeader => 'License';

  @override
  String get aboutLicenseBody =>
      'Bambuddy is free software released under the GNU Affero General Public License v3.0 (AGPL-3.0). You may use, study, share and modify it; if you run a modified version as a network service, you must offer its source to its users.';

  @override
  String get aboutViewLicense => 'Read the AGPL-3.0 license';

  @override
  String get aboutSourceHeader => 'Source code';

  @override
  String get aboutSourceBody => 'The full source is available on Codeberg.';

  @override
  String get aboutSourceLink => 'Open source repository';

  @override
  String get aboutThirdParty => 'Open-source licenses';

  @override
  String get aboutThirdPartySubtitle => 'Licenses of the bundled libraries';

  @override
  String get aboutOpenLinkError => 'Could not open the link';

  @override
  String get fileManagerMenu => 'File Manager';

  @override
  String get fileManagerTitle => 'File Manager';

  @override
  String get fmRoot => 'All Files';

  @override
  String get fmSearchHint => 'Search files…';

  @override
  String get fmEmpty => 'This folder is empty';

  @override
  String get fmNoMatches => 'No files match your filters';

  @override
  String get fmSortBy => 'Sort by';

  @override
  String get fmSortDateNewest => 'Newest first';

  @override
  String get fmSortDateOldest => 'Oldest first';

  @override
  String get fmSortNameAZ => 'Name A–Z';

  @override
  String get fmSortNameZA => 'Name Z–A';

  @override
  String get fmSortSizeLargest => 'Largest first';

  @override
  String get fmSortSizeSmallest => 'Smallest first';

  @override
  String get fmFilterType => 'File type';

  @override
  String get fmAllTypes => 'All types';

  @override
  String get fmNewFolder => 'New folder';

  @override
  String get fmFolderName => 'Folder name';

  @override
  String get fmFileName => 'File name';

  @override
  String get fmSave => 'Save';

  @override
  String get fmRename => 'Rename';

  @override
  String get fmRenameFolder => 'Rename folder';

  @override
  String get fmRenameFile => 'Rename file';

  @override
  String get fmRenamed => 'Renamed';

  @override
  String get fmFolderCreated => 'Folder created';

  @override
  String get fmDelete => 'Delete';

  @override
  String get fmDeleted => 'Moved to trash';

  @override
  String get fmDeleteFile => 'Delete file';

  @override
  String fmDeleteFileConfirm(String name) {
    return 'Move \"$name\" to trash?';
  }

  @override
  String get fmDeleteFolder => 'Delete folder';

  @override
  String fmDeleteFolderConfirm(String name) {
    return 'Delete folder \"$name\" and all its contents?';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return 'Move $count $_temp0 to trash?';
  }

  @override
  String get fmMoveTo => 'Move to…';

  @override
  String get fmMoved => 'Moved';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => 'Print';

  @override
  String fmPrintConfirmBody(String name, String printer) {
    return 'Send \"$name\" to $printer and start printing?';
  }

  @override
  String get fmPrintStarted => 'Sent to printer';

  @override
  String get fmAddToQueue => 'Add to queue';

  @override
  String get fmAddedToQueue => 'Added to queue';

  @override
  String get fmUpload => 'Upload file';

  @override
  String get fmUploading => 'Uploading…';

  @override
  String fmUploaded(String name) {
    return 'Uploaded $name';
  }

  @override
  String get fmUploadFailed => 'Upload failed';

  @override
  String fmSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'folders',
      one: 'folder',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '$size free';
  }

  @override
  String get fmTrash => 'Trash';

  @override
  String get fmTrashTitle => 'Trash';

  @override
  String get fmTrashEmpty => 'Trash is empty';

  @override
  String get fmRestore => 'Restore';

  @override
  String get fmRestored => 'Restored';

  @override
  String get fmEmptyTrash => 'Empty trash';

  @override
  String get fmEmptyTrashConfirm =>
      'Permanently delete all files in trash? This cannot be undone.';

  @override
  String get fmHardDelete => 'Delete permanently';

  @override
  String fmHardDeleteConfirm(String name) {
    return 'Permanently delete \"$name\"? This cannot be undone.';
  }

  @override
  String get fmDeletedForever => 'Permanently deleted';

  @override
  String get makerworldMenu => 'MakerWorld';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get mwIntro =>
      'Paste a MakerWorld model URL to import and print it directly from Bambuddy.';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/en/models/… or any MakerWorld link';

  @override
  String get mwResolve => 'Resolve';

  @override
  String get mwEnterUrl => 'Enter a MakerWorld URL';

  @override
  String get mwUntitledModel => 'Untitled model';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plates',
      one: '1 plate',
      zero: 'No plates',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => 'No plates found for this model.';

  @override
  String get mwImport => 'Import';

  @override
  String mwShowAllPlates(int count) {
    return 'Show all $count plates';
  }

  @override
  String get mwShowLess => 'Show less';

  @override
  String get mwInLibrary => 'In library';

  @override
  String get mwImported => 'Imported to your library';

  @override
  String get mwAlreadyInLibrary => 'Already in your library';

  @override
  String get mwViewInFiles => 'View in File Manager';

  @override
  String get mwRecentImports => 'Recent imports';

  @override
  String get mwNoRecent => 'No recent imports yet';

  @override
  String get mwOpenOnMakerworld => 'Open on MakerWorld';

  @override
  String get mwLoginRequired =>
      'Sign in to your Bambu Cloud account to download MakerWorld models.';

  @override
  String get cloudAccountMenu => 'Bambu Cloud account';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote =>
      'Sign in with your Bambu Lab account. These credentials are used only to download models from MakerWorld.';

  @override
  String get cloudEmail => 'Email';

  @override
  String get cloudPassword => 'Password';

  @override
  String get cloudRegionGlobal => 'Global';

  @override
  String get cloudRegionChina => 'China';

  @override
  String get cloudSignIn => 'Sign in';

  @override
  String get cloudSignOut => 'Sign out';

  @override
  String get cloudSignedIn => 'Signed in';

  @override
  String get cloudSignedInOk => 'Signed in to Bambu Cloud';

  @override
  String get cloudSignInFailed => 'Sign-in failed';

  @override
  String get cloudFillCredentials => 'Enter your email and password';

  @override
  String get cloudVerify => 'Verify';

  @override
  String get cloudVerificationCode => 'Verification code';

  @override
  String get cloudVerificationPrompt =>
      'Enter the verification code to finish signing in.';

  @override
  String get cloudEnterCode => 'Enter the verification code';

  @override
  String get swatchCodesMenu => 'Swatch Codes';

  @override
  String get swatchCodesTitle => 'Swatch Codes';

  @override
  String get swatchSearchHint => 'Search by code or name';

  @override
  String get swatchSectionCodes => 'Codes';

  @override
  String get swatchSectionUncoded => 'Inventory filaments without codes';

  @override
  String get swatchNoCodes => 'No swatch codes yet';

  @override
  String get swatchNoCodesHint => 'Create a code to label a filament sample.';

  @override
  String swatchNoMatch(String query) {
    return 'No codes match \"$query\"';
  }

  @override
  String get swatchAllCoded => 'All inventory filaments have codes';

  @override
  String get swatchNewCode => 'New code';

  @override
  String get swatchGenerate => 'Generate';

  @override
  String get swatchGenerateCode => 'Generate code';

  @override
  String get swatchExists => 'That filament already has a code';

  @override
  String swatchCreatedSnack(String code) {
    return 'Created code $code';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return 'Updated code $code';
  }

  @override
  String swatchCopied(String code) {
    return 'Copied $code';
  }

  @override
  String get swatchDelete => 'Delete';

  @override
  String get swatchDeleteTitle => 'Delete code?';

  @override
  String swatchDeleteBody(String code, String name) {
    return 'Code $code for $name will be removed.';
  }

  @override
  String get swatchExport => 'Export';

  @override
  String get swatchImport => 'Import';

  @override
  String get swatchExportEmpty => 'No codes to export';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes',
      one: '1 code',
    );
    return 'Exported $_temp0';
  }

  @override
  String get swatchExportFailed => 'Export failed';

  @override
  String get swatchImportTitle => 'Import codes?';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return 'This replaces all $existing existing codes with $incoming codes from the file. This cannot be undone.';
  }

  @override
  String get swatchImportConfirm => 'Replace all';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes',
      one: '1 code',
    );
    return 'Imported $_temp0';
  }

  @override
  String get swatchImportFailed => 'Couldn\'t read that file';

  @override
  String get swatchImportEmpty => 'No codes found in file';

  @override
  String get swatchFormTitle => 'New swatch code';

  @override
  String get swatchEditTitle => 'Edit code';

  @override
  String get swatchSave => 'Save';

  @override
  String get swatchRegenerate => 'Regenerate';

  @override
  String get swatchFieldCode => 'Code';

  @override
  String get swatchCodeInvalid =>
      'Use 6 characters: digits and letters, no 0, 1, I, L or O';

  @override
  String get swatchCodeTaken => 'That code is already in use';

  @override
  String get swatchFieldBrand => 'Manufacturer';

  @override
  String get swatchFieldMaterial => 'Material';

  @override
  String get swatchFieldVariant => 'Variant';

  @override
  String get swatchFieldColor => 'Color';

  @override
  String get swatchFieldHex => 'Color hex';

  @override
  String get swatchMaterialRequired => 'Material is required';

  @override
  String get swatchNoCatalogColors =>
      'No catalog colors available. Enter a color name and hex manually.';

  @override
  String get projectsMenu => 'Projects';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get projectsEmpty => 'No projects yet';

  @override
  String get projectsFilterAll => 'All';

  @override
  String get projectCreate => 'New project';

  @override
  String get projectEdit => 'Edit project';

  @override
  String get projectDelete => 'Delete';

  @override
  String get projectDeleteTitle => 'Delete project?';

  @override
  String projectDeleteBody(String name) {
    return '“$name” will be removed. Linked prints stay in the archive.';
  }

  @override
  String get projectDeleted => 'Project deleted';

  @override
  String get projectDeleteFailed => 'Could not delete project';

  @override
  String get projectSaved => 'Project saved';

  @override
  String get projectActionForbidden =>
      'Your API key lacks permission for this action';

  @override
  String get projectActionFailed => 'Action failed';

  @override
  String get projectName => 'Name';

  @override
  String get projectNameRequired => 'Name is required';

  @override
  String get projectDescription => 'Description';

  @override
  String get projectNotes => 'Notes';

  @override
  String get projectStatus => 'Status';

  @override
  String get projectPriority => 'Priority';

  @override
  String get projectColor => 'Color';

  @override
  String get projectDueDate => 'Due date';

  @override
  String get projectDueDateClear => 'Clear';

  @override
  String get projectBudget => 'Budget';

  @override
  String get projectTargetCount => 'Target plates';

  @override
  String get projectTargetPartsCount => 'Target parts';

  @override
  String get projectTags => 'Tags (comma-separated)';

  @override
  String get projectUrl => 'Link';

  @override
  String get projectParent => 'Parent project';

  @override
  String get projectParentNone => 'None';

  @override
  String get projectSave => 'Save';

  @override
  String get projectStatusPlanning => 'Planning';

  @override
  String get projectStatusActive => 'Active';

  @override
  String get projectStatusOnHold => 'On hold';

  @override
  String get projectStatusCompleted => 'Completed';

  @override
  String get projectStatusArchived => 'Archived';

  @override
  String get projectPriorityLow => 'Low';

  @override
  String get projectPriorityNormal => 'Normal';

  @override
  String get projectPriorityHigh => 'High';

  @override
  String get projectPriorityUrgent => 'Urgent';

  @override
  String get projectTabOverview => 'Overview';

  @override
  String get projectTabArchives => 'Archives';

  @override
  String get projectTabBom => 'BOM';

  @override
  String get projectTabQueue => 'Queue';

  @override
  String get projectTabTimeline => 'Timeline';

  @override
  String get projectTabFiles => 'Files';

  @override
  String get projectTabAttachments => 'Attachments';

  @override
  String get projectStatsTitle => 'Statistics';

  @override
  String get projectStatProgress => 'Progress';

  @override
  String get projectStatPartsProgress => 'Parts';

  @override
  String get projectStatPrints => 'Plates';

  @override
  String get projectStatCompleted => 'Completed';

  @override
  String get projectStatFailed => 'Failed';

  @override
  String get projectStatQueued => 'Queued';

  @override
  String get projectStatInProgress => 'In progress';

  @override
  String get projectStatPrintTime => 'Print time';

  @override
  String get projectStatFilament => 'Filament';

  @override
  String get projectStatCost => 'Est. cost';

  @override
  String get projectStatEnergy => 'Energy';

  @override
  String get projectStatEnergyCost => 'Energy cost';

  @override
  String get projectStatRemaining => 'Remaining';

  @override
  String get projectStatBom => 'BOM';

  @override
  String get projectChildren => 'Sub-projects';

  @override
  String get projectNoDescription => 'No description';

  @override
  String projectDueOn(String date) {
    return 'Due $date';
  }

  @override
  String get projectAddArchives => 'Add archives';

  @override
  String get projectRemoveArchive => 'Remove from project';

  @override
  String get projectArchivesEmpty => 'No archives linked';

  @override
  String get projectArchiveRemoved => 'Removed from project';

  @override
  String get archiveAddToProject => 'Add to project';

  @override
  String get projectArchivesAdded => 'Added to project';

  @override
  String get projectPickTitle => 'Pick a project';

  @override
  String get projectBomEmpty => 'No BOM items';

  @override
  String get bomAdd => 'Add item';

  @override
  String get bomEditTitle => 'Edit item';

  @override
  String get bomAddTitle => 'New item';

  @override
  String get bomName => 'Name';

  @override
  String get bomQtyNeeded => 'Quantity';

  @override
  String get bomQtyAcquired => 'Acquired';

  @override
  String get bomUnitPrice => 'Unit price';

  @override
  String get bomSourcingUrl => 'Source URL';

  @override
  String get bomRemarks => 'Remarks';

  @override
  String get bomComplete => 'Complete';

  @override
  String get bomDelete => 'Delete item';

  @override
  String get bomDeleted => 'Item deleted';

  @override
  String get projectQueueEmpty => 'No queue items';

  @override
  String get projectTimelineEmpty => 'No events yet';

  @override
  String get projectAttachmentsEmpty => 'No attachments';

  @override
  String get projectFilesEmpty => 'No printable files';

  @override
  String get projectAttachmentUpload => 'Upload file';

  @override
  String get projectAttachmentDownload => 'Download';

  @override
  String get projectAttachmentDelete => 'Delete';

  @override
  String get projectAttachmentDeleted => 'Attachment deleted';

  @override
  String get projectAttachmentUploaded => 'Attachment uploaded';

  @override
  String projectFileSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String get projectDownloadFailed => 'Download failed';

  @override
  String get projectSaveCancelled => 'Save cancelled';

  @override
  String get projectCoverUpload => 'Set cover image';

  @override
  String get projectCoverDelete => 'Remove cover image';

  @override
  String get projectCoverUpdated => 'Cover updated';

  @override
  String get projectCoverRemoved => 'Cover removed';

  @override
  String get projectMenuExport => 'Export';

  @override
  String get projectMenuCreateTemplate => 'Save as template';

  @override
  String get projectMenuImport => 'Import project';

  @override
  String get projectFromTemplate => 'Create from template';

  @override
  String get projectTemplateNone => 'No templates';

  @override
  String get projectTemplatePickTitle => 'Pick a template';

  @override
  String get projectTemplateNamePrompt => 'New project name';

  @override
  String projectExported(String path) {
    return 'Exported to $path';
  }

  @override
  String get projectExportFailed => 'Export failed';

  @override
  String get projectTemplateCreated => 'Template created';

  @override
  String get projectImported => 'Project imported';

  @override
  String get projectImportFailed => 'Import failed';

  @override
  String get projectUploading => 'Uploading…';

  @override
  String get projectLinkFolder => 'Link folder';

  @override
  String get projectNoFoldersToLink => 'No folders available to link';

  @override
  String get projectUnlinkFolder => 'Unlink folder';

  @override
  String get projectFolderLinked => 'Folder linked';

  @override
  String get projectFolderUnlinked => 'Folder unlinked';

  @override
  String get projectNotesEmpty => 'No notes yet';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    return '$count left';
  }

  @override
  String get sliceAction => 'Slice';

  @override
  String get sliceTitle => 'Slice file';

  @override
  String get slicePrinter => 'Printer';

  @override
  String get sliceProcess => 'Process / Quality';

  @override
  String get sliceBedType => 'Build plate';

  @override
  String get sliceBedDefault => 'Default (from preset)';

  @override
  String get sliceFilament => 'Filament';

  @override
  String sliceFilamentNumbered(String n) {
    return 'Filament $n';
  }

  @override
  String get sliceSelect => 'Tap to select';

  @override
  String get sliceStart => 'Slice';

  @override
  String get sliceShowAll => 'All';

  @override
  String get sliceSearchHint => 'Search presets';

  @override
  String get sliceOwnedEmpty =>
      'No matching presets for your printer and filaments. Turn on \"All\" to browse the full catalog.';

  @override
  String get sliceNoPresets => 'No presets available';

  @override
  String get sliceInProgress => 'Slicing…';

  @override
  String get sliceDone => 'Slice complete';

  @override
  String get sliceFailed => 'Slice failed';

  @override
  String get sliceClose => 'Close';

  @override
  String sliceResultTime(String time) {
    return 'Estimated time: $time';
  }

  @override
  String sliceResultFilament(String grams) {
    return 'Filament: $grams g';
  }

  @override
  String get sliceTierLocal => 'Local preset';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => 'Built-in';

  @override
  String get queueFilamentMapping => 'Filament mapping';

  @override
  String get mappingNoPrinter =>
      'Assign a printer to this item first to map its AMS slots.';

  @override
  String get mappingNoSlots => 'No filament information for this file.';

  @override
  String mappingNoAms(String printer) {
    return 'No AMS filaments loaded on $printer.';
  }

  @override
  String get mappingPickTray => 'Select AMS slot';

  @override
  String get mappingExternalSpool => 'External spool';

  @override
  String mappingAmsSlot(String unit, String slot) {
    return 'AMS $unit · slot $slot';
  }

  @override
  String get mappingSaved => 'Filament mapping saved';

  @override
  String get plateClearTitle => 'Is the plate clear?';

  @override
  String get plateClearBody =>
      'Make sure the build plate is empty before starting this print.';

  @override
  String get plateClearConfirm => 'Plate is clear';

  @override
  String get plateClearAction => 'Mark plate as cleared';

  @override
  String get plateClearBadge => 'Plate not cleared';

  @override
  String get plateClearedSnack => 'Plate marked as cleared';

  @override
  String get pfmTitle => 'File Manager';

  @override
  String get pfmTooltip => 'Files on printer';

  @override
  String pfmStorageUsed(String size) {
    return 'Used: $size';
  }

  @override
  String get pfmTabRoot => 'Root';

  @override
  String get pfmTabCache => 'Cache';

  @override
  String get pfmTabModels => 'Models';

  @override
  String get pfmTabTimelapse => 'Timelapse';

  @override
  String get pfmSearchHint => 'Filter files…';

  @override
  String get pfmSortTooltip => 'Sort';

  @override
  String get pfmRefreshTooltip => 'Refresh';

  @override
  String get pfmSortNameAsc => 'Name (A–Z)';

  @override
  String get pfmSortNameDesc => 'Name (Z–A)';

  @override
  String get pfmSortSizeLargest => 'Size (largest)';

  @override
  String get pfmSortSizeSmallest => 'Size (smallest)';

  @override
  String get pfmSortDateNewest => 'Date (newest)';

  @override
  String get pfmSortDateOldest => 'Date (oldest)';

  @override
  String get pfmSelectAll => 'Select all';

  @override
  String get pfmDeselectAll => 'Deselect all';

  @override
  String pfmSelected(int count) {
    return '$count selected';
  }

  @override
  String get pfmEmpty => 'This folder is empty';

  @override
  String get pfmNoMatches => 'No files match your filter';

  @override
  String get pfmDownload => 'Download';

  @override
  String get pfmDelete => 'Delete';

  @override
  String get pfmDownloadSaved => 'File saved';

  @override
  String get pfmDeleteConfirmTitle => 'Delete files?';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return 'Permanently delete $count $_temp0 from the printer? This cannot be undone.';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return 'Deleted $count $_temp0';
  }

  @override
  String get wearConnectionFailed => 'Connection failed';

  @override
  String get wearNoPrinters => 'No printers';

  @override
  String get wearPrinterUnavailable => 'Printer unavailable';

  @override
  String get wearNoActions => 'No actions available';

  @override
  String get wearClearPlate => 'Clear plate';

  @override
  String get wearPlateCleared => 'Plate cleared';

  @override
  String get wearStarted => 'Started';

  @override
  String get wearPhoneUnreachable => 'Phone unreachable';

  @override
  String get wearPhoneNoResponse => 'Phone did not respond';

  @override
  String get wearConfirm => 'Confirm';

  @override
  String get wearServerUrl => 'Server URL';

  @override
  String get wearConnect => 'Connect';

  @override
  String get wearAuthKey => 'Key';

  @override
  String get wearAuthLogin => 'Login';

  @override
  String get wearUsername => 'Username';
}
