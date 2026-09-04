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
  String get signInRequiredTitle => 'Sign in again';

  @override
  String get signInRequiredBody =>
      'The server rejected your saved password, so the app stopped retrying it — repeated attempts get an account locked out. Sign in again, and use a new password if it was changed.';

  @override
  String get signInRequiredAction => 'Sign in';

  @override
  String get signInRequiredTwoFactorBody =>
      'Your account now asks for a second factor, and the app cannot supply one in the background — so it stopped signing in on its own. Sign in again and enter the code.';

  @override
  String get later => 'Later';

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
  String get filePickerFailed => 'The file dialog could not be opened';

  @override
  String get retry => 'Try again';

  @override
  String get back => 'Back';

  @override
  String get searchPrinters => 'Search printers…';

  @override
  String get noPrinters => 'No printers — add them on the server';

  @override
  String noSearchResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get noPrintersMatchFilters => 'No printers match the current filters';

  @override
  String get dashboardFilters => 'Filters';

  @override
  String get filterStatus => 'Status';

  @override
  String get filtersClear => 'Clear';

  @override
  String get hideOffline => 'Hide offline';

  @override
  String get statusAll => 'All';

  @override
  String get statusPrinting => 'Printing';

  @override
  String get statusIdle => 'Idle';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusFinished => 'Finished';

  @override
  String get statusErrorFilter => 'Error';

  @override
  String get statusOfflineFilter => 'Offline';

  @override
  String get addPrinterTitle => 'Add printer';

  @override
  String get addPrinterName => 'Name';

  @override
  String get addPrinterIp => 'IP address';

  @override
  String get addPrinterSerial => 'Serial number';

  @override
  String get addPrinterAccessCode => 'Access code';

  @override
  String get addPrinterModel => 'Model';

  @override
  String get addPrinterModelOptional => 'Optional';

  @override
  String get addPrinterModelNone => 'Not set';

  @override
  String get addPrinterLocation => 'Location';

  @override
  String get addPrinterLocationOptional => 'Optional';

  @override
  String get addPrinterSubmit => 'Add printer';

  @override
  String get addPrinterConnectionNote =>
      'The server verifies the connection before saving, so a wrong IP or access code is reported and nothing is created.';

  @override
  String get addPrinterRequiredField => 'Required';

  @override
  String get addPrinterSuccess => 'Printer added';

  @override
  String get addPrinterErrConnection =>
      'Could not connect to the printer. Check the IP address, serial number and access code, and make sure LAN-only mode is on.';

  @override
  String get addPrinterErrDuplicate =>
      'A printer with this serial number already exists';

  @override
  String get addPrinterErrForbidden =>
      'You do not have permission to add printers';

  @override
  String get addPrinterErrGeneric => 'Could not add the printer. Try again.';

  @override
  String get addPrinterAutoArchive => 'Auto-archive completed prints';

  @override
  String get addPrinterScanTitle => 'Find printers on the network';

  @override
  String get addPrinterSubnet => 'Subnet to scan';

  @override
  String get addPrinterScanButton => 'Scan subnet for printers';

  @override
  String get addPrinterDiscoverNetwork => 'Discover printers on network';

  @override
  String addPrinterScanning(int scanned, int total) {
    return 'Scanning… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => 'Scanning…';

  @override
  String get addPrinterScanNoResults => 'No printers found';

  @override
  String get addPrinterScanError => 'Scan failed. Try again.';

  @override
  String get addPrinterSubnetCustomOption => 'Custom subnet…';

  @override
  String get addPrinterSubnetCustomLabel => 'Custom subnet (CIDR)';

  @override
  String get addPrinterSubnetDockerNote =>
      'Docker detected. Enter your printer\'s subnet in CIDR notation. Requires network_mode: host in docker-compose.yml.';

  @override
  String get addPrinterSubnetCustomNote =>
      'Use a custom subnet if your printer is on a different network than the server. The FTP (990) and MQTT (8883) ports must be reachable across the routing boundary.';

  @override
  String get addPrinterDiagnostic => 'Run diagnostic';

  @override
  String get addPrinterDiagnosticRunning => 'Running diagnostic…';

  @override
  String get addPrinterDiagnosticError => 'Diagnostic failed. Try again.';

  @override
  String get diagOverallOk => 'All checks passed';

  @override
  String get diagOverallWarnings => 'Completed with warnings';

  @override
  String get diagOverallProblems => 'Problems found';

  @override
  String get diagCheckPortMqtt => 'MQTT port (8883)';

  @override
  String get diagCheckPortFtps => 'FTPS port (990)';

  @override
  String get diagCheckPortRtsps => 'Camera port (322)';

  @override
  String get diagCheckNetworkMode => 'Network mode';

  @override
  String get diagCheckSubnet => 'Subnet reachability';

  @override
  String get diagCheckMqttAuth => 'MQTT credentials';

  @override
  String get diagCheckDeveloperMode => 'Developer / LAN mode';

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
  String get ctrlFanPart => 'Part cooling fan';

  @override
  String get ctrlFanAux => 'Aux fan';

  @override
  String get ctrlFanAux2 => 'Left aux fan';

  @override
  String get ctrlFanChamber => 'Chamber fan';

  @override
  String get ctrlFanExhaust => 'Exhaust fan';

  @override
  String get ctrlFanPartShort => 'Part';

  @override
  String get ctrlFanAuxShort => 'Aux';

  @override
  String get ctrlFanAux2Short => 'Aux L';

  @override
  String get ctrlFanChamberShort => 'Chamber';

  @override
  String get ctrlFanExhaustShort => 'Exhaust';

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
  String get ctrlOff => 'Off';

  @override
  String get ctrlSet => 'Set';

  @override
  String get ctrlActivate => 'Activate';

  @override
  String get ctrlNozzleActive => 'Active';

  @override
  String get ctrlDry => 'Dry';

  @override
  String get ctrlDrying => 'Drying';

  @override
  String get ctrlDryStart => 'Start';

  @override
  String get ctrlDryFilament => 'Filament';

  @override
  String get ctrlDryTemp => 'Temperature';

  @override
  String get ctrlDryDuration => 'Duration';

  @override
  String ctrlDryHours(int h) {
    return '$h h';
  }

  @override
  String get ctrlDryAutoIdle => 'Auto-drying when humidity is high.';

  @override
  String get ctrlDryAutoQueue => 'Auto-drying between queued prints.';

  @override
  String get ctrlDryAutoWhilePrinting => 'During prints, too.';

  @override
  String get ctrlDryStartWhen => 'Start time';

  @override
  String get ctrlDryStartNow => 'Now';

  @override
  String get ctrlDryStartAfter => 'Later';

  @override
  String get ctrlDryStartAt => 'At time';

  @override
  String get ctrlDryPickTime => 'Pick a time';

  @override
  String get ctrlDrySchedule => 'Schedule';

  @override
  String get ctrlDryScheduled => 'Drying scheduled';

  @override
  String get ctrlDryScheduleTimePast => 'Pick a time in the future';

  @override
  String ctrlDryScheduledFor(String time) {
    return 'Drying at $time';
  }

  @override
  String get ctrlDryScheduledAsap =>
      'Drying scheduled, waiting for the printer';

  @override
  String get ctrlDryScheduleCancel => 'Cancel scheduled drying';

  @override
  String get ctrlDryScheduleDismiss => 'Dismiss';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return 'Scheduled drying failed: $reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => 'unknown error';

  @override
  String get ctrlDryWaitPower => 'Connect the AMS power adapter';

  @override
  String get ctrlDryWaitRetract => 'Retract the filament at the AMS outlet';

  @override
  String get ctrlDryWaitBlocked => 'The AMS cannot start drying right now';

  @override
  String get ctrlDryWaitAmsNotFound => 'Waiting for the AMS to be detected';

  @override
  String get ctrlDryWaitOffline => 'Waiting for the printer to come online';

  @override
  String get ctrlDryWaitBusy => 'Waiting for the printer to be free';

  @override
  String get ctrlDryWaitAlreadyDrying =>
      'Waiting for the current cycle to finish';

  @override
  String get ctrlDryWaitInterrupted =>
      'Interrupted, will restart when the printer is free';

  @override
  String get ctrlMove => 'Move';

  @override
  String get ctrlMoveHome => 'Home all';

  @override
  String get ctrlMoveHomeStarted => 'Homing started';

  @override
  String get ctrlMoveStep => 'Step';

  @override
  String get ctrlMoveZ => 'Z (bed gap)';

  @override
  String get ctrlMoveZUp => 'Up';

  @override
  String get ctrlMoveZDown => 'Down';

  @override
  String get ctrlMoveExtruder => 'Extruder';

  @override
  String get ctrlMoveExtrude => 'Extrude';

  @override
  String get ctrlMoveRetract => 'Retract';

  @override
  String get ctrlMoveLength => 'Length';

  @override
  String ctrlMoveMm(int d) {
    return '$d mm';
  }

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
  String get ctrlForbidden => 'No permission to control this printer';

  @override
  String get ctrlFailed => 'Couldn\'t send the command';

  @override
  String get skipObjectsTitle => 'Skip objects';

  @override
  String get skipObjectsSkip => 'Skip';

  @override
  String get skipObjectsSkippedTag => 'Skipped';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Skipped $count objects',
      one: 'Skipped \"$names\"',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Skip $count objects?',
      one: 'Skip this object?',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '\"$names\" will be skipped for the rest of this print. This can\'t be undone.',
      one:
          '\"$names\" will be skipped for the rest of this print. This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get skipObjectsSelectHint =>
      'Tap an object above or below to select it for skipping';

  @override
  String get skipObjectsMatchInfo => 'Match IDs with your printer display';

  @override
  String get skipObjectsMatchHint =>
      'The printer screen shows object IDs on the build plate';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '$skipped/$total skipped';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count active';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return 'Skipping is available from layer 2 (currently layer $layer)';
  }

  @override
  String get skipObjectsEmpty => 'No printable objects';

  @override
  String get skipObjectsEmptyHint =>
      'Objects load when a print starts. Reload if a print is running.';

  @override
  String get skipObjectsReload => 'Reload';

  @override
  String get skipObjectsLoadFailed => 'Couldn\'t load printable objects.';

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
  String get smartPlugMonitorOnly => 'Monitoring only';

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
  String get queueAmsFromSlicer => 'AMS from slicer';

  @override
  String queueAnyOfModels(String models) {
    return 'Any of: $models';
  }

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
  String get archiveNoMatches => 'No prints match your filters';

  @override
  String get archiveFilters => 'Filters';

  @override
  String get archiveFiltersClear => 'Clear filters';

  @override
  String get archiveSortLabel => 'Sort by';

  @override
  String get archiveSortDateDesc => 'Newest first';

  @override
  String get archiveSortDateAsc => 'Oldest first';

  @override
  String get archiveSortNameAsc => 'Name A–Z';

  @override
  String get archiveSortNameDesc => 'Name Z–A';

  @override
  String get archiveSortSizeDesc => 'Largest first';

  @override
  String get archiveSortSizeAsc => 'Smallest first';

  @override
  String get archiveFilterFileType => 'Files';

  @override
  String get archiveFileTypeAll => 'All files';

  @override
  String get archiveFileTypeGcode => 'Sliced';

  @override
  String get archiveFileTypeSource => 'Source';

  @override
  String get archiveFilterFlags => 'Show';

  @override
  String get archiveFilterFavorites => 'Favorites';

  @override
  String get archiveFilterHideFailed => 'Hide failed';

  @override
  String get archiveFilterHideDuplicates => 'Hide duplicates';

  @override
  String get archiveFilterPrinter => 'Printer';

  @override
  String get archiveFilterMaterial => 'Material';

  @override
  String get archiveFilterColors => 'Colors';

  @override
  String get archiveColorModeAny => 'Any';

  @override
  String get archiveColorModeAll => 'All';

  @override
  String get archiveFavorite => 'Add to favorites';

  @override
  String get archiveUnfavorite => 'Remove from favorites';

  @override
  String get archiveFavoriteFailed => 'Couldn\'t update favorite';

  @override
  String get archiveReprint => 'Reprint';

  @override
  String get archiveAddToQueue => 'Add to queue';

  @override
  String get archiveTimelapse => 'Watch timelapse';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View photos ($count)',
      one: 'View photo',
    );
    return '$_temp0';
  }

  @override
  String archivePlate(int plate) {
    return 'Plate $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return 'Plate $plate of a multi-plate file';
  }

  @override
  String get archivePhotosTitle => 'Photos';

  @override
  String get archivePhotosEmpty => 'No photos for this print';

  @override
  String get archivePhotoFailed => 'Couldn\'t load this photo.';

  @override
  String get archiveFilamentUsed => 'Filament used';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used $grams over $count runs',
      one: 'Used $grams',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => 'No usage recorded';

  @override
  String get archiveFilamentSaving => 'Saving';

  @override
  String get archiveFilamentNone => 'Not recorded';

  @override
  String get archiveFilamentLabel => 'Weight (g)';

  @override
  String get archiveFilamentNotANumber =>
      'Enter a number, or leave it empty to clear the weight.';

  @override
  String archiveFilamentOutOfRange(String max) {
    return 'A weight between 0 and $max g.';
  }

  @override
  String get archiveFilamentSaved => 'Filament weight saved';

  @override
  String get archiveFilamentUnsupported =>
      'This server doesn\'t store a typed-in filament weight yet. Update bambuddy.';

  @override
  String get archiveHasTimelapse => 'Has a timelapse';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Has $count photos',
      one: 'Has a photo',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => 'Timelapse';

  @override
  String get timelapseError => 'Couldn\'t play this timelapse.';

  @override
  String timelapseHttpError(int status) {
    return 'The server would not hand over this timelapse ($status).';
  }

  @override
  String get timelapseStalled =>
      'The server is serving the video, but the player never started it.';

  @override
  String get timelapsePlay => 'Play';

  @override
  String get timelapsePause => 'Pause';

  @override
  String get timelapseSave => 'Save to gallery';

  @override
  String get timelapseShare => 'Share';

  @override
  String get timelapseSaved => 'Saved to the gallery';

  @override
  String get timelapseSaveFailed => 'Couldn\'t save the video';

  @override
  String get timelapseSaveDenied =>
      'Bambuddy needs permission to write to the gallery on this Android version.';

  @override
  String get timelapseEdit => 'Edit';

  @override
  String get timelapseEditSave => 'Save';

  @override
  String get timelapseEditTitle => 'Edit timelapse';

  @override
  String get timelapseEditTrim => 'Trim';

  @override
  String get timelapseEditSpeed => 'Speed';

  @override
  String timelapseEditOutput(String length) {
    return 'Result: $length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return 'Original: $length at $width×$height';
  }

  @override
  String get timelapseEditSaveTitle => 'Overwrite the recording?';

  @override
  String get timelapseEditSaveMessage =>
      'The server re-encodes the timelapse and replaces the original. There is no copy to go back to.';

  @override
  String get timelapseEditProcessing =>
      'The server is re-encoding the video. On a small host this takes minutes — leaving this screen does not stop it.';

  @override
  String get timelapseEdited => 'Timelapse updated';

  @override
  String get gcodeViewerTitle => 'G-code preview';

  @override
  String get gcodeViewerOpen => 'Preview G-code';

  @override
  String get gcodeViewerError => 'Couldn\'t load the G-code preview.';

  @override
  String get gcodeViewerLoading => 'Downloading G-code…';

  @override
  String get gcodeViewerParsing => 'Reading the toolpath…';

  @override
  String get gcodeViewerTravels => 'Travel moves';

  @override
  String get gcodeViewerColorByFilament => 'Filament';

  @override
  String get gcodeViewerColorByFeature => 'Feature';

  @override
  String get gcodeViewerColorByHeight => 'Height';

  @override
  String get gcodeViewerColorByWidth => 'Width';

  @override
  String get gcodeSingleLayer => 'single layer';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return 'Filament $n';
  }

  @override
  String get gcodeViewerEmpty =>
      'There is no toolpath in this file — it hasn\'t been sliced yet.';

  @override
  String gcodeViewerHttpError(int status) {
    return 'The server would not hand over the G-code for this file ($status).';
  }

  @override
  String get gcodeFeatureWall => 'Walls';

  @override
  String get gcodeFeatureSparseInfill => 'Sparse infill';

  @override
  String get gcodeFeatureSolidInfill => 'Solid infill';

  @override
  String get gcodeFeatureSkirt => 'Skirt / brim';

  @override
  String get gcodeFeatureSupport => 'Support';

  @override
  String get gcodeFeatureGapFill => 'Gap fill';

  @override
  String get gcodeFeatureBridge => 'Bridge / overhang';

  @override
  String get gcodeFeatureIroning => 'Ironing';

  @override
  String get gcodeFeaturePrimeTower => 'Prime tower';

  @override
  String get archiveNo3mfTitle =>
      'Some recent prints archived without their thumbnails';

  @override
  String get archiveNo3mfBody =>
      'The slicer didn\'t leave the .gcode.3mf on the printer\'s card, so Bambuddy couldn\'t pull the thumbnail or the slicer metadata. Usually \"Store sent files on external storage\" is off in the slicer\'s Device tab.';

  @override
  String get archiveNo3mfTitleInternal =>
      'Some recent prints stayed on the printer\'s internal storage';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio put the sliced file on the printer\'s internal storage instead of the card, so there was nothing to read over FTP. On H2-series and P2S the Print button always does that — switching the slicer setting on changes nothing. Those prints are still archived with their name and timing, just without a thumbnail or slicer metadata. For complete archives, start the print from Bambuddy or slice in OrcaSlicer — either way with a card or stick in the printer.';

  @override
  String get archiveNo3mfTitleNoStorage =>
      'Some recent prints couldn\'t be archived — no storage in the printer';

  @override
  String get archiveNo3mfBodyNoStorage =>
      'The printer reports no card or stick in its slot, so the sliced file had nowhere to land and Bambuddy had nothing to read. Insert one and the next print archives in full.';

  @override
  String get archiveNo3mfDocs => 'See install step 4';

  @override
  String get archiveNo3mfDocsWhy => 'Why this happens';

  @override
  String get archiveNo3mfDismiss => 'Dismiss this notice';

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
  String get cameraDemoUnavailable =>
      'Camera preview is not available in demo mode';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'External spool';

  @override
  String get traySlotEmpty => 'Empty';

  @override
  String get amsSlotFilament => 'Filament';

  @override
  String get amsLoad => 'Load';

  @override
  String get amsUnload => 'Unload';

  @override
  String get amsRfidReread => 'Re-read tag';

  @override
  String get amsLoadStarted => 'Loading filament…';

  @override
  String get amsUnloadStarted => 'Unloading filament…';

  @override
  String get amsRfidRereadStarted => 'Re-reading the tag…';

  @override
  String amsFeedTitle(String slot) {
    return 'Feed $slot into which nozzle?';
  }

  @override
  String get amsFeedPrompt =>
      'The Filament Track Switch can route this slot to either nozzle, so the printer cannot work out where the filament should go.';

  @override
  String get amsFeedAlreadyLoaded => 'already loaded';

  @override
  String get amsSwitchNotReady =>
      'The Filament Track Switch is not set up yet. Assign every AMS to an inlet on the printer, then try again.';

  @override
  String get amsUnloadSlotNotLoaded => 'No nozzle is fed from this slot';

  @override
  String get amsActionsWhilePrinting =>
      'Unavailable while the printer is printing';

  @override
  String get amsSlotConfigure => 'Configure slot';

  @override
  String get amsSlotConfigTitle => 'Slot configuration';

  @override
  String get amsSlotConfigSearch => 'Search presets';

  @override
  String get amsSlotConfigColour => 'Colour';

  @override
  String get amsSlotConfigApply => 'Write to printer';

  @override
  String get amsSlotConfigStarted => 'Configuring the slot…';

  @override
  String get amsSlotConfigNameNotSaved =>
      'Slot configured, but the preset name could not be saved';

  @override
  String get amsSlotConfigEmpty => 'No filament presets available';

  @override
  String get amsSlotConfigNoMatch => 'No preset matches the search';

  @override
  String get amsSlotConfigCloudHint =>
      'Log in to Bambu Cloud to pick from your own presets.';

  @override
  String get amsSlotConfigCloudAction => 'Log in';

  @override
  String get amsSlotConfigTierLocal => 'Imported';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => 'Built-in';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return 'Only for $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return 'Only for $model ($hidden hidden)';
  }

  @override
  String get amsSlotConfigModelUnknown =>
      'Printer model unknown — showing every preset';

  @override
  String get amsSlotConfigCurrent => 'Currently set';

  @override
  String get amsSlotConfigKProfile => 'K profile';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return 'Default (K $value)';
  }

  @override
  String get amsSlotConfigKProfileOther => 'Other profiles';

  @override
  String get amsSlotConfigKProfileNone =>
      'This printer has no stored K profiles for this nozzle';

  @override
  String get amsSlotConfigKProfileUnavailable =>
      'Could not read the printer\'s K profiles';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return 'The printer did not report its nozzle size — assuming $diameter mm';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => 'Catalogue colours';

  @override
  String get amsSlotConfigColourCustom => 'Custom colour';

  @override
  String get amsSlotReset => 'Clear slot';

  @override
  String get amsSlotResetConfirmTitle => 'Clear this slot?';

  @override
  String get amsSlotResetConfirmMessage =>
      'The printer forgets the filament configured here, and bambuddy forgets which preset it was.';

  @override
  String get amsSlotResetStarted => 'Clearing the slot…';

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
  String get sensorHistoryCurrent => 'Current';

  @override
  String get sensorHistoryAverage => 'Average';

  @override
  String get sensorHistoryMin => 'Min';

  @override
  String get sensorHistoryMax => 'Max';

  @override
  String get sensorHistoryRange6h => '6h';

  @override
  String get sensorHistoryRange24h => '24h';

  @override
  String get sensorHistoryRange48h => '48h';

  @override
  String get sensorHistoryRange7d => '7d';

  @override
  String get amsHistoryGood => 'Good';

  @override
  String get amsHistoryFair => 'Fair';

  @override
  String get sensorHistoryEmpty => 'No data for this range';

  @override
  String get sensorHistoryError => 'Couldn\'t load history';

  @override
  String get amsHistoryRecordingInfo =>
      'Recorded every 5 minutes while the printer is connected';

  @override
  String get heaterHistoryTitle => 'Temperature history';

  @override
  String get heaterHistoryOpen => 'Temperature history';

  @override
  String get heaterHistoryReading => 'Reading';

  @override
  String get heaterHistoryTarget => 'Target';

  @override
  String get heaterHistoryRecordingInfo =>
      'Recorded every minute while the printer is connected';

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
  String get widgetMultiTitle => 'Printers';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total active';
  }

  @override
  String widgetMultiMore(int count) {
    return '+$count more';
  }

  @override
  String get widgetMultiGaugeLabel => 'printing';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count idle';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count offline';
  }

  @override
  String get widgetMultiName => 'Bambuddy · Printers';

  @override
  String get widgetMultiDescription => 'All printers at a glance';

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
    return '${minutes}min';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String durationHours(int hours) {
    return '${hours}h';
  }

  @override
  String durationSeconds(int seconds) {
    return '${seconds}s';
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
  String get twoFactorTitle => 'Two-factor authentication';

  @override
  String get twoFactorMethodTotp => 'Authenticator';

  @override
  String get twoFactorMethodEmail => 'E-mail';

  @override
  String get twoFactorMethodBackup => 'Backup code';

  @override
  String get twoFactorExplainTotp =>
      'Enter the 6-digit code from your authenticator app.';

  @override
  String get twoFactorExplainEmail =>
      'Have the server e-mail you a 6-digit code, then enter it here.';

  @override
  String get twoFactorExplainEmailSent =>
      'A 6-digit code has been sent to the address on your account. It expires in 10 minutes.';

  @override
  String get twoFactorExplainBackup =>
      'Enter one of the 8-character backup codes you saved when setting up 2FA. Each one works once.';

  @override
  String get twoFactorCodeLabel => 'Code';

  @override
  String get twoFactorSendEmail => 'E-mail me a code';

  @override
  String get twoFactorResendEmail => 'Send another code';

  @override
  String get twoFactorVerify => 'Confirm and connect';

  @override
  String get twoFactorBack => 'Use a different account';

  @override
  String get twoFactorSessionNote =>
      'The app cannot renew a 2FA session on its own, so it will ask again when this one expires. An API key does not expire and skips this step.';

  @override
  String get tryDemo => 'Try the demo';

  @override
  String get scanApiKeyTitle => 'Scan API key';

  @override
  String get scanApiKeyHint => 'Point the camera at the API key QR code';

  @override
  String get cameraPermissionTitle => 'Camera access needed';

  @override
  String get cameraPermissionBody => 'Allow camera access to scan QR codes.';

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
  String get errForbidden => 'Not allowed — the server refused this action';

  @override
  String errForbiddenDetail(String reason) {
    return 'Not allowed: $reason';
  }

  @override
  String get errApiKeyOwnerDisabled =>
      'The account that owns this API key has been deactivated or deleted — the key stays refused until that account is restored.';

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
  String get errTwoFactorCodeRejected => 'Wrong code — check it and try again.';

  @override
  String get errTwoFactorChallengeExpired =>
      'The sign-in attempt expired — enter your password again to get a new code.';

  @override
  String get errTwoFactorMethodUnavailable =>
      'That method is not available on this account — pick another one.';

  @override
  String get errTwoFactorEmailUnavailable =>
      'The server could not send the code — it has no e-mail set up, or your account has no address. Use another method.';

  @override
  String get errMissingTwoFactorCode => 'Enter the code';

  @override
  String get errApiKeyRejected =>
      'API key rejected — check the key and its scope (can_read_status required)';

  @override
  String get errTooManyAttempts =>
      'Too many attempts — the server is blocking sign-in for a few minutes. Wait and try again, or use an API key.';

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
  String get notifExtrasHeader => 'Details';

  @override
  String get notifFinishPhotoTitle => 'Photo of the finished print';

  @override
  String get notifFinishPhotoDesc =>
      'Adds the shot the server takes when a print ends to the finished/failed notification, once it arrives';

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
  String get hmsErrorsHeader => 'Active errors';

  @override
  String get hmsViewInWiki => 'Open in Bambu wiki';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => 'Dismiss all';

  @override
  String get hmsDismissed => 'Errors cleared on the printer';

  @override
  String get hmsDismissFailed => 'Could not clear the errors';

  @override
  String get hmsActionSent => 'Sent to the printer';

  @override
  String get hmsActionFailed => 'The printer refused the action';

  @override
  String get hmsActionNotAcknowledged =>
      'The printer did not confirm the action — check its screen';

  @override
  String get hmsStopConfirmTitle => 'Stop the print?';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer will abandon the print job. This cannot be undone.';
  }

  @override
  String get hmsStopConfirmAction => 'Stop printing';

  @override
  String get hmsActionResume => 'Resume';

  @override
  String get hmsActionResumeDefects => 'Resume anyway';

  @override
  String get hmsActionResumeSolved => 'Fixed, resume';

  @override
  String get hmsActionProblemSolvedResume => 'Fixed, resume';

  @override
  String get hmsActionFilamentLoadedResume => 'Loaded, resume';

  @override
  String get hmsActionProceed => 'Proceed';

  @override
  String get hmsActionStopPrinting => 'Stop';

  @override
  String get hmsActionIgnoreResume => 'Ignore, resume';

  @override
  String get hmsActionIgnoreNoReminder => 'Ignore always';

  @override
  String get hmsActionDontRemind => 'Don\'t remind';

  @override
  String get hmsActionNoReminder => 'Dismiss';

  @override
  String get hmsActionFilamentExtruded => 'Extruded';

  @override
  String get hmsActionRetryFilamentExtruded => 'Not yet, retry';

  @override
  String get hmsActionContinue => 'Done, continue';

  @override
  String get hmsActionRetrySolved => 'Fixed, retry';

  @override
  String get hmsActionDone => 'Done';

  @override
  String get hmsActionRetry => 'Retry';

  @override
  String get hmsActionResumePlain => 'Resume';

  @override
  String get hmsActionConfirm => 'Confirm';

  @override
  String get hmsActionAbort => 'Abort';

  @override
  String get hmsActionOk => 'OK';

  @override
  String get hmsActionRecheck => 'Recheck';

  @override
  String get hmsActionTurnOffFireAlarm => 'Turn off alarm';

  @override
  String get hmsActionStopDrying => 'Stop drying';

  @override
  String get hmsActionDisablePurification => 'Disable purification';

  @override
  String get batteryOptTitle => 'Reliable background notifications';

  @override
  String get batteryOptBody =>
      'To keep print notifications working when the app is in the background, allow Bambuddy to run without battery restrictions. On Samsung phones this is essential.';

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
  String get bgServiceTitle => 'Bambuddy';

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
  String inventoryTotalConsumed(String weight) {
    return '$weight consumed';
  }

  @override
  String inventoryConsumedSinceReset(String weight) {
    return 'Consumed since reset: $weight';
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
  String inventoryFieldRange(int min, int max) {
    return 'Enter a value from $min to $max';
  }

  @override
  String get inventoryFieldNegative => 'Enter a value of 0 or more';

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
      'Reset the consumed-filament counter to zero? Future prints count from zero again — the remaining weight is not changed.';

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
  String get inventoryUsageReset => 'Counter reset';

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
  String get inventoryFromSlot => 'Add to inventory';

  @override
  String get inventoryFromSlotHint =>
      'Register the tagged spool the printer reports in this slot';

  @override
  String get inventoryFromSlotDone => 'Spool added and assigned to the slot';

  @override
  String get inventoryFromSlotNoTag =>
      'The printer no longer reports a tagged spool in this slot';

  @override
  String get inventoryFromSlotOffline =>
      'The printer is not connected, so it cannot say what is in the slot';

  @override
  String get inventoryFromSlotUnsupported =>
      'This server version cannot add a spool straight from a slot';

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
  String inventorySelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get inventorySelectAll => 'Select all';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Archive $count $_temp0?';
  }

  @override
  String get inventoryBulkArchiveBody =>
      'They will be hidden from the active list. You can restore them later.';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Restore $count $_temp0?';
  }

  @override
  String get inventoryBulkRestoreBody => 'They will return to the active list.';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Delete $count $_temp0?';
  }

  @override
  String get inventoryBulkDeleteBody =>
      'This permanently removes them and cannot be undone.';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Reset usage on $count $_temp0?';
  }

  @override
  String get inventoryBulkResetBody =>
      'Their consumed-filament counters go back to zero. Remaining weights are not changed.';

  @override
  String inventoryBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return '$count $_temp0 updated';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return '$ok done, $failed failed';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return '$ok done, $skipped already there';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return '$ok done, $skipped already there, $failed failed';
  }

  @override
  String get inventoryBulkEdit => 'Edit fields';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Edit $count $_temp0';
  }

  @override
  String get inventoryBulkEditHint =>
      'Only the fields you fill in change. Leave the rest blank.';

  @override
  String get inventoryBulkEditUnchanged => 'Unchanged';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Apply to $count $_temp0';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'spools',
      one: 'spool',
    );
    return 'Change $count $_temp0?';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: 'fields',
      one: 'field',
    );
    return '$fields $_temp0 will be overwritten on every selected spool.';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      'This server is too old for mass edit. Update bambuddy, or edit the spools one at a time.';

  @override
  String get inventoryApply => 'Apply';

  @override
  String get inventoryLabelsTitle => 'Print spool labels';

  @override
  String get inventoryLabelsPrint => 'Print labels';

  @override
  String get inventoryLabelsPrintAll => 'Print labels for all';

  @override
  String get inventoryLabelsSearchHint => 'Search name, brand, or #ID';

  @override
  String get inventoryLabelsPickSpools =>
      'Pick which spools to print labels for:';

  @override
  String get inventoryLabelsMaterial => 'Material:';

  @override
  String get inventoryLabelsAllMaterials => 'All';

  @override
  String get inventoryLabelsSort => 'Sort:';

  @override
  String get inventoryLabelsSortById => 'By ID';

  @override
  String get inventoryLabelsSortByColor => 'By colour';

  @override
  String get inventoryLabelsSelectVisible => 'Select visible';

  @override
  String get inventoryLabelsDeselectVisible => 'Deselect visible';

  @override
  String get inventoryLabelsClearAll => 'Clear all';

  @override
  String get inventoryLabelsNoMatches =>
      'No spools match the current search or filter.';

  @override
  String get inventoryLabelsMonochrome => 'Monochrome (black & white printer)';

  @override
  String get inventoryLabelsMonochromeHint =>
      'Drops the colour swatch and widens the text';

  @override
  String get inventoryLabelsShare => 'Share PDF instead of printing';

  @override
  String get inventoryLabelsPickTemplate => 'Pick a label size to print:';

  @override
  String inventoryLabelsTooMany(int max) {
    return 'Pick at most $max spools per print';
  }

  @override
  String get inventoryLabelsFailed => 'Could not generate labels';

  @override
  String get inventoryLabelsAmsSmall => 'AMS holder — small (74 × 33 mm)';

  @override
  String get inventoryLabelsAmsSmallHint =>
      'One per page; matches the printable label from MakerWorld model 752566.';

  @override
  String get inventoryLabelsAmsLarge => 'AMS holder — large (75 × 55 mm)';

  @override
  String get inventoryLabelsAmsLargeHint =>
      'One per page; fits the cardstock-insert variant of the same holder.';

  @override
  String get inventoryLabelsBox40 => 'Box label (40 × 30 mm)';

  @override
  String get inventoryLabelsBox40Hint =>
      'One per page; common DK/Brother roll size, good for bags and bins.';

  @override
  String get inventoryLabelsBox62 => 'Box label (62 × 29 mm)';

  @override
  String get inventoryLabelsBox62Hint =>
      'One per page; sized for Brother PT/QL and Dymo small labels.';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 — A4 sheet (38.1 × 63.5 mm × 21)';

  @override
  String get inventoryLabelsAveryL7160Hint =>
      'EU sheet stock; 21 labels per A4 page.';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 — US Letter sheet (25.4 × 66.7 mm × 30)';

  @override
  String get inventoryLabelsAvery5160Hint =>
      'US sheet stock; 30 labels per Letter page.';

  @override
  String get inventoryLabelsStartTitle => 'First free label';

  @override
  String get inventoryLabelsStartHint =>
      'Tap the slot the first label should print in — the ones before it stay blank, so a part-used sheet gets finished instead of started over.';

  @override
  String inventoryLabelsStartSlot(int position) {
    return 'Position $position';
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
  String get statsEnergyOverTime => 'Energy over time';

  @override
  String get statsMostEnergy => 'Most energy used';

  @override
  String statsKwh(String value) {
    return '$value kWh';
  }

  @override
  String get statsByMaterialTitle => 'By material';

  @override
  String get statsSuccessByMaterial => 'Success by material';

  @override
  String get statsColorDistribution => 'Color distribution';

  @override
  String get statsColorShareHint => 'Share of filament used, by weight';

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
  String get aboutSourceBody => 'The full source is available on GitHub.';

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
  String get fmAddToQueue => 'Add to queue';

  @override
  String get fmAddedToQueue => 'Added to queue';

  @override
  String get fmGroupAsVariants => 'Group as alternatives';

  @override
  String get fmQueueAsVariants => 'Queue as one job';

  @override
  String get fmUngroupVariants => 'Ungroup alternatives';

  @override
  String fmVariantsGrouped(int count) {
    return '$count files grouped as alternatives';
  }

  @override
  String get fmVariantsUngrouped => 'Alternatives ungrouped';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count alternatives';
  }

  @override
  String get fmVariantsGone => 'This group no longer exists';

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
  String get fmTags => 'Tags';

  @override
  String get fmTagsFilterTitle => 'Filter by tags';

  @override
  String get fmTagsFilterHint =>
      'Tags search the whole library — the current folder is ignored.';

  @override
  String get fmTagsManage => 'Manage tags';

  @override
  String get fmTagsEmpty => 'No tags yet';

  @override
  String get fmTagsNone => 'No tags';

  @override
  String get fmTagsApply => 'Apply';

  @override
  String get fmTagNew => 'New tag';

  @override
  String get fmTagName => 'Tag name';

  @override
  String get fmTagRename => 'Rename tag';

  @override
  String get fmTagDelete => 'Delete tag';

  @override
  String fmTagDeleteConfirm(String name) {
    return 'Delete tag \"$name\"? Files keep everything else — they only lose this label.';
  }

  @override
  String get fmTagCreated => 'Tag created';

  @override
  String get fmTagDeleted => 'Tag deleted';

  @override
  String get fmTagExists => 'A tag with this name already exists';

  @override
  String get fmTagsSaved => 'Tags updated';

  @override
  String fmTagsPartial(int count, int total) {
    return 'Updated $count of $total files — the rest are not yours to edit';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return 'Tag $count $_temp0';
  }

  @override
  String get fmTagsAdd => 'Add';

  @override
  String get fmTagsRemove => 'Remove';

  @override
  String get fmTagsReplace => 'Replace';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return 'Replace all tags on $count $_temp0 with the selected ones?';
  }

  @override
  String get fmTagsPickSome => 'Pick at least one tag';

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
  String get projectTargetSets => 'Target sets';

  @override
  String get projectTargetSetsHint =>
      'How many times each file in the project should be printed';

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
  String get projectStatSets => 'Complete sets';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done of $target';
  }

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
  String get sliceAutoOrient => 'Auto orient';

  @override
  String get sliceAutoOrientHint =>
      'Turns each object onto its best printing side.';

  @override
  String get sliceAutoArrange => 'Auto arrange';

  @override
  String get sliceAutoArrangeHint => 'Lays the objects out on the plate again.';

  @override
  String sliceDesignedFor(String printer) {
    return 'This file is for $printer';
  }

  @override
  String get sliceUseDesignedPrinter => 'Switch';

  @override
  String get sliceAsDesigned => 'Use the file\'s own settings';

  @override
  String get sliceAsDesignedHint =>
      'The designer\'s settings instead of the profiles above.';

  @override
  String get sliceAsDesignedInactive => 'Not used — the file decides';

  @override
  String get sliceFilamentUnused => 'Not used by this plate';

  @override
  String get processSettingsTitle => 'Process settings';

  @override
  String get sliceProcessSettingsNeedsProcess => 'Pick a process preset first';

  @override
  String get sliceProcessSettingsUnchanged => 'Using the preset as it is';

  @override
  String sliceProcessSettingsChanged(int count) {
    return '$count changed';
  }

  @override
  String get processSettingsModeSimple => 'Simple';

  @override
  String get processSettingsModeAdvanced => 'Advanced';

  @override
  String get processSettingsModeExpert => 'Expert';

  @override
  String get processSettingsSearchHint => 'Search settings';

  @override
  String get processSettingsNoMatches => 'No settings match this search.';

  @override
  String get processSettingsRevert => 'Reset to the preset\'s value';

  @override
  String processSettingsRevertAll(int count) {
    return 'Reset $count';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return 'The slicer accepts $range';
  }

  @override
  String get processSettingsDisabledHint =>
      'The slicer ignores this with your current settings.';

  @override
  String get processSettingsUnavailable =>
      'This server cannot report process settings for the selected preset.';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      'Showing slicer defaults: your slicer sidecar is older than this feature and cannot report a preset\'s values. Update the sidecar image to see them. Anything you do not change still uses the preset.';

  @override
  String get processSettingsDefaultsNotConfigured =>
      'Showing slicer defaults: no slicer sidecar is configured, so a preset\'s values cannot be read. Anything you do not change still uses the preset.';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      'Showing slicer defaults: the slicer sidecar did not answer, so a preset\'s values cannot be read. Anything you do not change still uses the preset.';

  @override
  String get processSettingsDefaultsUnavailable =>
      'Showing slicer defaults: the selected preset\'s own values could not be read. Anything you do not change still uses the preset.';

  @override
  String get processSettingsFilamentDefault =>
      'Default (the region\'s own filament)';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot: $name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return 'Slot $slot — this file has no such slot';
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
  String get sliceExternalFallback =>
      'Saved in the server\'s library — the file\'s own folder could not take it.';

  @override
  String get sliceExternalReadonly => 'That folder is set to read-only.';

  @override
  String get sliceExternalNoPath => 'That folder has no path configured.';

  @override
  String get sliceExternalUnreachable =>
      'That folder\'s path is not reachable right now.';

  @override
  String get sliceExternalNotWritable =>
      'The server cannot write to that folder.';

  @override
  String get sliceExternalInvalidName =>
      'That folder would not take the file\'s name.';

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
  String get plateClearNeedsOnline =>
      'This server releases the plate only while the printer is connected. Update bambuddy to do it on a printer that is switched off.';

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
  String get pfmPrinterUnavailable =>
      'The printer did not answer, so its files could not be listed';

  @override
  String get pfmDownloadTooLarge =>
      'The selection is too large for the server to bundle';

  @override
  String get pfmDownloadNoServerSpace =>
      'The server has no room to prepare this download';

  @override
  String get pfmDownloadTookTooLong =>
      'Preparing the download took too long and the server gave up';

  @override
  String get pfmPreparingOnServer => 'Preparing on the server…';

  @override
  String get pfmDownloading => 'Downloading…';

  @override
  String get pfmDownloadCancelled => 'Download cancelled';

  @override
  String get pfmDownloadPrepareFailed =>
      'The server could not prepare this download';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: 'one file',
    );
    return 'Left out $_temp0 that could not be read from the printer';
  }

  @override
  String get pfmDownloadSaved => 'File saved';

  @override
  String get pfmDownloadNotSaved =>
      'The file could not be saved where you chose';

  @override
  String get pfmDownload => 'Download';

  @override
  String get pfmDelete => 'Delete';

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
  String get wearPlateNeedsOnline => 'This server needs the printer online';

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

  @override
  String get wearSetupPhoneTitle => 'Set up from your phone';

  @override
  String get wearSetupPhoneBody =>
      'Open Bambuddy on your paired phone — the watch takes the server and sign-in from it.';

  @override
  String get wearSetupPhoneCheck => 'Check again';

  @override
  String get wearSetupPhoneEmpty => 'Nothing from the phone yet.';

  @override
  String get wearSetupManual => 'Enter manually';

  @override
  String get wearSetupDemo => 'Demo';

  @override
  String get wearSetupTapToType => 'Tap to type';

  @override
  String get wearSettingsTitle => 'Settings';

  @override
  String get wearFromPhone => 'From your phone';

  @override
  String get wearFromPhoneUse => 'Use this server';

  @override
  String get wearFromPhoneLater => 'Not now';

  @override
  String get wearAuthNone => 'No sign-in';

  @override
  String get wearFromPhoneWaiting => 'The phone offers a different server.';

  @override
  String get wearCurrentServer => 'Current server';

  @override
  String get wearOk => 'OK';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonAuto => 'Auto';

  @override
  String get queueEdit => 'Edit';

  @override
  String get queueEditTitle => 'Edit Queue Item';

  @override
  String get queueEditSave => 'Save';

  @override
  String get queueEditSaved => 'Queue item updated';

  @override
  String get queueCreateTitle => 'Print';

  @override
  String get queueCreateSubmit => 'Print';

  @override
  String get queueCreateAdded => 'Added to queue';

  @override
  String get queueEditPrintJob => 'Print Job';

  @override
  String get queueEditTarget => 'Target';

  @override
  String get queueEditSpecificPrinter => 'Specific Printer';

  @override
  String queueEditAnyModel(String model) {
    return 'Any $model';
  }

  @override
  String get queueEditAnyModelGeneric => 'Any Model';

  @override
  String get queueEditTargetModel => 'Model';

  @override
  String get queueEditTargetLocation => 'Location';

  @override
  String get queueEditAnyLocation => 'Any location';

  @override
  String get queueEditMappingNeedsPrinter =>
      'Select a printer to map filaments';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'slots',
      one: 'slot',
    );
    return '$count $_temp0 mapped';
  }

  @override
  String get queueEditMappingAuto => 'Auto (no manual mapping)';

  @override
  String get queueEditPlate => 'Plate';

  @override
  String queueEditPlateSelected(int plate) {
    return 'Plate $plate';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return 'Plate $plate · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return 'This job prints plate $plate';
  }

  @override
  String get queuePlatePickTitle => 'Which plate?';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objects',
      one: '1 object',
      zero: 'No objects',
    );
    return '$_temp0';
  }

  @override
  String get queueEditPrintOptions => 'Print Options';

  @override
  String get queueOptBedLevelling => 'Bed Levelling';

  @override
  String get queueOptBedLevellingDesc => 'Auto-level bed before print';

  @override
  String get queueOptFlowCali => 'Flow Calibration';

  @override
  String get queueOptFlowCaliDesc => 'Calibrate extrusion flow';

  @override
  String get queueOptVibrationCali => 'Vibration Calibration';

  @override
  String get queueOptVibrationCaliDesc => 'Reduce ringing artifacts';

  @override
  String get queueOptLayerInspect => 'First Layer Inspection';

  @override
  String get queueOptLayerInspectDesc => 'AI inspection of first layer';

  @override
  String get queueOptTimelapse => 'Timelapse';

  @override
  String get queueOptTimelapseDesc => 'Record timelapse video';

  @override
  String get queueOptNozzleOffset => 'Nozzle Offset Calibration';

  @override
  String get queueOptNozzleOffsetDesc =>
      'Calibrate nozzle offsets between extruders';

  @override
  String get queueEditPreheat => 'Preheat & Heat Soak';

  @override
  String get queueEditPreheatDesc =>
      'Heat the bed and chamber before this print starts. Defaults to the global Settings → Workflow toggle.';

  @override
  String get queuePreheatInherit => 'Inherit';

  @override
  String get queueEditChamberTarget =>
      'Chamber target override (°C, blank = filament default)';

  @override
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

  @override
  String get queueEditWhenToPrint => 'When to print';

  @override
  String get queueScheduleAsap => 'ASAP';

  @override
  String get queueScheduleQueue => 'Queue';

  @override
  String get queueScheduleSchedule => 'Schedule';

  @override
  String get queueEditPickTime => 'Pick date & time';

  @override
  String get queueEditRequireManualStart => 'Require manual start';

  @override
  String get queueEditRequirePrevious =>
      'Only start if previous print succeeded';

  @override
  String get queueEditPowerOff => 'Power off printer when done';

  @override
  String get queueEditGcodeInjection => 'Inject auto-print G-code';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return 'No G-code snippet for $model — nothing will be injected.';
  }

  @override
  String get queueEditNoModel => 'Select a target model';

  @override
  String get queueEditNoPrinter => 'Select a printer';

  @override
  String get queueEditFilamentOverride => 'Filament Override';

  @override
  String get queueEditFilamentOverrideDesc =>
      'Optionally override filaments for model-based assignment. The scheduler matches against your selected filaments instead of the original 3MF values.';

  @override
  String get queueEditNoFilamentReqs =>
      'No filament requirements for this job.';

  @override
  String get queueEditOriginal => 'Original';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return 'Slot $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => 'Force color match';

  @override
  String get queueEditNozzleRack => 'Nozzle rack';

  @override
  String get queueEditNozzleRackDesc =>
      'Choose which rack nozzle each filament prints from. Left automatic, a fitting position is picked when the print starts.';

  @override
  String queueEditRackGroupLabel(String slots, String nozzle) {
    return 'Filament $slots · $nozzle';
  }

  @override
  String get queueEditRackAuto => 'Automatic';

  @override
  String queueEditRackPosition(int position, String nozzle) {
    return 'Position $position · $nozzle';
  }

  @override
  String queueEditRackPositionTaken(int position, String nozzle) {
    return 'Position $position · $nozzle — already chosen';
  }

  @override
  String queueEditRackPositionUnfit(int position, String nozzle) {
    return 'Position $position · $nozzle — does not fit';
  }

  @override
  String get queueEditRackEmpty => 'empty';

  @override
  String get queueEditRackPickStale =>
      'The chosen position no longer fits this filament — pick another, or the print is refused at start.';

  @override
  String queueEditRackNoFit(String nozzle) {
    return 'No rack position holds a $nozzle nozzle — fit one, or the printer decides for itself.';
  }

  @override
  String get nozzleFlowStandard => 'Standard';

  @override
  String get nozzleFlowHigh => 'High flow';

  @override
  String get bugReportMenu => 'Report a bug or an idea';

  @override
  String get bugReportTitle => 'Report a bug or an idea';

  @override
  String get bugReportIntroHeader => 'How it works';

  @override
  String get bugReportStepRecord => 'Start recording';

  @override
  String get bugReportStepReproduce => 'Reproduce the problem';

  @override
  String get bugReportStepFinish => 'Come back and finish';

  @override
  String get bugReportLogScreens => 'Screens you open and buttons you press';

  @override
  String get bugReportLogRequests => 'Requests to the server and its answers';

  @override
  String get bugReportLogService =>
      'The live view, and which notifications the background service posted or skipped';

  @override
  String get bugReportLogErrors =>
      'Errors and crashes, including the ones you never see';

  @override
  String get bugReportLogSetup =>
      'App and server version, your phone, your language';

  @override
  String get bugReportLogNoKey => 'Your API key or password';

  @override
  String get bugReportLogNoTyping => 'The text you type';

  @override
  String get bugReportLogNoAddress =>
      'Your server address — only http or https, name or IP, and the port';

  @override
  String get bugReportLogNoData =>
      'Printer serial numbers, or the names of your files, models and spools';

  @override
  String get bugReportReviewFirst =>
      'You read all of it before it leaves the phone.';

  @override
  String get bugReportPrivacyHeader => 'What ends up in the log';

  @override
  String get bugReportStart => 'Start recording';

  @override
  String get bugReportRecordingHeader => 'Recording';

  @override
  String get bugReportRecordingBody =>
      'Go back to the app and reproduce the problem. The recording bar stays with you — drag it aside or collapse it if it gets in the way, and use it to mark the moment it breaks and to finish.';

  @override
  String get bugReportMark => 'Mark the moment';

  @override
  String get bugReportMarked => 'Moment marked';

  @override
  String get bugReportStop => 'Finish recording';

  @override
  String get bugReportStopShort => 'Finish';

  @override
  String get bugReportBannerLabel => 'Recording';

  @override
  String get bugReportBarMove => 'Move the recording bar';

  @override
  String get bugReportBarCollapse => 'Collapse the recording bar';

  @override
  String get bugReportBarExpand => 'Expand the recording bar';

  @override
  String get bugReportReviewHeader => 'Review before sending';

  @override
  String get bugReportReviewBody =>
      'This is everything that was recorded. Read it through — below you choose whether it stays on the phone or goes out as a public issue.';

  @override
  String bugReportSummary(int records, int errors, int warnings) {
    return '$records records · $errors errors · $warnings warnings';
  }

  @override
  String bugReportMarkers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marked moments',
      one: '1 marked moment',
    );
    return '$_temp0';
  }

  @override
  String get bugReportTruncated =>
      'The session was long — the oldest records were dropped.';

  @override
  String get bugReportEmpty => 'Nothing was recorded.';

  @override
  String get bugReportShowRaw => 'Show raw log';

  @override
  String get bugReportHideRaw => 'Hide raw log';

  @override
  String bugReportRawClipped(int kb) {
    return 'The first $kb kB are not shown here. The file you save holds the whole session.';
  }

  @override
  String get bugReportSave => 'Save to a file';

  @override
  String get bugReportSaveShort => 'Save';

  @override
  String get bugReportSaved => 'Log saved to the file';

  @override
  String get bugReportSaveFailed => 'The log could not be saved.';

  @override
  String get bugReportDiscard => 'Discard';

  @override
  String get bugReportDiscardQuestion => 'Discard this recording?';

  @override
  String get bugReportDiscardBody => 'The log will be deleted from the phone.';

  @override
  String get bugReportDiscardBodyQueued =>
      'The log will be deleted from the phone and the queued report cancelled.';

  @override
  String bugReportLimit(int minutes) {
    return 'A recording stops by itself after $minutes minutes.';
  }

  @override
  String bugReportLimitReached(int minutes) {
    return 'Recording finished — the $minutes minute limit was reached.';
  }

  @override
  String bugReportSizeLimitReached(int megabytes) {
    return 'Recording finished — the log reached its $megabytes MB limit.';
  }

  @override
  String get bugReportShow => 'Show';

  @override
  String get bugReportRecoveredHeader => 'A recording survived a crash';

  @override
  String get bugReportRecoveredBody =>
      'The app closed while it was recording. What it had written down is still on the phone — look at it, or throw it away.';

  @override
  String get bugReportDestinationHeader => 'What happens to this log';

  @override
  String get bugReportDestinationFile => 'Save to a file';

  @override
  String get bugReportDestinationIssue => 'Report on GitHub';

  @override
  String get bugReportDestinationFileBody =>
      'The log is saved where you choose and stays on your phone. You decide whether to send it anywhere.';

  @override
  String get bugReportDestinationIssueBody =>
      'The log and your description are posted as a public issue on GitHub, where anyone can read them and they stay for good. Go through the log below first.';

  @override
  String get bugReportDescriptionLabel => 'What went wrong?';

  @override
  String get bugReportDescriptionHint =>
      'What were you doing, what did you expect, what happened instead.';

  @override
  String get bugReportDescriptionRequired =>
      'Say what went wrong — a log with no description is nearly unusable.';

  @override
  String get bugReportSend => 'Report';

  @override
  String get bugReportSending => 'Sending…';

  @override
  String bugReportSendWaiting(String clock) {
    return 'Sending in $clock';
  }

  @override
  String get bugReportSendWaitingBody =>
      'The relay spaces reports out. You can leave this screen — it goes on its own.';

  @override
  String get bugReportSent => 'Report sent';

  @override
  String get bugReportSentBody =>
      'Thank you. The issue is open and the log is attached to it.';

  @override
  String get bugReportOpenIssue => 'Open the issue';

  @override
  String get bugReportDone => 'Done';

  @override
  String get bugReportSendFailedNotYet =>
      'The relay is not accepting reports right now. Try again later, or save the log to a file.';

  @override
  String get bugReportSendFailedRefused =>
      'The relay refused this report. Save the log to a file and attach it yourself.';

  @override
  String get bugReportSendFailedDuplicate =>
      'This one has already been reported.';

  @override
  String get bugReportSendFailedUnreachable =>
      'Could not reach the relay. Check the connection, or save the log to a file.';

  @override
  String get bugReportSendFailedRejected =>
      'The relay rejected this report. Save the log to a file and attach it yourself.';

  @override
  String get bugReportSendFailedDemo =>
      'Demo mode does not publish reports. Save the log to a file instead.';

  @override
  String get bugReportKindQuestion => 'What are you reporting?';

  @override
  String get bugReportKindBug => 'Bug';

  @override
  String get bugReportKindChange => 'Change';

  @override
  String get bugReportKindFeature => 'Feature';

  @override
  String get bugReportChangeHeader => 'Request a change';

  @override
  String get bugReportChangeBody =>
      'Something works, but not the way it should.';

  @override
  String get bugReportChangeLabel => 'What should change?';

  @override
  String get bugReportChangeHint =>
      'What it does now, and what it should do instead.';

  @override
  String get bugReportFeatureHeader => 'Request a feature';

  @override
  String get bugReportFeatureBody => 'Something the app cannot do yet.';

  @override
  String get bugReportFeatureLabel => 'What is missing?';

  @override
  String get bugReportFeatureHint =>
      'What you want to do, and why the app does not let you.';

  @override
  String get bugReportRequestPrivacyHeader => 'What gets sent';

  @override
  String get bugReportRequestWhatYouWrite => 'What you write';

  @override
  String get bugReportRequestVersions => 'App and server version';

  @override
  String get bugReportRequestNoLog => 'No log, no recording';

  @override
  String get bugReportRequestNoData =>
      'Nothing about your printers or your phone';

  @override
  String get bugReportRequestPublic =>
      'It becomes a public issue on GitHub — anyone can read it, and it stays.';

  @override
  String get bugReportRequestRequired =>
      'Write what you are asking for — an empty request cannot be acted on.';

  @override
  String get bugReportRequestSentBody => 'Thank you. The issue is open.';

  @override
  String get bugReportCancelSend => 'Cancel sending';

  @override
  String get bugReportRequestFailedNotYet =>
      'The relay is not accepting reports right now. Try again later.';

  @override
  String get bugReportRequestFailedRefused =>
      'The relay refused this request. You can open the issue yourself on GitHub.';

  @override
  String get bugReportRequestFailedUnreachable =>
      'Could not reach the relay. Check the connection and try again.';

  @override
  String get bugReportRequestFailedDemo =>
      'Demo mode does not publish reports.';

  @override
  String get bugReportRequestNotPrepared =>
      'The app could not put the report together. Nothing was sent — try again.';

  @override
  String get usersTitle => 'Users';

  @override
  String get usersMenu => 'Users';

  @override
  String get usersEmpty => 'No accounts on this server.';

  @override
  String get usersYou => 'you';

  @override
  String get usersRoleAdmin => 'Admin';

  @override
  String get usersRoleUser => 'User';

  @override
  String get usersInactive => 'Inactive';

  @override
  String get usersEmailLabel => 'E-mail';

  @override
  String get usersEmailNone => 'none';

  @override
  String get usersGroupsLabel => 'Groups';

  @override
  String get usersNoGroups => 'none';

  @override
  String get usersPermissionsLabel => 'Permissions';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permissions',
      one: '1 permission',
      zero: 'none',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => 'not reported by the server';

  @override
  String get usersAuthSourceLabel => 'Sign-in';

  @override
  String get usersAuthSourceLocal => 'Local account';

  @override
  String get usersCreatedLabel => 'Created';

  @override
  String get usersOwnedTitle => 'CREATED BY THIS ACCOUNT';

  @override
  String get usersOwnedArchives => 'Prints';

  @override
  String get usersOwnedQueue => 'Queue';

  @override
  String get usersOwnedLibrary => 'Files';

  @override
  String get usersOwnedFailed => 'Could not read what this account owns.';

  @override
  String get usersCreate => 'Add account';

  @override
  String get usersCreateTitle => 'New account';

  @override
  String get usersEdit => 'Edit';

  @override
  String get usersEditTitle => 'Edit account';

  @override
  String get usersDelete => 'Delete';

  @override
  String get usersSave => 'Save';

  @override
  String get usersSaved => 'Account saved';

  @override
  String get usersSaveFailed => 'The account could not be saved.';

  @override
  String get usersDeleted => 'Account deleted';

  @override
  String get usersFieldUsername => 'Username';

  @override
  String get usersFieldEmail => 'E-mail (optional)';

  @override
  String get usersFieldEmailRequired => 'E-mail';

  @override
  String get usersFieldPassword => 'Password';

  @override
  String get usersFieldNewPassword => 'New password';

  @override
  String get usersFieldConfirmPassword => 'Repeat the password';

  @override
  String get usersFieldActive => 'Active';

  @override
  String get usersFieldGroups => 'Groups';

  @override
  String get usersGroupSystem => '(built-in)';

  @override
  String get usersFieldRequired => 'Fill this in';

  @override
  String get usersPasswordsDoNotMatch => 'The two passwords are different.';

  @override
  String get usersGroupsAdminHint =>
      'Membership of Administrators is what makes an account an admin.';

  @override
  String get usersActiveHint => 'An inactive account cannot sign in.';

  @override
  String get usersEmailAdvancedHint =>
      'This server mails the password, so it needs an address.';

  @override
  String get usersPasswordMailed =>
      'The server picks the password itself and mails it to this address. Nobody, including you, gets to see it.';

  @override
  String get usersNoSmtpWarning =>
      'No mail server is configured, so that message will not arrive — the account would be created with a password nobody knows.';

  @override
  String get usersLdapPasswordNote =>
      'This account signs in through the directory (LDAP). Its password lives there and cannot be set from here.';

  @override
  String get usersPasswordKeepHint =>
      'Leave empty to keep the current password.';

  @override
  String get usersPasswordRulesHint =>
      'At least 8 characters, with an upper and lower case letter, a digit and a symbol.';

  @override
  String get usersPasswordTooShort => 'At least 8 characters.';

  @override
  String get usersPasswordNoUppercase => 'Add an upper case letter.';

  @override
  String get usersPasswordNoLowercase => 'Add a lower case letter.';

  @override
  String get usersPasswordNoDigit => 'Add a digit.';

  @override
  String get usersPasswordNoSpecial => 'Add a symbol.';

  @override
  String usersDeleteTitle(String username) {
    return 'Delete $username?';
  }

  @override
  String get usersDeleteBody =>
      'The account, its API keys and its sign-in state are removed. This cannot be undone.';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This account created $count items',
      one: 'This account created 1 item',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => 'Delete them too';

  @override
  String get usersDeleteItemsTooHint =>
      'Their prints, queue items and files are deleted with the account.';

  @override
  String get usersDeleteItemsKeepHint =>
      'Their prints, queue items and files stay, with no owner.';

  @override
  String get usersDeleteConfirm => 'Delete';

  @override
  String get usersErrLastAdmin =>
      'This is the last admin — the server keeps one.';

  @override
  String get usersErrLastAdminDelete =>
      'The last admin cannot be deleted — the server would be left with nobody who can manage it.';

  @override
  String get usersErrLastAdminDeactivate =>
      'The last admin cannot be deactivated — the server would be left with nobody who can manage it.';

  @override
  String get usersErrLastAdminRole =>
      'The last admin cannot be demoted — the server would be left with nobody who can manage it.';

  @override
  String get usersErrSelfDelete =>
      'You cannot delete the account you are signed in with.';

  @override
  String get usersErrUsernameTaken => 'That username is taken.';

  @override
  String get usersErrEmailTaken => 'That e-mail is already on another account.';

  @override
  String get usersErrLdapPassword =>
      'The password of a directory (LDAP) account cannot be set here.';

  @override
  String get usersErrEmailRequired =>
      'This server needs an e-mail address for a new account.';

  @override
  String get usersErrPasswordRequired =>
      'This server needs a password for a new account.';

  @override
  String get usersErrGroupsInvalid =>
      'One of the groups no longer exists — reopen the form.';

  @override
  String get groupsTitle => 'Groups';

  @override
  String get groupsMenu => 'Groups';

  @override
  String get groupsEmpty => 'No groups on this server.';

  @override
  String get groupsNoDescription => 'No description';

  @override
  String get groupsSystemPill => 'Built-in';

  @override
  String get groupsSystemNote =>
      'A built-in group cannot be renamed and what it grants is fixed — only who is in it can change.';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'no accounts',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permissions',
      one: '1 permission',
      zero: 'no permissions',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => 'MEMBERS';

  @override
  String get groupsNoMembers => 'Nobody is in this group.';

  @override
  String get groupsAddMember => 'Add member';

  @override
  String groupsAddMemberTitle(String group) {
    return 'Add to $group';
  }

  @override
  String get groupsEveryoneIsIn => 'Every account is already in this group.';

  @override
  String get groupsRemoveMember => 'Remove';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return 'Remove $username from $group?';
  }

  @override
  String get groupsRemoveMemberBody =>
      'The account stays, and loses what this group granted it.';

  @override
  String get groupsCreate => 'New group';

  @override
  String get groupsCreateTitle => 'New group';

  @override
  String get groupsEditTitle => 'Edit group';

  @override
  String get groupsDelete => 'Delete group';

  @override
  String get groupsSaved => 'Group saved';

  @override
  String get groupsDeleted => 'Group deleted';

  @override
  String groupsDeleteQuestion(String group) {
    return 'Delete $group?';
  }

  @override
  String get groupsDeleteBody => 'The permissions it grants disappear with it.';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count accounts are in it and stay — they just lose what this group granted.',
      one:
          '1 account is in it and stays — it just loses what this group granted.',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => 'Name';

  @override
  String get groupsFieldDescription => 'What it is for';

  @override
  String get groupsSystemFormNote =>
      'A built-in group: its name and permissions are fixed by the server. Only the description can be changed here.';

  @override
  String get groupsPermissionsHeader => 'PERMISSIONS';

  @override
  String groupsPermissionsSelected(int count) {
    return '$count selected';
  }

  @override
  String get groupsAdvancedPermissions => 'Server administration';

  @override
  String get groupsAdvancedHint =>
      'Users, API keys, settings, backups — everything the app itself has no screen for.';

  @override
  String get adminMenu => 'Administration';

  @override
  String get adminTitle => 'Administration';

  @override
  String adminSignedInAs(String username) {
    return 'Signed in as $username';
  }

  @override
  String get adminUsersSubtitle =>
      'Who has an account, and what each of them may do';

  @override
  String get adminGroupsSubtitle => 'Permission sets and who holds them';

  @override
  String get adminApiKeysSubtitle =>
      'Credentials for everything that is not this app';

  @override
  String get apiKeysTitle => 'API keys';

  @override
  String get apiKeysEmpty => 'No keys have been issued.';

  @override
  String get apiKeysCreate => 'New key';

  @override
  String get apiKeysCreateTitle => 'New API key';

  @override
  String get apiKeysEditTitle => 'Edit key';

  @override
  String get apiKeysSaved => 'Key saved';

  @override
  String get apiKeysRevoke => 'Revoke';

  @override
  String get apiKeysRevoked => 'Key revoked';

  @override
  String apiKeysRevokeQuestion(String name) {
    return 'Revoke $name?';
  }

  @override
  String get apiKeysRevokeBody =>
      'Whatever uses this key stops working at once. This cannot be undone — a new key would have to be issued.';

  @override
  String apiKeysLastUsed(String date) {
    return 'last used $date';
  }

  @override
  String get apiKeysNeverUsed => 'never used';

  @override
  String get apiKeysDisabled => 'Switched off';

  @override
  String get apiKeysExpired => 'Expired';

  @override
  String apiKeysExpiresOn(String date) {
    return 'until $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count printers',
      one: '1 printer',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => 'No owner';

  @override
  String get apiKeysFieldName => 'Name';

  @override
  String get apiKeysFieldNameHint =>
      'What holds this key — \"Home Assistant\", \"SpoolBuddy\".';

  @override
  String get apiKeysFieldEnabled => 'Active';

  @override
  String get apiKeysFieldEnabledHint =>
      'Switching it off stops the key working without deleting it.';

  @override
  String get apiKeysScopesHeader => 'WHAT IT MAY DO';

  @override
  String get apiKeysScopesHint =>
      'A key can never manage accounts, groups, keys or settings — the server refuses those to every key.';

  @override
  String get apiKeysPrintersHeader => 'PRINTERS';

  @override
  String get apiKeysAllPrinters => 'All printers';

  @override
  String get apiKeysAllPrintersHint =>
      'Off: pick which printers this key may touch.';

  @override
  String get apiKeysExpiryHeader => 'EXPIRY';

  @override
  String get apiKeysNoExpiry => 'Does not expire';

  @override
  String get apiKeysExpiryHint =>
      'Tap to pick a date after which the key stops working.';

  @override
  String get apiKeysExpiryClear => 'No expiry';

  @override
  String get apiKeysCreatedTitle => 'Key created';

  @override
  String get apiKeysCreatedWarning =>
      'Copy it now. The server keeps only a hash — this is the last time it can be shown.';

  @override
  String get apiKeysCopy => 'Copy';

  @override
  String get apiKeysCopied => 'Key copied';

  @override
  String get apiKeysCreatedDone => 'Done';

  @override
  String get apiKeyScopeRead => 'Read status';

  @override
  String get apiKeyScopeReadHint =>
      'Printers, queue, archive, library, statistics — reading only.';

  @override
  String get apiKeyScopeQueue => 'Queue';

  @override
  String get apiKeyScopeControl => 'Control printers';

  @override
  String get apiKeyScopeControlHint =>
      'Pause, stop, temperatures, AMS, smart plugs.';

  @override
  String get apiKeyScopeLibrary => 'Files';

  @override
  String get apiKeyScopeInventory => 'Filaments';

  @override
  String get apiKeyScopeMaintenance => 'Maintenance';

  @override
  String get apiKeyScopeArchives => 'Archive';

  @override
  String get apiKeyScopeProjects => 'Projects';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint =>
      'Reads the cloud on behalf of the account that creates the key. Needs authentication switched on server-side.';

  @override
  String get apiKeyScopeEnergy => 'Energy price';

  @override
  String get apiKeyScopeEnergyHint =>
      'The one settings value a key may write — for a dynamic tariff.';

  @override
  String get printLogTitle => 'Print log';

  @override
  String get printLogSearchHint => 'Search runs';

  @override
  String get printLogEmpty => 'No runs recorded yet';

  @override
  String get printLogNoMatches => 'No runs match your filters';

  @override
  String get printLogLoadFailed => 'Could not load the print log';

  @override
  String get printLogFilters => 'Filters';

  @override
  String get printLogFilterPrinter => 'Printer';

  @override
  String get printLogFilterUser => 'User';

  @override
  String get printLogFilterStatus => 'Status';

  @override
  String get printLogFilterDates => 'Date range';

  @override
  String get printLogAnyPrinter => 'Any printer';

  @override
  String get printLogAnyUser => 'Anyone';

  @override
  String get printLogAnyStatus => 'Any status';

  @override
  String get printLogNoUser => 'No user';

  @override
  String get printLogOrphan => 'Archive deleted';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded of $total';
  }

  @override
  String get printLogLoadMore => 'Load more';

  @override
  String get printLogSort => 'Sort by';

  @override
  String get printLogSortDate => 'Date';

  @override
  String get printLogSortName => 'Name';

  @override
  String get printLogSortPrinter => 'Printer';

  @override
  String get printLogSortUser => 'User';

  @override
  String get printLogSortStatus => 'Status';

  @override
  String get printLogSortDuration => 'Duration';

  @override
  String get printLogSortFilament => 'Filament used';

  @override
  String get printLogSortCost => 'Cost';

  @override
  String get printLogSortEnergy => 'Energy';

  @override
  String get printLogSortDirection => 'Direction';

  @override
  String get printLogSortDescending => 'Descending';

  @override
  String get printLogSortAscending => 'Ascending';

  @override
  String get printLogStatusCompleted => 'Completed';

  @override
  String get printLogStatusFailed => 'Failed';

  @override
  String get printLogStatusStopped => 'Stopped';

  @override
  String get printLogStatusCancelled => 'Cancelled';

  @override
  String get printLogStatusSkipped => 'Skipped';

  @override
  String get printLogStatusAborted => 'Aborted';

  @override
  String printLogEnergy(String value) {
    return '$value kWh';
  }

  @override
  String get printLogClassifyTitle => 'Classify this run';

  @override
  String get printLogDetailStarted => 'Started';

  @override
  String get printLogDetailFinished => 'Finished';

  @override
  String get printLogDetailDuration => 'Duration';

  @override
  String get printLogDetailFilament => 'Filament';

  @override
  String get printLogDetailCost => 'Cost';

  @override
  String get printLogDetailEnergy => 'Energy';

  @override
  String get printLogFailureCause => 'Failure cause';

  @override
  String get printLogNoClassification => 'Not classified';

  @override
  String get printLogStatusLabel => 'Status';

  @override
  String get printLogCountsAsFailure =>
      'Counted as a failure — this run and its cause show up in failure analysis.';

  @override
  String get printLogNotCountedAsFailure =>
      'Not counted as a failure, so the cause stays out of failure analysis.';

  @override
  String printLogStatusOneWay(String status) {
    return 'This server cannot write “$status” back. Change it and it is gone for good.';
  }

  @override
  String get printLogSave => 'Save';

  @override
  String get printLogSaveFailed => 'Could not save the classification';

  @override
  String get printLogDelete => 'Delete run';

  @override
  String get printLogDeleteTitle => 'Delete this run?';

  @override
  String get printLogDeleteBody =>
      'It leaves the log, and its filament, cost and time leave the statistics. The archive it points at stays.';

  @override
  String get printLogDeleteFailed => 'Could not delete the run';

  @override
  String get printLogClear => 'Clear print log';

  @override
  String get printLogClearTitle => 'Clear the whole print log?';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count runs go',
      one: 'The one run in the log goes',
    );
    return '$_temp0 — everyone\'s, not only yours — and their filament, cost and time leave the statistics. Archives and the queue are untouched. This cannot be undone.';
  }

  @override
  String get printLogClearBodyFiltered =>
      'Every run in the log goes — everyone\'s, not only yours, and the filter you have on does not narrow it — and their filament, cost and time leave the statistics. Archives and the queue are untouched. This cannot be undone.';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs deleted',
      one: '$count run deleted',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed => 'Could not clear the print log';

  @override
  String get failureReasonAdhesion => 'Adhesion failure';

  @override
  String get failureReasonSpaghetti => 'Spaghetti / detached print';

  @override
  String get failureReasonLayerShift => 'Layer shift';

  @override
  String get failureReasonCloggedNozzle => 'Clogged nozzle';

  @override
  String get failureReasonFilamentRunout => 'Filament runout';

  @override
  String get failureReasonWarping => 'Warping';

  @override
  String get failureReasonStringing => 'Stringing';

  @override
  String get failureReasonUnderExtrusion => 'Under-extrusion';

  @override
  String get failureReasonPowerFailure => 'Power failure';

  @override
  String get failureReasonUserCancelled => 'Cancelled by the user';

  @override
  String get failureReasonOther => 'Other';

  @override
  String get failureReasonUnknown => 'Unknown';
}
