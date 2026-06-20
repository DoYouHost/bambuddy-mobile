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
  String get wifiTooltip => 'Wi-Fi signal';

  @override
  String get doorOpen => 'Door open';

  @override
  String get doorClosed => 'Door closed';

  @override
  String get statusUnavailable => 'status unavailable';

  @override
  String get statusOffline => 'OFFLINE';

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
  String get navDashboard => 'Dashboard';

  @override
  String get navQueue => 'Queue';

  @override
  String get navArchive => 'Archive';

  @override
  String get navMaintenance => 'Maintenance';

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
}
