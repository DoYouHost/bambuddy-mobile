// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get printersTitle => 'Drucker';

  @override
  String get changeServer => 'Server wechseln';

  @override
  String get sessionExpired => 'Sitzung abgelaufen — erneut anmelden';

  @override
  String get signInRequiredTitle => 'Erneut anmelden';

  @override
  String get signInRequiredBody =>
      'Der Server hat dein gespeichertes Passwort abgelehnt, daher hat die App weitere Versuche eingestellt — wiederholte Versuche können das Konto sperren. Melde dich erneut an und verwende ein neues Passwort, falls es geändert wurde.';

  @override
  String get signInRequiredAction => 'Anmelden';

  @override
  String get signInRequiredTwoFactorBody =>
      'Dein Konto erfordert jetzt einen zweiten Faktor, den die App im Hintergrund nicht bereitstellen kann — daher wurde die automatische Anmeldung beendet. Melde dich erneut an und gib den Code ein.';

  @override
  String get later => 'Später';

  @override
  String get serverUnreachableStale =>
      'Server nicht erreichbar — Daten sind möglicherweise veraltet';

  @override
  String get wsReconnecting =>
      'Keine Live-Verbindung — Aktualisierung alle 5 s';

  @override
  String get connLive => 'Live';

  @override
  String get connLiveTooltip => 'Echtzeit-Aktualisierungen über WebSocket';

  @override
  String get connPolling => 'Polling';

  @override
  String get connPollingTooltip =>
      'Keine Live-Verbindung — Aktualisierung alle 5 s (REST)';

  @override
  String get connectFailed => 'Verbindung zum Server fehlgeschlagen';

  @override
  String get filePickerFailed => 'Der Dateidialog konnte nicht geöffnet werden';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get back => 'Zurück';

  @override
  String get searchPrinters => 'Drucker suchen…';

  @override
  String get noPrinters => 'Keine Drucker — auf dem Server hinzufügen';

  @override
  String noSearchResults(String query) {
    return 'Keine Ergebnisse für „$query“';
  }

  @override
  String get noPrintersMatchFilters =>
      'Keine Drucker entsprechen den aktuellen Filtern';

  @override
  String get dashboardFilters => 'Filter';

  @override
  String get filterStatus => 'Status';

  @override
  String get filtersClear => 'Zurücksetzen';

  @override
  String get hideOffline => 'Offline ausblenden';

  @override
  String get statusAll => 'Alle';

  @override
  String get statusPrinting => 'Druckt';

  @override
  String get statusIdle => 'Bereit';

  @override
  String get statusPaused => 'Pausiert';

  @override
  String get statusFinished => 'Abgeschlossen';

  @override
  String get statusErrorFilter => 'Fehler';

  @override
  String get statusOfflineFilter => 'Offline';

  @override
  String get addPrinterTitle => 'Drucker hinzufügen';

  @override
  String get addPrinterName => 'Name';

  @override
  String get addPrinterIp => 'IP-Adresse';

  @override
  String get addPrinterSerial => 'Seriennummer';

  @override
  String get addPrinterAccessCode => 'Zugriffscode';

  @override
  String get addPrinterModel => 'Modell';

  @override
  String get addPrinterModelOptional => 'Optional';

  @override
  String get addPrinterModelNone => 'Nicht festgelegt';

  @override
  String get addPrinterLocation => 'Standort';

  @override
  String get addPrinterLocationOptional => 'Optional';

  @override
  String get addPrinterSubmit => 'Drucker hinzufügen';

  @override
  String get addPrinterConnectionNote =>
      'Der Server überprüft die Verbindung vor dem Speichern. Bei falscher IP-Adresse oder falschem Zugriffscode wird ein Fehler gemeldet und nichts erstellt.';

  @override
  String get addPrinterRequiredField => 'Erforderlich';

  @override
  String get addPrinterSuccess => 'Drucker hinzugefügt';

  @override
  String get addPrinterErrConnection =>
      'Verbindung zum Drucker fehlgeschlagen. Überprüfe die IP-Adresse, Seriennummer und den Zugriffscode und stelle sicher, dass der LAN-Modus aktiviert ist.';

  @override
  String get addPrinterErrDuplicate =>
      'Ein Drucker mit dieser Seriennummer existiert bereits';

  @override
  String get addPrinterErrForbidden =>
      'Du hast keine Berechtigung, Drucker hinzuzufügen';

  @override
  String get addPrinterErrGeneric =>
      'Drucker konnte nicht hinzugefügt werden. Bitte erneut versuchen.';

  @override
  String get addPrinterAutoArchive =>
      'Abgeschlossene Drucke automatisch archivieren';

  @override
  String get addPrinterScanTitle => 'Drucker im Netzwerk suchen';

  @override
  String get addPrinterSubnet => 'Zu scannendes Subnetz';

  @override
  String get addPrinterScanButton => 'Subnetz nach Druckern scannen';

  @override
  String get addPrinterDiscoverNetwork => 'Drucker im Netzwerk erkennen';

  @override
  String addPrinterScanning(int scanned, int total) {
    return 'Scannen… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => 'Scannen…';

  @override
  String get addPrinterScanNoResults => 'Keine Drucker gefunden';

  @override
  String get addPrinterScanError =>
      'Scan fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get addPrinterSubnetCustomOption => 'Benutzerdefiniertes Subnetz…';

  @override
  String get addPrinterSubnetCustomLabel =>
      'Benutzerdefiniertes Subnetz (CIDR)';

  @override
  String get addPrinterSubnetDockerNote =>
      'Docker erkannt. Gib das Subnetz deines Druckers in CIDR-Notation ein. Erfordert network_mode: host in docker-compose.yml.';

  @override
  String get addPrinterSubnetCustomNote =>
      'Verwende ein benutzerdefiniertes Subnetz, wenn sich der Drucker in einem anderen Netzwerk als der Server befindet. Die FTP- (990) und MQTT-Ports (8883) müssen über das Routing erreichbar sein.';

  @override
  String get addPrinterDiagnostic => 'Diagnose ausführen';

  @override
  String get addPrinterDiagnosticRunning => 'Diagnose läuft…';

  @override
  String get addPrinterDiagnosticError =>
      'Diagnose fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get diagOverallOk => 'Alle Prüfungen bestanden';

  @override
  String get diagOverallWarnings => 'Mit Warnungen abgeschlossen';

  @override
  String get diagOverallProblems => 'Probleme gefunden';

  @override
  String get diagCheckPortMqtt => 'MQTT-Port (8883)';

  @override
  String get diagCheckPortFtps => 'FTPS-Port (990)';

  @override
  String get diagCheckPortRtsps => 'Kamera-Port (322)';

  @override
  String get diagCheckNetworkMode => 'Netzwerkmodus';

  @override
  String get diagCheckSubnet => 'Subnetz-Erreichbarkeit';

  @override
  String get diagCheckMqttAuth => 'MQTT-Zugangsdaten';

  @override
  String get diagCheckDeveloperMode => 'Entwickler- / LAN-Modus';

  @override
  String get changeServerQuestion => 'Server wechseln?';

  @override
  String get changeServerWarning =>
      'Das gespeicherte Profil und die Zugangsdaten werden entfernt.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get clear => 'Löschen';

  @override
  String get change => 'Ändern';

  @override
  String get noActivePrints => 'Keine aktiven Drucke';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count drucken',
      one: '$count druckt',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => 'Als Nächstes verfügbar: ';

  @override
  String get tempNozzle => 'Düse';

  @override
  String get tempBed => 'Druckbett';

  @override
  String get tempChamber => 'Kammer';

  @override
  String tempNozzleNumbered(String n) {
    return 'Düse $n';
  }

  @override
  String get ctrlFanPart => 'Bauteillüfter';

  @override
  String get ctrlFanAux => 'Zusatzlüfter';

  @override
  String get ctrlFanAux2 => 'Linker Zusatzlüfter';

  @override
  String get ctrlFanChamber => 'Kammerlüfter';

  @override
  String get ctrlFanExhaust => 'Abluftlüfter';

  @override
  String get ctrlFanPartShort => 'Bauteil';

  @override
  String get ctrlFanAuxShort => 'Zusatz';

  @override
  String get ctrlFanAux2Short => 'Zusatz L';

  @override
  String get ctrlFanChamberShort => 'Kammer';

  @override
  String get ctrlFanExhaustShort => 'Abluft';

  @override
  String get ctrlSpeed => 'Geschwindigkeit';

  @override
  String get ctrlLight => 'Kammerbeleuchtung';

  @override
  String get ctrlLightOn => 'Ein';

  @override
  String get ctrlLightOff => 'Aus';

  @override
  String get ctrlAirduct => 'Luftkanal';

  @override
  String get ctrlAirductCooling => 'Kühlen';

  @override
  String get ctrlAirductHeating => 'Heizen';

  @override
  String get ctrlOff => 'Aus';

  @override
  String get ctrlSet => 'Einstellen';

  @override
  String get ctrlActivate => 'Aktivieren';

  @override
  String get ctrlNozzleActive => 'Aktiv';

  @override
  String get ctrlDry => 'Trocknen';

  @override
  String get ctrlDrying => 'Trocknung läuft';

  @override
  String get ctrlDryStart => 'Starten';

  @override
  String get ctrlDryFilament => 'Filament';

  @override
  String get ctrlDryTemp => 'Temperatur';

  @override
  String get ctrlDryDuration => 'Dauer';

  @override
  String ctrlDryHours(int h) {
    return '$h h';
  }

  @override
  String get ctrlDryAutoIdle =>
      'Automatisches Trocknen bei hoher Luftfeuchtigkeit.';

  @override
  String get ctrlDryAutoQueue =>
      'Automatisches Trocknen zwischen Druckaufträgen.';

  @override
  String get ctrlDryAutoWhilePrinting => 'Auch während des Druckens.';

  @override
  String get ctrlDryStartWhen => 'Startzeit';

  @override
  String get ctrlDryStartNow => 'Jetzt';

  @override
  String get ctrlDryStartAfter => 'Später';

  @override
  String get ctrlDryStartAt => 'Zur Uhrzeit';

  @override
  String get ctrlDryPickTime => 'Uhrzeit auswählen';

  @override
  String get ctrlDrySchedule => 'Planen';

  @override
  String get ctrlDryScheduled => 'Trocknen geplant';

  @override
  String get ctrlDryScheduleTimePast => 'Wähle eine Zeit in der Zukunft';

  @override
  String ctrlDryScheduledFor(String time) {
    return 'Trocknen um $time';
  }

  @override
  String get ctrlDryScheduledAsap => 'Trocknen geplant, wartet auf den Drucker';

  @override
  String get ctrlDryScheduleCancel => 'Geplantes Trocknen abbrechen';

  @override
  String get ctrlDryScheduleDismiss => 'Verwerfen';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return 'Geplantes Trocknen fehlgeschlagen: $reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => 'unbekannter Fehler';

  @override
  String get ctrlDryWaitPower => 'AMS-Netzteil anschließen';

  @override
  String get ctrlDryWaitRetract => 'Filament am AMS-Ausgang zurückziehen';

  @override
  String get ctrlDryWaitBlocked =>
      'Das AMS kann den Trocknungsvorgang derzeit nicht starten';

  @override
  String get ctrlDryWaitAmsNotFound => 'Warten auf Erkennung des AMS';

  @override
  String get ctrlDryWaitOffline => 'Warten, bis der Drucker online ist';

  @override
  String get ctrlDryWaitBusy => 'Warten, bis der Drucker frei ist';

  @override
  String get ctrlDryWaitAlreadyDrying =>
      'Warten auf Abschluss des aktuellen Zyklus';

  @override
  String get ctrlDryWaitInterrupted =>
      'Unterbrochen, wird neu gestartet, sobald der Drucker frei ist';

  @override
  String get ctrlMove => 'Bewegen';

  @override
  String get ctrlMoveHome => 'Alle Achsen referenzieren';

  @override
  String get ctrlMoveHomeStarted => 'Referenzfahrt gestartet';

  @override
  String get ctrlMoveStep => 'Schritt';

  @override
  String get ctrlMoveZ => 'Z (Bettabstand)';

  @override
  String get ctrlMoveZUp => 'Hoch';

  @override
  String get ctrlMoveZDown => 'Runter';

  @override
  String get ctrlMoveExtruder => 'Extruder';

  @override
  String get ctrlMoveExtrude => 'Extrudieren';

  @override
  String get ctrlMoveRetract => 'Einziehen';

  @override
  String get ctrlMoveLength => 'Länge';

  @override
  String ctrlMoveMm(int d) {
    return '$d mm';
  }

  @override
  String get ctrlPause => 'Pause';

  @override
  String get ctrlResume => 'Fortsetzen';

  @override
  String get ctrlStop => 'Stoppen';

  @override
  String get ctrlStopConfirmTitle => 'Druck stoppen?';

  @override
  String get ctrlStopConfirmBody =>
      'Dies bricht den aktuellen Druck ab. Er kann nicht fortgesetzt werden.';

  @override
  String get ctrlForbidden =>
      'Keine Berechtigung zur Steuerung dieses Druckers';

  @override
  String get ctrlFailed => 'Befehl konnte nicht gesendet werden';

  @override
  String get skipObjectsTitle => 'Objekte überspringen';

  @override
  String get skipObjectsSkip => 'Überspringen';

  @override
  String get skipObjectsSkippedTag => 'Übersprungen';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte übersprungen',
      one: '„$names“ übersprungen',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte überspringen?',
      one: 'Dieses Objekt überspringen?',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '„$names“ werden für den Rest dieses Drucks übersprungen. Dies kann nicht rückgängig gemacht werden.',
      one:
          '„$names“ wird für den Rest dieses Drucks übersprungen. Dies kann nicht rückgängig gemacht werden.',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get skipObjectsSelectHint =>
      'Tippe oben oder unten auf ein Objekt, um es zum Überspringen auszuwählen';

  @override
  String get skipObjectsMatchInfo => 'IDs mit dem Druckerdisplay abgleichen';

  @override
  String get skipObjectsMatchHint =>
      'Das Druckerdisplay zeigt Objekt-IDs auf der Druckplatte';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '$skipped/$total übersprungen';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count aktiv';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return 'Überspringen ist ab Schicht 2 verfügbar (aktuell Schicht $layer)';
  }

  @override
  String get skipObjectsEmpty => 'Keine druckbaren Objekte';

  @override
  String get skipObjectsEmptyHint =>
      'Objekte werden beim Druckstart geladen. Neu laden, wenn ein Druck läuft.';

  @override
  String get skipObjectsReload => 'Neu laden';

  @override
  String get skipObjectsLoadFailed =>
      'Druckbare Objekte konnten nicht geladen werden.';

  @override
  String get speedSilent => 'Leise';

  @override
  String get speedStandard => 'Standard';

  @override
  String get speedSport => 'Sport';

  @override
  String get speedLudicrous => 'Verrückt';

  @override
  String get smartPlugOn => 'Ein';

  @override
  String get smartPlugOff => 'Aus';

  @override
  String get smartPlugUnreachable => 'Nicht erreichbar';

  @override
  String get smartPlugMonitorOnly => 'Nur Überwachung';

  @override
  String get smartPlugCantPowerOff =>
      'Strom kann nicht abgeschaltet werden, während der Drucker druckt';

  @override
  String get smartPlugOffConfirmTitle => 'Strom abschalten?';

  @override
  String get smartPlugOffConfirmBody => 'Der Drucker wird sofort stromlos.';

  @override
  String get smartPlugTurnOff => 'Ausschalten';

  @override
  String get smartPlugOnConfirmTitle => 'Einschalten?';

  @override
  String get smartPlugOnConfirmBody => 'Der Drucker wird eingeschaltet.';

  @override
  String get smartPlugTurnOn => 'Einschalten';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => 'Gesamte Leistungsaufnahme aller Steckdosen';

  @override
  String get queueEmpty => 'Die Warteschlange ist leer';

  @override
  String get queueAmsFromSlicer => 'AMS aus Slicer';

  @override
  String queueAnyOfModels(String models) {
    return 'Eines von: $models';
  }

  @override
  String get queueDeleteTitle => 'Aus Warteschlange entfernen?';

  @override
  String get queueDeleteBody =>
      'Dies entfernt den Eintrag aus der Druck-Warteschlange.';

  @override
  String get queueDeleteConfirm => 'Entfernen';

  @override
  String get queueStart => 'Jetzt starten';

  @override
  String get queueStartNext => 'Als Nächstes starten';

  @override
  String get queueCancel => 'Abbrechen';

  @override
  String get queueStop => 'Druck stoppen';

  @override
  String get queueStopTitle => 'Diesen Druck abbrechen?';

  @override
  String get queueStopBody =>
      'Der Drucker stoppt den Druckvorgang und der Eintrag wird aus der Warteschlange entfernt. Was bisher gedruckt wurde, kann nicht fortgesetzt werden.';

  @override
  String get queueStopConfirm => 'Druck stoppen';

  @override
  String get queueRemove => 'Aus Warteschlange entfernen';

  @override
  String get queueRemoveStoppedTitle => 'Aus Warteschlange entfernen?';

  @override
  String get queueRemoveStoppedBody =>
      'Der Drucker zeigt diesen Druck nicht als aktiv an. Durch das Entfernen wird der Eintrag aus der Warteschlange gelöscht.';

  @override
  String get queueStopped => 'Druck gestoppt';

  @override
  String get queueRemoved => 'Aus Warteschlange entfernt';

  @override
  String get queueRemovalStatusChanged =>
      'Dieser Eintrag befindet sich nicht mehr im angezeigten Status. Aktualisiere die Warteschlange und versuche es erneut.';

  @override
  String get queueNoFreePrinters => 'Derzeit keine freien Drucker verfügbar';

  @override
  String get queuePrintStarted => 'Druck gestartet';

  @override
  String get queueStatusPending => 'Wartend';

  @override
  String get queueStatusScheduled => 'Geplant';

  @override
  String get queueStatusPrinting => 'Druckt';

  @override
  String get queueStatusPaused => 'Pausiert';

  @override
  String get archiveSearchHint => 'Archiv durchsuchen';

  @override
  String get archiveEmpty => 'Keine archivierten Drucke';

  @override
  String archiveSearchFailed(String query) {
    return 'Suche nach „$query“ fehlgeschlagen. Versuche einen anderen Suchbegriff.';
  }

  @override
  String get archiveNoMatches => 'Keine Drucke entsprechen deinen Filtern';

  @override
  String get archiveFilters => 'Filter';

  @override
  String get archiveFiltersClear => 'Filter zurücksetzen';

  @override
  String get archiveSortLabel => 'Sortieren nach';

  @override
  String get archiveSortDateDesc => 'Neueste zuerst';

  @override
  String get archiveSortDateAsc => 'Älteste zuerst';

  @override
  String get archiveSortNameAsc => 'Name A–Z';

  @override
  String get archiveSortNameDesc => 'Name Z–A';

  @override
  String get archiveSortSizeDesc => 'Größte zuerst';

  @override
  String get archiveSortSizeAsc => 'Kleinste zuerst';

  @override
  String get archiveFilterFileType => 'Dateien';

  @override
  String get archiveFileTypeAll => 'Alle Dateien';

  @override
  String get archiveFileTypeGcode => 'Geslict';

  @override
  String get archiveFileTypeSource => 'Quelle';

  @override
  String get archiveFilterFlags => 'Anzeigen';

  @override
  String get archiveFilterFavorites => 'Favoriten';

  @override
  String get archiveFilterHideFailed => 'Fehlgeschlagene ausblenden';

  @override
  String get archiveFilterHideDuplicates => 'Duplikate ausblenden';

  @override
  String get archiveFilterPrinter => 'Drucker';

  @override
  String get archiveFilterMaterial => 'Material';

  @override
  String get archiveFilterColors => 'Farben';

  @override
  String get archiveColorModeAny => 'Beliebig';

  @override
  String get archiveColorModeAll => 'Alle';

  @override
  String get archiveFavorite => 'Zu Favoriten hinzufügen';

  @override
  String get archiveUnfavorite => 'Aus Favoriten entfernen';

  @override
  String get archiveFavoriteFailed =>
      'Favorit konnte nicht aktualisiert werden';

  @override
  String get archiveReprint => 'Erneut drucken';

  @override
  String get archiveAddToQueue => 'Zur Warteschlange hinzufügen';

  @override
  String get archiveTimelapse => 'Zeitraffer ansehen';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fotos ansehen ($count)',
      one: 'Foto ansehen',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaAction => 'Aufnahmen & Fotos';

  @override
  String get archiveMediaOnServer => 'Auf dem Server';

  @override
  String archiveMediaOnPrinter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Auf dem Drucker ($count)',
      zero: 'Auf dem Drucker',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSearching => 'Suche auf dem Drucker…';

  @override
  String get archiveMediaNothingOnPrinter => 'Nichts auf dem Drucker';

  @override
  String archiveMediaPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos',
      one: 'ein Foto',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaKindTimelapse => 'Zeitraffer';

  @override
  String get archiveMediaKindIpcam => 'Kamera';

  @override
  String archiveMediaDownloadSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien herunterladen',
      one: 'Eine Datei herunterladen',
      zero: 'Ausgewählte herunterladen',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSaved => 'Video gespeichert';

  @override
  String get archiveMediaNoFilePermission =>
      'Keine Berechtigung für die Dateien des Druckers';

  @override
  String get archiveMediaPrinterMissing => 'Drucker nicht mehr vorhanden';

  @override
  String get archiveMediaTimelapseUnavailable =>
      'Zeitraffer: Keine Antwort vom Drucker';

  @override
  String get archiveMediaIpcamUnavailable =>
      'Kamera: Keine Antwort vom Drucker';

  @override
  String archivePlate(int plate) {
    return 'Druckplatte $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return 'Druckplatte $plate einer Datei mit mehreren Platten';
  }

  @override
  String get archivePhotosTitle => 'Fotos';

  @override
  String get archivePhotosEmpty => 'Keine Fotos für diesen Druckauftrag';

  @override
  String get archivePhotoFailed => 'Dieses Foto konnte nicht geladen werden.';

  @override
  String get archiveFilamentUsed => 'Verbrauchtes Filament';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$grams in $count Durchläufen verbraucht',
      one: '$grams verbraucht',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => 'Kein Verbrauch aufgezeichnet';

  @override
  String get archiveFilamentSaving => 'Wird gespeichert';

  @override
  String get archiveFilamentNone => 'Nicht erfasst';

  @override
  String get archiveFilamentLabel => 'Gewicht (g)';

  @override
  String get archiveFilamentNotANumber =>
      'Gib eine Zahl ein oder lass das Feld leer, um das Gewicht zu löschen.';

  @override
  String archiveFilamentOutOfRange(String max) {
    return 'Ein Gewicht zwischen 0 und $max g.';
  }

  @override
  String get archiveFilamentSaved => 'Filamentgewicht gespeichert';

  @override
  String get archiveFilamentUnsupported =>
      'Dieser Server speichert noch kein manuell eingegebenes Filamentgewicht. Aktualisiere bambuddy.';

  @override
  String get archiveHasTimelapse => 'Hat einen Zeitraffer';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hat $count Fotos',
      one: 'Hat ein Foto',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => 'Zeitraffer';

  @override
  String get timelapseError =>
      'Dieser Zeitraffer konnte nicht abgespielt werden.';

  @override
  String timelapseHttpError(int status) {
    return 'Der Server hat diesen Zeitraffer nicht bereitgestellt ($status).';
  }

  @override
  String get timelapseStalled =>
      'Der Server liefert das Video, aber der Player hat die Wiedergabe nicht gestartet.';

  @override
  String get timelapsePlay => 'Abspielen';

  @override
  String get timelapsePause => 'Pause';

  @override
  String get timelapseSave => 'In Galerie speichern';

  @override
  String get timelapseShare => 'Teilen';

  @override
  String get timelapseSaved => 'In der Galerie gespeichert';

  @override
  String get timelapseSaveFailed => 'Das Video konnte nicht gespeichert werden';

  @override
  String get timelapseSaveDenied =>
      'Bambuddy benötigt unter dieser Android-Version die Berechtigung, in die Galerie zu schreiben.';

  @override
  String get timelapseEdit => 'Bearbeiten';

  @override
  String get timelapseEditSave => 'Speichern';

  @override
  String get timelapseEditTitle => 'Zeitraffer bearbeiten';

  @override
  String get timelapseEditTrim => 'Kürzen';

  @override
  String get timelapseEditSpeed => 'Geschwindigkeit';

  @override
  String timelapseEditOutput(String length) {
    return 'Ergebnis: $length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return 'Original: $length bei $width×$height';
  }

  @override
  String get timelapseEditSaveTitle => 'Aufnahme überschreiben?';

  @override
  String get timelapseEditSaveMessage =>
      'Der Server kodiert den Zeitraffer neu und ersetzt das Original. Es gibt keine Kopie, zu der du zurückkehren kannst.';

  @override
  String get timelapseEditProcessing =>
      'Der Server kodiert das Video neu. Auf schwächerer Hardware dauert dies einige Minuten – das Verlassen dieses Bildschirms bricht den Vorgang nicht ab.';

  @override
  String get timelapseEdited => 'Zeitraffer aktualisiert';

  @override
  String get gcodeViewerTitle => 'G-Code-Vorschau';

  @override
  String get gcodeViewerOpen => 'G-Code-Vorschau';

  @override
  String get gcodeViewerError =>
      'Die G-Code-Vorschau konnte nicht geladen werden.';

  @override
  String get gcodeViewerLoading => 'G-Code wird heruntergeladen…';

  @override
  String get gcodeViewerParsing => 'Werkzeugpfad wird gelesen…';

  @override
  String get gcodeViewerTravels => 'Leerfahrten';

  @override
  String get gcodeViewerColorByFilament => 'Filament';

  @override
  String get gcodeViewerColorByFeature => 'Linientyp';

  @override
  String get gcodeViewerColorByHeight => 'Höhe';

  @override
  String get gcodeViewerColorByWidth => 'Breite';

  @override
  String get gcodeSingleLayer => 'Einzelschicht';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return 'Filament $n';
  }

  @override
  String get gcodeViewerEmpty =>
      'In dieser Datei ist kein Werkzeugpfad vorhanden – sie wurde noch nicht geslict.';

  @override
  String gcodeViewerHttpError(int status) {
    return 'Der Server hat den G-Code für diese Datei nicht bereitgestellt ($status).';
  }

  @override
  String get gcodeFeatureWall => 'Wände';

  @override
  String get gcodeFeatureSparseInfill => 'Füllung';

  @override
  String get gcodeFeatureSolidInfill => 'Massive Füllung';

  @override
  String get gcodeFeatureSkirt => 'Skirt / Brim';

  @override
  String get gcodeFeatureSupport => 'Stützstruktur';

  @override
  String get gcodeFeatureGapFill => 'Lückenfüllung';

  @override
  String get gcodeFeatureBridge => 'Brücke / Überhang';

  @override
  String get gcodeFeatureIroning => 'Glätten';

  @override
  String get gcodeFeaturePrimeTower => 'Reinigungsturm';

  @override
  String get archiveNo3mfTitle =>
      'Einige der letzten Druckaufträge wurden ohne Vorschaubild archiviert';

  @override
  String get archiveNo3mfBody =>
      'Der Slicer hat die Datei .gcode.3mf nicht auf der Speicherkarte des Druckers abgelegt, daher konnte Bambuddy weder das Vorschaubild noch die Slicer-Metadaten abrufen. Meist ist im Slicer auf dem Tab „Device“ die Einstellung „Store sent files on external storage“ deaktiviert.';

  @override
  String get archiveNo3mfTitleInternal =>
      'Einige der letzten Druckaufträge verblieben im internen Speicher des Druckers';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio hat die geslicte Datei im internen Speicher des Druckers statt auf der Speicherkarte abgelegt, sodass über FTP nichts gelesen werden konnte. Bei der H2-Serie und beim P2S macht die Schaltfläche „Drucken“ dies immer – das Aktivieren der Slicer-Einstellung ändert daran nichts. Diese Druckaufträge werden trotzdem mit Name und Druckdauer archiviert, nur ohne Vorschaubild oder Slicer-Metadaten. Für vollständige Archive starte den Druck über Bambuddy oder slice in OrcaSlicer – in beiden Fällen mit einer Speicherkarte oder einem USB-Stick im Drucker.';

  @override
  String get archiveNo3mfTitleNoStorage =>
      'Einige der letzten Druckaufträge konnten nicht archiviert werden – kein Speicher im Drucker';

  @override
  String get archiveNo3mfBodyNoStorage =>
      'Der Drucker meldet, dass keine Speicherkarte oder kein USB-Stick eingesteckt ist. Die geslicte Datei konnte daher nirgends gespeichert werden und Bambuddy konnte nichts auslesen. Stecke ein Speichermedium ein, damit der nächste Druckauftrag vollständig archiviert wird.';

  @override
  String get archiveNo3mfDocs => 'Siehe Installationsschritt 4';

  @override
  String get archiveNo3mfDocsWhy => 'Warum das passiert';

  @override
  String get archiveNo3mfDismiss => 'Diesen Hinweis schließen';

  @override
  String get archiveNotSliceable =>
      'Dieser Druckauftrag hat keine Quelldatei und kein Modell, daher kann er nicht erneut geslict werden.';

  @override
  String get archiveDelete => 'Löschen';

  @override
  String get archiveDeleteTitle => 'Druckauftrag löschen?';

  @override
  String archiveDeleteBody(String name) {
    return '„$name“ aus dem Archiv entfernen.';
  }

  @override
  String get archiveDeletePurgeStats => 'Auch aus den Statistiken entfernen';

  @override
  String get archiveDeletePurgeStatsHint =>
      'Andernfalls bleibt der Druckauftrag in den Gesamtstatistiken erhalten.';

  @override
  String get archiveDeleted => 'Druckauftrag gelöscht';

  @override
  String get archiveDeleteFailed => 'Druckauftrag konnte nicht gelöscht werden';

  @override
  String get archiveSelectAll => 'Alle auswählen';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: '1 ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Druckaufträge löschen?',
      one: '1 Druckauftrag löschen?',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody =>
      'Die ausgewählten Druckaufträge aus dem Archiv entfernen.';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Druckaufträge gelöscht',
      one: '1 Druckauftrag gelöscht',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return '$ok gelöscht, $failed fehlgeschlagen';
  }

  @override
  String get archivePurgeOlder => 'Alte Druckaufträge bereinigen…';

  @override
  String get archivePurgeTitle => 'Alte Druckaufträge bereinigen';

  @override
  String get archivePurgeOlderThan => 'Älter als';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Druckaufträge · $size',
      one: '1 Druckauftrag · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing =>
      'Keine Druckaufträge älter als dieser Zeitraum.';

  @override
  String get archivePurgePreviewError =>
      'Vorschau konnte nicht geladen werden.';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Druckaufträge bereinigt',
      one: '1 Druckauftrag bereinigt',
      zero: 'Keine Druckaufträge bereinigt',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => 'Drucker auswählen';

  @override
  String get noPrintersAvailable => 'Keine Drucker verfügbar';

  @override
  String get detailsShow => 'Details';

  @override
  String get detailsHide => 'Details ausblenden';

  @override
  String get cameraTooltip => 'Kamera';

  @override
  String get cameraConnecting => 'Verbindung zur Kamera wird hergestellt…';

  @override
  String get cameraError => 'Kamerastream konnte nicht geladen werden';

  @override
  String get cameraDemoUnavailable =>
      'Kameravorschau ist im Demo-Modus nicht verfügbar';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'Externe Spule';

  @override
  String get traySlotEmpty => 'Leer';

  @override
  String get amsSlotFilament => 'Filament';

  @override
  String get amsLoad => 'Laden';

  @override
  String get amsUnload => 'Entladen';

  @override
  String get amsRfidReread => 'Tag neu einlesen';

  @override
  String get amsLoadStarted => 'Filament wird geladen…';

  @override
  String get amsUnloadStarted => 'Filament wird entladen…';

  @override
  String get amsRfidRereadStarted => 'Tag wird neu eingelesen…';

  @override
  String amsFeedTitle(String slot) {
    return '$slot in welche Düse zuführen?';
  }

  @override
  String get amsFeedPrompt =>
      'Der Filament Track Switch kann diesen Slot zu beiden Düsen leiten, daher kann der Drucker nicht selbst bestimmen, wohin das Filament geführt werden soll.';

  @override
  String get amsFeedAlreadyLoaded => 'bereits geladen';

  @override
  String get amsSwitchNotReady =>
      'Der Filament Track Switch ist noch nicht eingerichtet. Weise jedes AMS einem Einlass am Drucker zu und versuche es erneut.';

  @override
  String get amsUnloadSlotNotLoaded =>
      'Aus diesem Slot wird keine Düse versorgt';

  @override
  String get amsActionsWhilePrinting =>
      'Nicht verfügbar, während der Drucker druckt';

  @override
  String get amsSlotConfigure => 'Slot konfigurieren';

  @override
  String get amsSlotConfigTitle => 'Slot-Konfiguration';

  @override
  String get amsSlotConfigSearch => 'Profile suchen';

  @override
  String get amsSlotConfigColour => 'Farbe';

  @override
  String get amsSlotConfigApply => 'Auf Drucker schreiben';

  @override
  String get amsSlotConfigStarted => 'Slot wird konfiguriert…';

  @override
  String get amsSlotConfigNameNotSaved =>
      'Slot konfiguriert, aber der Name des Profils konnte nicht gespeichert werden';

  @override
  String get amsSlotConfigEmpty => 'Keine Filamentprofile verfügbar';

  @override
  String get amsSlotConfigNoMatch => 'Kein Profil entspricht der Suche';

  @override
  String get amsSlotConfigCloudHint =>
      'Melde dich bei Bambu Cloud an, um aus deinen eigenen Profilen zu wählen.';

  @override
  String get amsSlotConfigCloudAction => 'Anmelden';

  @override
  String get amsSlotConfigTierLocal => 'Importiert';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => 'Integriert';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return 'Nur für $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return 'Nur für $model ($hidden ausgeblendet)';
  }

  @override
  String get amsSlotConfigModelUnknown =>
      'Druckermodell unbekannt – alle Profile werden angezeigt';

  @override
  String get amsSlotConfigCurrent => 'Aktuell eingestellt';

  @override
  String get amsSlotConfigKProfile => 'K-Profil';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return 'Standard (K $value)';
  }

  @override
  String get amsSlotConfigKProfileOther => 'Weitere Profile';

  @override
  String get amsSlotConfigKProfileNone =>
      'Dieser Drucker hat keine gespeicherten K-Profile für diese Düse';

  @override
  String get amsSlotConfigKProfileUnavailable =>
      'K-Profile des Druckers konnten nicht gelesen werden';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return 'Der Drucker hat die Düsengröße nicht gemeldet – es wird $diameter mm angenommen';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => 'Katalogfarben';

  @override
  String get amsSlotConfigColourCustom => 'Benutzerdefinierte Farbe';

  @override
  String get amsSlotReset => 'Slot zurücksetzen';

  @override
  String get amsSlotResetConfirmTitle => 'Diesen Slot zurücksetzen?';

  @override
  String get amsSlotResetConfirmMessage =>
      'Der Drucker vergisst das hier konfigurierte Filament und Bambuddy vergisst, welches Profil es war.';

  @override
  String get amsSlotResetStarted => 'Slot wird zurückgesetzt…';

  @override
  String get extruderLeft => 'Linker Extruder';

  @override
  String get extruderRight => 'Rechter Extruder';

  @override
  String get extruderLeftShort => 'L';

  @override
  String get extruderRightShort => 'R';

  @override
  String get amsHumidityTooltip => 'AMS-Luftfeuchtigkeit';

  @override
  String get amsTempTooltip => 'AMS-Temperatur';

  @override
  String amsHistoryTitle(String ams) {
    return '$ams-Verlauf';
  }

  @override
  String get amsHistoryHumidity => 'Luftfeuchtigkeit';

  @override
  String get amsHistoryTemperature => 'Temperatur';

  @override
  String get sensorHistoryCurrent => 'Aktuell';

  @override
  String get sensorHistoryAverage => 'Durchschnitt';

  @override
  String get sensorHistoryMin => 'Min.';

  @override
  String get sensorHistoryMax => 'Max.';

  @override
  String get sensorHistoryRange6h => '6 h';

  @override
  String get sensorHistoryRange24h => '24 h';

  @override
  String get sensorHistoryRange48h => '48 h';

  @override
  String get sensorHistoryRange7d => '7 d';

  @override
  String get amsHistoryGood => 'Gut';

  @override
  String get amsHistoryFair => 'Mittel';

  @override
  String get sensorHistoryEmpty => 'Keine Daten für diesen Zeitraum';

  @override
  String get sensorHistoryError => 'Verlauf konnte nicht geladen werden';

  @override
  String get amsHistoryRecordingInfo =>
      'Wird alle 5 Minuten aufgezeichnet, während der Drucker verbunden ist';

  @override
  String get heaterHistoryTitle => 'Temperaturverlauf';

  @override
  String get heaterHistoryOpen => 'Temperaturverlauf';

  @override
  String get heaterHistoryReading => 'Messwert';

  @override
  String get heaterHistoryTarget => 'Zielwert';

  @override
  String get heaterHistoryRecordingInfo =>
      'Wird jede Minute aufgezeichnet, während der Drucker verbunden ist';

  @override
  String get wifiTooltip => 'WLAN-Signal';

  @override
  String get doorOpen => 'Tür offen';

  @override
  String get doorClosed => 'Tür geschlossen';

  @override
  String get firmwareUpToDate => 'Firmware ist aktuell';

  @override
  String firmwareUpdateAvailable(String version) {
    return 'Firmware-Update verfügbar: $version';
  }

  @override
  String get statusUnavailable => 'Status nicht verfügbar';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

  @override
  String get widgetNoPrinter => 'Kein Drucker';

  @override
  String get widgetStatusPrinting => 'Druckt';

  @override
  String get widgetStatusPaused => 'Pausiert';

  @override
  String get widgetStatusFinished => 'Abgeschlossen';

  @override
  String get widgetStatusFailed => 'Fehlgeschlagen';

  @override
  String get widgetStatusIdle => 'Bereit';

  @override
  String get widgetStatusOffline => 'Offline';

  @override
  String get widgetStatusError => 'Fehler';

  @override
  String get widgetMultiTitle => 'Drucker';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total aktiv';
  }

  @override
  String widgetMultiMore(int count) {
    return '+$count weitere';
  }

  @override
  String get widgetMultiGaugeLabel => 'druckt';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count bereit';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count offline';
  }

  @override
  String get widgetMultiName => 'Bambuddy · Drucker';

  @override
  String get widgetMultiDescription => 'Alle Drucker auf einen Blick';

  @override
  String remaining(String time) {
    return '$time verbleibend';
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
  String get connectToServer => 'Mit Server verbinden';

  @override
  String get serverAddressLabel => 'Bambuddy-Serveradresse';

  @override
  String get serverAddressHint => 'z. B. 192.168.1.10:8000';

  @override
  String get serverAddressHelper =>
      'Fernzugriff: HTTPS über einen Reverse-Proxy verwenden';

  @override
  String get testConnection => 'Verbindung testen';

  @override
  String get serverRequiresAuth =>
      'Der Server erfordert eine Authentifizierung';

  @override
  String get authModeApiKey => 'API-Schlüssel (empfohlen)';

  @override
  String get authModeLogin => 'Benutzername & Passwort';

  @override
  String get apiKeyExplain =>
      'Ein API-Schlüssel läuft nicht ab und hat begrenzte Berechtigungen – erstelle einen auf dem Server: Einstellungen → API-Schlüssel.';

  @override
  String get apiKeyLabel => 'API-Schlüssel';

  @override
  String get saveAndConnect => 'Speichern und verbinden';

  @override
  String get loginExplain =>
      'Eine Sitzung läuft nach 24 h ab. Aktiviere „Angemeldet bleiben“, damit sich die App automatisch wieder anmeldet.';

  @override
  String get usernameLabel => 'Benutzername oder E-Mail';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get rememberMe => 'Angemeldet bleiben';

  @override
  String get rememberMeSubtitle =>
      'Das Passwort wird im verschlüsselten Speicher abgelegt (Android Keystore)';

  @override
  String get signInAndConnect => 'Anmelden und verbinden';

  @override
  String get twoFactorTitle => 'Zwei-Faktor-Authentifizierung';

  @override
  String get twoFactorMethodTotp => 'Authenticator';

  @override
  String get twoFactorMethodEmail => 'E-Mail';

  @override
  String get twoFactorMethodBackup => 'Backup-Code';

  @override
  String get twoFactorExplainTotp =>
      'Gib den 6-stelligen Code aus deiner Authenticator-App ein.';

  @override
  String get twoFactorExplainEmail =>
      'Lass dir vom Server einen 6-stelligen Code per E-Mail senden und gib ihn hier ein.';

  @override
  String get twoFactorExplainEmailSent =>
      'Ein 6-stelliger Code wurde an die Adresse deines Kontos gesendet. Er läuft in 10 Minuten ab.';

  @override
  String get twoFactorExplainBackup =>
      'Gib einen der 8-stelligen Backup-Codes ein, die du beim Einrichten der 2FA gespeichert hast. Jeder Code funktioniert nur einmal.';

  @override
  String get twoFactorCodeLabel => 'Code';

  @override
  String get twoFactorSendEmail => 'Code per E-Mail senden';

  @override
  String get twoFactorResendEmail => 'Neuen Code senden';

  @override
  String get twoFactorVerify => 'Bestätigen und verbinden';

  @override
  String get twoFactorBack => 'Anderes Konto verwenden';

  @override
  String get twoFactorSessionNote =>
      'Die App kann eine 2FA-Sitzung nicht selbstständig erneuern, daher fragt sie erneut, wenn diese abläuft. Ein API-Schlüssel läuft nicht ab und überspringt diesen Schritt.';

  @override
  String get tryDemo => 'Demo ausprobieren';

  @override
  String get scanApiKeyTitle => 'API-Schlüssel scannen';

  @override
  String get scanApiKeyHint =>
      'Kamera auf den QR-Code des API-Schlüssels richten';

  @override
  String get cameraPermissionTitle => 'Kamerazugriff erforderlich';

  @override
  String get cameraPermissionBody =>
      'Erlaube den Kamerazugriff, um QR-Codes zu scannen.';

  @override
  String get errMissingUrl => 'Serveradresse eingeben';

  @override
  String get errMissingApiKey => 'API-Schlüssel eingeben';

  @override
  String get errMissingCredentials => 'Benutzername und Passwort eingeben';

  @override
  String get errRequiresServerSetup =>
      'Der Server erfordert eine Ersteinrichtung — schließe sie im Browser ab und kehre hierher zurück.';

  @override
  String get errServerUnreachable => 'Server nicht erreichbar';

  @override
  String get errUnauthorized => 'Nicht autorisiert';

  @override
  String get errForbidden =>
      'Nicht zulässig — der Server hat diese Aktion abgelehnt';

  @override
  String errForbiddenDetail(String reason) {
    return 'Nicht zulässig: $reason';
  }

  @override
  String get errApiKeyOwnerDisabled =>
      'Das Konto, zu dem dieser API-Schlüssel gehört, wurde deaktiviert oder gelöscht — der Schlüssel bleibt abgelehnt, bis das Konto wiederhergestellt wird.';

  @override
  String errBadResponse(int code) {
    return 'Server antwortete mit Fehler $code';
  }

  @override
  String get errBadCertificate =>
      'Ungültiges TLS-Zertifikat (selbstsignierte Zertifikate werden in v1 nicht unterstützt)';

  @override
  String get errConnection => 'Verbindungsfehler';

  @override
  String get errMalformedResponse => 'Ungültige Serverantwort';

  @override
  String get errInvalidCredentials =>
      'Ungültiger Benutzername oder ungültiges Passwort';

  @override
  String get errTwoFactorUnsupported =>
      'Konto erfordert 2FA — in dieser Version nicht unterstützt. Verwende einen API-Schlüssel (Einstellungen → API-Schlüssel auf dem Server).';

  @override
  String get errTwoFactorCodeRejected =>
      'Falscher Code — überprüfe ihn und versuche es erneut.';

  @override
  String get errTwoFactorChallengeExpired =>
      'Der Anmeldeversuch ist abgelaufen — gib dein Passwort erneut ein, um einen neuen Code zu erhalten.';

  @override
  String get errTwoFactorMethodUnavailable =>
      'Diese Methode ist für dieses Konto nicht verfügbar — wähle eine andere.';

  @override
  String get errTwoFactorEmailUnavailable =>
      'Der Server konnte den Code nicht senden — es ist keine E-Mail-Konfiguration vorhanden oder das Konto hat keine Adresse. Verwende eine andere Methode.';

  @override
  String get errMissingTwoFactorCode => 'Code eingeben';

  @override
  String get errApiKeyRejected =>
      'API-Schlüssel abgelehnt — überprüfe den Schlüssel und seinen Scope (can_read_status erforderlich)';

  @override
  String get errTooManyAttempts =>
      'Zu viele Versuche — der Server blockiert die Anmeldung für einige Minuten. Warte kurz und versuche es erneut, oder verwende einen API-Schlüssel.';

  @override
  String get errSlotTagUnreadable =>
      'Dieser Slot hat keinen lesbaren RFID-Tag — Spoolman verknüpft Spulen per Tag und kann diese daher nicht übernehmen. Der integrierte Bestand weist stattdessen nach Slot zu.';

  @override
  String get errPrinterOffline =>
      'Der Drucker ist offline, daher kann die App den Inhalt des Slots nicht auslesen. Verbinde ihn erneut und versuche es noch einmal.';

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent% · ETA $eta';
  }

  @override
  String notifMorePrints(int count) {
    return '+$count';
  }

  @override
  String get printFinishedTitle => 'Druck abgeschlossen';

  @override
  String printFinishedBody(String name) {
    return '$name ist fertig';
  }

  @override
  String get printFailedTitle => 'Druck fehlgeschlagen';

  @override
  String printFailedBody(String name) {
    return '$name fehlgeschlagen';
  }

  @override
  String get notifStartedTitle => 'Druck gestartet';

  @override
  String notifStartedBody(String name) {
    return 'Druck von $name gestartet';
  }

  @override
  String get notifFirstLayerTitle => 'Erste Schicht fertig';

  @override
  String notifFirstLayerBody(String name) {
    return '$name hat die erste Schicht abgeschlossen';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return '$percent% gedruckt';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name ist zu $percent% fertig';
  }

  @override
  String get notifPlateTitle => 'Druckplatte nicht leer';

  @override
  String notifPlateBody(String printer) {
    return 'Bei $printer muss die Druckplatte vor dem nächsten Auftrag geräumt werden';
  }

  @override
  String get notifOfflineTitle => 'Drucker offline';

  @override
  String notifOfflineBody(String printer) {
    return '$printer hat die Verbindung verloren';
  }

  @override
  String get notifErrorTitle => 'Druckerfehler';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer: $detail';
  }

  @override
  String get notifLowFilamentTitle => 'Niedriger Filamentstand';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return '$printer hat noch $percent% Filament übrig';
  }

  @override
  String get notifHumidityTitle => 'AMS-Feuchtigkeit hoch';

  @override
  String get notifHumidityHtTitle => 'AMS-HT-Feuchtigkeit hoch';

  @override
  String notifHumidityBody(String printer, int value) {
    return '$printer: AMS-Feuchtigkeit liegt bei $value%';
  }

  @override
  String get notifBedCooledTitle => 'Druckbett abgekühlt';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return 'Druckbett von $printer auf $temp°C abgekühlt';
  }

  @override
  String get notifSettingsTitle => 'Benachrichtigungen';

  @override
  String get notifSettingsHint =>
      'Wähle, welche Ereignisse eine Benachrichtigung auslösen. Änderungen werden beim nächsten Start der Hintergrundüberwachung wirksam.';

  @override
  String get notifMasterTitle => 'Ereignisbenachrichtigungen';

  @override
  String get notifMasterDesc =>
      'Ausschalten, um alle Alarme stummzuschalten. Die laufende Benachrichtigung über den Druckfortschritt bleibt erhalten.';

  @override
  String get notifEventsHeader => 'Ereignisse';

  @override
  String get notifExtrasHeader => 'Details';

  @override
  String get notifFinishPhotoTitle => 'Foto des fertigen Drucks';

  @override
  String get notifFinishPhotoDesc =>
      'Fügt der Benachrichtigung über Abschluss oder Fehlschlag das Foto hinzu, das der Server nach dem Druck aufnimmt, sobald es verfügbar ist';

  @override
  String get notifThresholdsHeader => 'Schwellenwerte';

  @override
  String get notifEvtStarted => 'Druck gestartet';

  @override
  String get notifEvtStartedDesc => 'Wenn ein Druck beginnt';

  @override
  String get notifEvtFinished => 'Druck abgeschlossen';

  @override
  String get notifEvtFinishedDesc =>
      'Wenn ein Druck erfolgreich abgeschlossen wird';

  @override
  String get notifEvtFailed => 'Druck fehlgeschlagen';

  @override
  String get notifEvtFailedDesc => 'Wenn ein Druck fehlschlägt';

  @override
  String get notifEvtFirstLayer => 'Erste Schicht fertig';

  @override
  String get notifEvtFirstLayerDesc =>
      'Wenn die erste Schicht fertiggestellt ist';

  @override
  String get notifEvtMilestones => 'Fortschrittsmeilensteine';

  @override
  String get notifEvtMilestonesDesc => 'Bei 25%, 50% und 75%';

  @override
  String get notifEvtPlate => 'Druckplatte nicht leer';

  @override
  String get notifEvtPlateDesc =>
      'Wenn die Druckplatte vor dem nächsten Auftrag geräumt werden muss';

  @override
  String get notifEvtOffline => 'Drucker offline';

  @override
  String get notifEvtOfflineDesc => 'Wenn ein Drucker die Verbindung verliert';

  @override
  String get notifEvtError => 'Druckerfehler (HMS)';

  @override
  String get notifEvtErrorDesc => 'Wenn der Drucker einen HMS-Fehler meldet';

  @override
  String get notifEvtLowFilament => 'Niedriger Filamentstand';

  @override
  String get notifEvtLowFilamentDesc =>
      'Wenn das verbleibende Filament unter den Schwellenwert fällt';

  @override
  String get notifEvtHumidity => 'AMS-Feuchtigkeit hoch';

  @override
  String get notifEvtHumidityDesc =>
      'Wenn die AMS-Feuchtigkeit über den Schwellenwert steigt';

  @override
  String get notifEvtBedCooled => 'Druckbett abgekühlt';

  @override
  String get notifEvtBedCooledDesc =>
      'Wenn das Druckbett nach einem Druck abkühlt';

  @override
  String notifBedCooledThreshold(int temp) {
    return 'Druckbett unter $temp°C abgekühlt';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'AMS-Feuchtigkeit über $value%';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return 'Niedriger Filamentstand unter $percent%';
  }

  @override
  String get notifEventsMenu => 'Benachrichtigungsereignisse';

  @override
  String get hmsErrorsHeader => 'Aktive Fehler';

  @override
  String get hmsViewInWiki => 'Im Bambu-Wiki öffnen';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fehler',
      one: '1 Fehler',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => 'Alle verwerfen';

  @override
  String get hmsDismissed => 'Fehler auf dem Drucker gelöscht';

  @override
  String get hmsDismissFailed => 'Fehler konnten nicht gelöscht werden';

  @override
  String get hmsActionSent => 'An den Drucker gesendet';

  @override
  String get hmsActionFailed => 'Der Drucker hat die Aktion abgelehnt';

  @override
  String get hmsActionNotAcknowledged =>
      'Der Drucker hat die Aktion nicht bestätigt — überprüfe seinen Bildschirm';

  @override
  String get hmsStopConfirmTitle => 'Druck abbrechen?';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer bricht den Druckauftrag ab. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get hmsStopConfirmAction => 'Druck abbrechen';

  @override
  String get hmsActionResume => 'Fortsetzen';

  @override
  String get hmsActionResumeDefects => 'Trotzdem fortsetzen';

  @override
  String get hmsActionResumeSolved => 'Behoben, fortsetzen';

  @override
  String get hmsActionProblemSolvedResume => 'Behoben, fortsetzen';

  @override
  String get hmsActionFilamentLoadedResume => 'Geladen, fortsetzen';

  @override
  String get hmsActionProceed => 'Fortfahren';

  @override
  String get hmsActionStopPrinting => 'Stopp';

  @override
  String get hmsActionIgnoreResume => 'Ignorieren, fortsetzen';

  @override
  String get hmsActionIgnoreNoReminder => 'Immer ignorieren';

  @override
  String get hmsActionDontRemind => 'Nicht erinnern';

  @override
  String get hmsActionNoReminder => 'Verwerfen';

  @override
  String get hmsActionFilamentExtruded => 'Extrudiert';

  @override
  String get hmsActionRetryFilamentExtruded => 'Noch nicht, wiederholen';

  @override
  String get hmsActionContinue => 'Fertig, weiter';

  @override
  String get hmsActionRetrySolved => 'Behoben, wiederholen';

  @override
  String get hmsActionDone => 'Fertig';

  @override
  String get hmsActionRetry => 'Wiederholen';

  @override
  String get hmsActionResumePlain => 'Fortsetzen';

  @override
  String get hmsActionConfirm => 'Bestätigen';

  @override
  String get hmsActionAbort => 'Abbrechen';

  @override
  String get hmsActionOk => 'OK';

  @override
  String get hmsActionRecheck => 'Erneut prüfen';

  @override
  String get hmsActionTurnOffFireAlarm => 'Alarm ausschalten';

  @override
  String get hmsActionStopDrying => 'Trocknen beenden';

  @override
  String get hmsActionDisablePurification => 'Luftreinigung deaktivieren';

  @override
  String get batteryOptTitle => 'Zuverlässige Hintergrundbenachrichtigungen';

  @override
  String get batteryOptBody =>
      'Damit Druckbenachrichtigungen im Hintergrund zuverlässig funktionieren, erlaube Bambuddy die Ausführung ohne Akku-Einschränkungen. Auf Samsung-Geräten ist dies unerlässlich.';

  @override
  String get batteryOptAllow => 'Einstellungen öffnen';

  @override
  String get batteryOptLater => 'Später';

  @override
  String get batteryOptMenu => 'Hintergrundbenachrichtigungen';

  @override
  String get notificationsReady => 'Benachrichtigungen sind eingerichtet';

  @override
  String get notificationsBlocked =>
      'Benachrichtigungen sind deaktiviert — aktiviere sie in den Systemeinstellungen';

  @override
  String get bgServiceTitle => 'Bambuddy';

  @override
  String get bgServiceText => 'Drucker werden überwacht';

  @override
  String get bgMonitoringToggle => 'Hintergrundüberwachung';

  @override
  String get bgMonitoringSubtitle =>
      'Drucke weiter überwachen, während die App geschlossen ist. Zeigt eine dauerhafte Benachrichtigung an.';

  @override
  String get bgMonitoringOn => 'Hintergrundüberwachung an';

  @override
  String get bgMonitoringOff => 'Hintergrundüberwachung aus';

  @override
  String get navDashboard => 'Drucker';

  @override
  String get navQueue => 'Warteschlange';

  @override
  String get navArchive => 'Archiv';

  @override
  String get navMaintenance => 'Wartung';

  @override
  String get navFilaments => 'Filamente';

  @override
  String get inventoryEmpty => 'Keine Spulen im Bestand';

  @override
  String get inventoryNoMatches => 'Keine Filamente entsprechen deiner Suche';

  @override
  String get inventorySearchHint => 'Material, Marke, Farbe suchen…';

  @override
  String get inventoryShowArchived => 'Archivierte anzeigen';

  @override
  String get inventoryArchived => 'Archiviert';

  @override
  String get inventoryLowStock => 'Niedrig';

  @override
  String get inventoryFilters => 'Filter';

  @override
  String get inventoryFilterStatus => 'Status';

  @override
  String get inventoryStatusActive => 'Aktiv';

  @override
  String get inventoryStatusArchived => 'Archiviert';

  @override
  String get inventoryFilterStock => 'Bestand';

  @override
  String get inventoryStockAll => 'Alle';

  @override
  String get inventoryStockLow => 'Niedriger Bestand';

  @override
  String get inventoryFilterMaterial => 'Material';

  @override
  String get inventoryFilterBrand => 'Marke';

  @override
  String get inventoryFiltersClear => 'Alle zurücksetzen';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return '$grams g übrig';
  }

  @override
  String inventoryTotalConsumed(String weight) {
    return '$weight verbraucht';
  }

  @override
  String inventoryConsumedSinceReset(String weight) {
    return 'Seit Zurücksetzen verbraucht: $weight';
  }

  @override
  String inventoryOfTotal(int total) {
    return 'von $total g';
  }

  @override
  String inventoryLoadedIn(String slot) {
    return 'Geladen in $slot';
  }

  @override
  String get inventoryNotLoaded => 'In keinem AMS-Slot geladen';

  @override
  String get inventoryLocation => 'Lagerort';

  @override
  String get inventoryNozzleTemp => 'Düsentemperatur';

  @override
  String inventoryCostPerKg(String cost) {
    return '$cost/kg';
  }

  @override
  String get inventoryNote => 'Notiz';

  @override
  String get inventoryTag => 'Tag';

  @override
  String get inventoryId => 'Filament-ID';

  @override
  String get inventoryUsageHistory => 'Verbrauchsverlauf';

  @override
  String get inventoryUsageEmpty => 'Noch kein Verbrauch erfasst';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => 'Kalibrierung (K)';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle mm · K $k';
  }

  @override
  String get inventoryAddSpool => 'Spule hinzufügen';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 hinzufügen';
  }

  @override
  String get inventoryNewSpool => 'Neue Spule';

  @override
  String get inventoryEditSpool => 'Spule bearbeiten';

  @override
  String get inventorySave => 'Speichern';

  @override
  String get inventoryFieldQuantity => 'Anzahl';

  @override
  String get inventoryQuantityHint =>
      'Mehrere identische Spulen auf einmal erstellen';

  @override
  String get inventoryEdit => 'Bearbeiten';

  @override
  String get inventoryDelete => 'Löschen';

  @override
  String get inventoryArchive => 'Archivieren';

  @override
  String get inventoryRestore => 'Wiederherstellen';

  @override
  String get inventoryResetUsage => 'Verbrauch zurücksetzen';

  @override
  String get inventoryFieldSlicerPreset => 'Slicer-Profil';

  @override
  String get inventorySlicerPresetHint =>
      'Druckprofil, mit dem diese Spule hinzugefügt wird';

  @override
  String get inventorySlicerPresetNone => 'Kein Profil';

  @override
  String get inventorySlicerPresetSearch => 'Profile suchen…';

  @override
  String get inventorySlicerPresetUnavailable =>
      'Keine Slicer-Profile verfügbar. Aktiviere das Slicing auf dem Server (und verbinde die Bambu Cloud für Cloud-Profile).';

  @override
  String get inventorySectionPrinterPresets => 'Profile pro Druckermodell';

  @override
  String get inventoryPrinterPresetsHint =>
      'Eine Auswahl hier hat Vorrang vor dem Profil der Spule.';

  @override
  String get inventoryPrinterPresetDefault => 'Wie auf der Spule';

  @override
  String inventoryPrinterPresetNozzle(String model, String diameter) {
    return '$model · Düse $diameter';
  }

  @override
  String get inventoryPrinterPresetsLoadFailed =>
      'Nicht gelesen — beim Speichern bleiben sie unverändert.';

  @override
  String get inventoryPrinterPresetsSaveFailed =>
      'Spule gespeichert, modellspezifische Profile jedoch nicht.';

  @override
  String get inventoryFieldMaterial => 'Material';

  @override
  String get inventoryFieldBrand => 'Marke';

  @override
  String get inventoryFieldSubtype => 'Variante';

  @override
  String get inventoryFieldColorName => 'Farbname';

  @override
  String get inventoryFieldColorHex => 'Farbe (Hex)';

  @override
  String get inventoryFieldLabelWeight => 'Spulengewicht (g)';

  @override
  String get inventoryFieldWeightUsed => 'Verbraucht (g)';

  @override
  String get inventoryFieldCostPerKg => 'Kosten pro kg';

  @override
  String get inventoryFieldLowStock =>
      'Schwellenwert für niedrigen Bestand (%)';

  @override
  String get inventoryFieldLocation => 'Lagerort';

  @override
  String get inventoryFieldNozzleMin => 'Düse min (°C)';

  @override
  String get inventoryFieldNozzleMax => 'Düse max (°C)';

  @override
  String get inventoryFieldNote => 'Notiz';

  @override
  String get inventoryFieldRequired => 'Erforderlich';

  @override
  String get inventoryFieldInvalidNumber => 'Zahl eingeben';

  @override
  String inventoryFieldRange(int min, int max) {
    return 'Wert von $min bis $max eingeben';
  }

  @override
  String get inventoryFieldNegative => 'Wert von mindestens 0 eingeben';

  @override
  String get inventorySectionBasics => 'Basisdaten';

  @override
  String get inventorySectionWeight => 'Gewicht & Kosten';

  @override
  String get inventorySectionDetails => 'Details';

  @override
  String get inventorySectionFilament => 'Filament';

  @override
  String get inventorySectionColor => 'Farbe';

  @override
  String get inventorySectionAdditional => 'Zusätzliches';

  @override
  String get inventoryFieldEmptySpoolWeight => 'Leergewicht der Spule (g)';

  @override
  String get inventoryCoreWeightSelect => 'Auswählen…';

  @override
  String get inventoryCoreWeightSearch => 'Spulen suchen…';

  @override
  String get inventoryFieldRemainingWeight => 'Verbleibendes Gewicht (g)';

  @override
  String get inventoryFieldMeasuredWeight => 'Gemessenes Gewicht (g)';

  @override
  String get inventoryFieldCategory => 'Kategorie';

  @override
  String get inventoryFieldExtraColors => 'Zusätzliche Farben';

  @override
  String get inventoryExtraColorsHint => '2–8 Hex-Werte, kommagetrennt';

  @override
  String get inventoryFieldEffect => 'Effekt';

  @override
  String get inventoryEffectNone => 'Keiner';

  @override
  String get inventoryColorCommon => 'Standardfarben';

  @override
  String get inventoryColorSearchHint => 'Farben suchen…';

  @override
  String get inventoryColorPickTitle => 'Farbe auswählen';

  @override
  String get inventoryColorSelect => 'Auswählen';

  @override
  String get inventoryColorNone => 'Keine Farbe';

  @override
  String get inventoryLowStockHint =>
      'Leer lassen, um den globalen Schwellenwert zu verwenden';

  @override
  String inventoryRemainingOfLabel(int total) {
    return 'von $total g';
  }

  @override
  String get inventoryDeleteTitle => 'Spule löschen?';

  @override
  String inventoryDeleteConfirm(String name) {
    return '$name dauerhaft löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get inventoryResetUsageConfirm =>
      'Zähler für verbrauchtes Filament auf null zurücksetzen? Zukünftige Drucke zählen wieder ab null — das verbleibende Gewicht wird nicht geändert.';

  @override
  String get inventorySpoolCreated => 'Spule hinzugefügt';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 hinzugefügt';
  }

  @override
  String get inventorySpoolUpdated => 'Spule aktualisiert';

  @override
  String get inventorySpoolDeleted => 'Spule gelöscht';

  @override
  String get inventorySpoolArchived => 'Spule archiviert';

  @override
  String get inventorySpoolRestored => 'Spule wiederhergestellt';

  @override
  String get inventoryUsageReset => 'Zähler zurückgesetzt';

  @override
  String get inventorySaveFailed => 'Spule konnte nicht gespeichert werden';

  @override
  String get inventoryActionFailed => 'Aktion fehlgeschlagen';

  @override
  String get inventoryUnassign => 'Zuweisung aufheben';

  @override
  String get inventoryAssign => 'Slot zuweisen';

  @override
  String get inventoryAssignPrinter => 'Drucker';

  @override
  String get inventoryAssignNoPrinters => 'Keine Drucker verfügbar';

  @override
  String get inventorySlotAms => 'AMS-Slot';

  @override
  String get inventoryAssignUnit => 'AMS-Einheit';

  @override
  String get inventoryAssignSlot => 'Slot';

  @override
  String get inventoryAssignExtruder => 'Extruder';

  @override
  String get inventoryAssignExternalHint =>
      'Weist dem externen Spulenhalter zu';

  @override
  String get inventoryAssignConfirm => 'Zuweisen';

  @override
  String get inventoryAssignTitle => 'Spule zuweisen';

  @override
  String get inventoryAssignCurrent => 'Derzeit in diesem Slot';

  @override
  String get inventoryAssignPick => 'Spule auswählen';

  @override
  String get inventoryReassignTitle => 'Spule verschieben?';

  @override
  String inventoryReassignMessage(String slot) {
    return 'Diese Spule befindet sich derzeit in $slot. Sie wird von dort entfernt und diesem Slot zugewiesen.';
  }

  @override
  String get inventoryReassignAction => 'Verschieben';

  @override
  String get inventorySpoolAssigned => 'Spule zugewiesen';

  @override
  String get inventorySpoolUnassigned => 'Zuweisung der Spule aufgehoben';

  @override
  String get inventoryFromSlot => 'Zum Inventar hinzufügen';

  @override
  String get inventoryFromSlotHint =>
      'Die vom Drucker in diesem Slot gemeldete Spule mit RFID-Tag erfassen';

  @override
  String get inventoryFromSlotDone =>
      'Spule hinzugefügt und dem Slot zugewiesen';

  @override
  String get inventoryFromSlotNoTag =>
      'Der Drucker meldet in diesem Slot keine Spule mit RFID-Tag mehr';

  @override
  String get inventoryFromSlotOffline =>
      'Der Drucker ist nicht verbunden und kann nicht ermitteln, was sich im Slot befindet';

  @override
  String get inventoryFromSlotUnsupported =>
      'Diese Serverversion kann keine Spule direkt aus einem Slot hinzufügen';

  @override
  String get inventoryScanSpool => 'QR scannen';

  @override
  String get inventoryScanTitle => 'Spulen-QR scannen';

  @override
  String get inventoryScanHint => 'Richte die Kamera auf den QR-Code der Spule';

  @override
  String get inventoryScanPermissionTitle => 'Kamerazugriff erforderlich';

  @override
  String get inventoryScanPermissionBody =>
      'Erlaube den Kamerazugriff, um QR-Codes von Spulen zu scannen.';

  @override
  String get inventoryScanOpenSettings => 'Einstellungen öffnen';

  @override
  String get inventoryScanInvalid => 'Unbekannter QR-Code';

  @override
  String inventoryScanNotFound(int id) {
    return 'Spule #$id nicht gefunden';
  }

  @override
  String inventorySelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get inventorySelectAll => 'Alle auswählen';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 archivieren?';
  }

  @override
  String get inventoryBulkArchiveBody =>
      'Sie werden aus der aktiven Liste ausgeblendet. Du kannst sie später wiederherstellen.';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 wiederherstellen?';
  }

  @override
  String get inventoryBulkRestoreBody =>
      'Sie werden wieder in die aktive Liste aufgenommen.';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 löschen?';
  }

  @override
  String get inventoryBulkDeleteBody =>
      'Dies entfernt sie dauerhaft und kann nicht rückgängig gemacht werden.';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return 'Verbrauch bei $count $_temp0 zurücksetzen?';
  }

  @override
  String get inventoryBulkResetBody =>
      'Ihre Zähler für verbrauchtes Filament werden auf null zurückgesetzt. Das verbleibende Gewicht wird nicht geändert.';

  @override
  String inventoryBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 aktualisiert';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return '$ok erfolgreich, $failed fehlgeschlagen';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return '$ok erfolgreich, $skipped bereits vorhanden';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return '$ok erfolgreich, $skipped bereits vorhanden, $failed fehlgeschlagen';
  }

  @override
  String get inventoryBulkEdit => 'Felder bearbeiten';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 bearbeiten';
  }

  @override
  String get inventoryBulkEditHint =>
      'Nur ausgefüllte Felder werden geändert. Den Rest leer lassen.';

  @override
  String get inventoryBulkEditUnchanged => 'Unverändert';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return 'Auf $count $_temp0 anwenden';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spulen',
      one: 'Spule',
    );
    return '$count $_temp0 ändern?';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: 'Felder werden',
      one: 'Feld wird',
    );
    return '$fields $_temp0 auf jeder ausgewählten Spule überschrieben.';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      'Dieser Server ist zu alt für Massenbearbeitung. Aktualisiere Bambuddy oder bearbeite die Spulen einzeln.';

  @override
  String get inventoryApply => 'Anwenden';

  @override
  String get inventoryLabelsTitle => 'Spulenetiketten drucken';

  @override
  String get inventoryLabelsPrint => 'Etiketten drucken';

  @override
  String get inventoryLabelsPrintAll => 'Etiketten für alle drucken';

  @override
  String get inventoryClimateTitle => 'Lagerbedingungen';

  @override
  String get inventoryClimateTitleAlerting =>
      'Lagerbedingungen: außerhalb des Warnbereichs';

  @override
  String get inventoryClimateSource =>
      'Der Server liest diese aus Home Assistant aus. Sensoren werden in der Weboberfläche von Bambuddy einem Standort zugewiesen.';

  @override
  String get inventoryClimateNoReading => 'kein Messwert';

  @override
  String inventoryClimateReading(String name, String value) {
    return '$name: $value';
  }

  @override
  String inventoryClimateReadingAlerting(String name, String value) {
    return '$name: $value, außerhalb des Warnbereichs';
  }

  @override
  String inventoryClimateReadingStale(String name, String value) {
    return '$name: $value, Sensor nicht erreichbar';
  }

  @override
  String get inventoryLabelsSearchHint => 'Name, Marke oder #ID suchen';

  @override
  String get inventoryLabelsPickSpools =>
      'Spulen für den Etikettendruck auswählen:';

  @override
  String get inventoryLabelsMaterial => 'Material:';

  @override
  String get inventoryLabelsAllMaterials => 'Alle';

  @override
  String get inventoryLabelsSort => 'Sortierung:';

  @override
  String get inventoryLabelsSortById => 'Nach ID';

  @override
  String get inventoryLabelsSortByColor => 'Nach Farbe';

  @override
  String get inventoryLabelsSelectVisible => 'Sichtbare auswählen';

  @override
  String get inventoryLabelsDeselectVisible => 'Sichtbare abwählen';

  @override
  String get inventoryLabelsClearAll => 'Alle abwählen';

  @override
  String get inventoryLabelsNoMatches =>
      'Keine Spulen entsprechen der aktuellen Suche oder dem Filter.';

  @override
  String get inventoryLabelsMonochrome => 'Monochrom (Schwarz-Weiß-Drucker)';

  @override
  String get inventoryLabelsMonochromeHint =>
      'Entfernt das Farbfeld und verbreitert den Text';

  @override
  String get inventoryLabelsShare => 'PDF teilen statt drucken';

  @override
  String get inventoryLabelsPickTemplate =>
      'Etikettengröße zum Drucken auswählen:';

  @override
  String inventoryLabelsTooMany(int max) {
    return 'Maximal $max Spulen pro Druck auswählen';
  }

  @override
  String get inventoryLabelsFailed =>
      'Etiketten konnten nicht generiert werden';

  @override
  String get inventoryLabelsAmsSmall => 'AMS-Halter – klein (74 × 33 mm)';

  @override
  String get inventoryLabelsAmsSmallHint =>
      'Eins pro Seite; passend für das druckbare Etikett von MakerWorld-Modell 752566.';

  @override
  String get inventoryLabelsAmsLarge => 'AMS-Halter – groß (75 × 55 mm)';

  @override
  String get inventoryLabelsAmsLargeHint =>
      'Eins pro Seite; passend für die Karton-Einschub-Variante desselben Halters.';

  @override
  String get inventoryLabelsBox40 => 'Box-Etikett (40 × 30 mm)';

  @override
  String get inventoryLabelsBox40Hint =>
      'Eins pro Seite; gängiges DK/Brother-Rollenformat, gut für Beutel und Boxen.';

  @override
  String get inventoryLabelsBox62 => 'Box-Etikett (62 × 29 mm)';

  @override
  String get inventoryLabelsBox62Hint =>
      'Eins pro Seite; passend für kleine Etiketten von Brother PT/QL und Dymo.';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 – A4-Bogen (38,1 × 63,5 mm × 21)';

  @override
  String get inventoryLabelsAveryL7160Hint =>
      'EU-Bogenware; 21 Etiketten pro A4-Seite.';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 – US-Letter-Bogen (25,4 × 66,7 mm × 30)';

  @override
  String get inventoryLabelsAvery5160Hint =>
      'US-Bogenware; 30 Etiketten pro Letter-Seite.';

  @override
  String get inventoryLabelsStartTitle => 'Erstes freies Etikett';

  @override
  String get inventoryLabelsStartHint =>
      'Tippe auf das Feld, in dem das erste Etikett gedruckt werden soll – die Felder davor bleiben leer, damit ein angefangener Bogen aufgebraucht werden kann, statt einen neuen zu beginnen.';

  @override
  String inventoryLabelsStartSlot(int position) {
    return 'Position $position';
  }

  @override
  String get maintenanceEmpty => 'Keine Wartungsdaten';

  @override
  String maintenanceTotalHours(int hours) {
    return '$hours h gesamt';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count fällig';
  }

  @override
  String maintenanceWarningBadge(int count) {
    return '$count bald fällig';
  }

  @override
  String maintenanceDueIn(int hours) {
    return 'Fällig in $hours h';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return 'Seit $hours h überfällig';
  }

  @override
  String get maintenancePerform => 'Als erledigt markieren';

  @override
  String get maintenancePerformConfirm =>
      'Zähler für diese Wartungsaufgabe zurücksetzen?';

  @override
  String get maintenanceNotesHint => 'Notizen (optional)';

  @override
  String get maintenanceHistory => 'Verlauf';

  @override
  String get maintenanceHistoryEmpty => 'Noch kein Verlauf vorhanden';

  @override
  String get maintenanceDone => 'Wartung als erledigt markiert';

  @override
  String get maintenanceFailed => 'Wartung konnte nicht aktualisiert werden';

  @override
  String get maintenanceSaved => 'Gespeichert';

  @override
  String get maintenanceSettingsTitle => 'Wartungseinstellungen';

  @override
  String get maintenanceOverridesTitle => 'Intervall-Überschreibungen';

  @override
  String get maintenanceOverridesSubtitle =>
      'Aufgaben stummschalten oder Intervalle pro Drucker anpassen';

  @override
  String get maintenanceTabStatus => 'Status';

  @override
  String get maintenanceTabSettings => 'Einstellungen';

  @override
  String get maintenanceMute => 'Stummschalten';

  @override
  String get maintenanceUnmute => 'Stummschaltung aufheben';

  @override
  String get maintenanceMuted => 'Aufgabe stummgeschaltet';

  @override
  String get maintenanceUnmuted => 'Stummschaltung der Aufgabe aufgehoben';

  @override
  String get maintenanceEditInterval => 'Intervall bearbeiten';

  @override
  String get maintenanceResetInterval => 'Auf Standard zurücksetzen';

  @override
  String get maintenanceTypesTitle => 'Wartungstypen';

  @override
  String get maintenanceTypesSubtitle => 'Systemtypen und eigene Aufgaben';

  @override
  String get maintenanceRestoreDefaults => 'Standardwerte wiederherstellen';

  @override
  String get maintenanceRestoreConfirm =>
      'Alle ausgeblendeten Standard-Wartungstypen wiederherstellen?';

  @override
  String get maintenanceAddType => 'Eigenen Typ hinzufügen';

  @override
  String get maintenanceEditType => 'Typ bearbeiten';

  @override
  String get maintenanceSystemType => 'System';

  @override
  String maintenanceEveryHours(int count) {
    return 'Alle $count h';
  }

  @override
  String maintenanceEveryDays(int count) {
    return 'Alle $count Tage';
  }

  @override
  String get maintenanceDeleteTypeTitle => 'Wartungstyp löschen?';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return '„$name“ löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return 'Standardtyp „$name“ ausblenden? Du kannst ihn später wiederherstellen.';
  }

  @override
  String get maintenanceFieldName => 'Name';

  @override
  String get maintenanceFieldNameHint => 'z. B. HEPA-Filter austauschen';

  @override
  String get maintenanceFieldIntervalType => 'Intervalltyp';

  @override
  String get maintenanceFieldInterval => 'Intervall';

  @override
  String get maintenanceIntervalHours => 'Druckstunden';

  @override
  String get maintenanceIntervalDays => 'Tage';

  @override
  String get maintenanceIntervalInvalid => 'Einen Wert ≥ 1 eingeben';

  @override
  String get maintenanceFieldIcon => 'Symbol';

  @override
  String get maintenanceFieldDocLink => 'Dokumentationslink (optional)';

  @override
  String get maintenanceAssignPrinters => 'Druckern zuweisen';

  @override
  String get maintenanceSelectPrinter => 'Mindestens einen Drucker auswählen';

  @override
  String get notifEvtMaintenance => 'Wartung fällig';

  @override
  String get notifEvtMaintenanceDesc =>
      'Wenn eine Wartungsaufgabe überfällig wird';

  @override
  String get maintenanceNotifTitle => 'Wartung fällig';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer: $task';
  }

  @override
  String get maintenanceReminderTitle => 'Wartungserinnerung';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wartungsaufgaben',
      one: 'Wartungsaufgabe',
    );
    return '$printer hat $count überfällige $_temp0';
  }

  @override
  String get maintenanceNotifAction => 'Als erledigt markieren';

  @override
  String get navMenu => 'Menü';

  @override
  String get menuStatistics => 'Statistiken';

  @override
  String get statsTitle => 'Statistiken';

  @override
  String get statsRangeAllTime => 'Gesamter Zeitraum';

  @override
  String get statsRangeLast7Days => 'Letzte 7 Tage';

  @override
  String get statsRangeLast30Days => 'Letzte 30 Tage';

  @override
  String get statsRangeLast90Days => 'Letzte 90 Tage';

  @override
  String get statsRangeThisYear => 'Dieses Jahr';

  @override
  String get statsRangeCustom => 'Benutzerdefinierter Zeitraum';

  @override
  String get statsEmpty => 'Keine Drucke in diesem Zeitraum';

  @override
  String get statsLoadFailed => 'Statistiken konnten nicht geladen werden';

  @override
  String get statsOverview => 'Übersicht';

  @override
  String get statsTotalPrints => 'Drucke gesamt';

  @override
  String get statsPrintTime => 'Druckzeit';

  @override
  String get statsFilamentUsed => 'Verbrauchtes Filament';

  @override
  String get statsFilamentCost => 'Filamentkosten';

  @override
  String get statsEnergyUsed => 'Verbrauchte Energie';

  @override
  String get statsEnergyCost => 'Energiekosten';

  @override
  String get statsTotalCost => 'Gesamtkosten';

  @override
  String get statsEnergyWarmingUp => 'Energiedaten werden noch gesammelt';

  @override
  String get statsSuccessRate => 'Erfolgsquote';

  @override
  String statsSuccessful(int count) {
    return 'Erfolgreich: $count';
  }

  @override
  String statsFailed(int count) {
    return 'Fehlgeschlagen: $count';
  }

  @override
  String statsCancelled(int count) {
    return 'Abgebrochen: $count';
  }

  @override
  String get statsAllUsers => 'Alle Benutzer';

  @override
  String get statsNoUser => 'Kein Benutzer (System)';

  @override
  String get statsTimeAccuracy => 'Zeitgenauigkeit';

  @override
  String get statsTimeAccuracyHint => '100 % = exakte Schätzung';

  @override
  String get statsByMaterial => 'Drucke nach Material';

  @override
  String get statsByPrinter => 'Drucke nach Drucker';

  @override
  String get statsTimeAccuracyByPrinter => 'Zeitgenauigkeit nach Drucker';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Drucke',
      one: '$count Druck',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours h';
  }

  @override
  String statsPrinterFallback(String id) {
    return 'Drucker #$id';
  }

  @override
  String get statsMetricWeight => 'Gewicht';

  @override
  String get statsMetricPrints => 'Drucke';

  @override
  String get statsMetricTime => 'Zeit';

  @override
  String get statsFailureAnalysis => 'Fehleranalyse';

  @override
  String get statsFailureRate => 'Fehlerrate';

  @override
  String statsFailurePeriod(int days) {
    return 'Letzte $days Tage';
  }

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total Drucke fehlgeschlagen';
  }

  @override
  String get statsTopFailureReasons => 'Häufigste Fehlerursachen';

  @override
  String get statsNoFailures => 'Keine Fehler in diesem Zeitraum';

  @override
  String get statsPrintActivity => 'Druckaktivität';

  @override
  String get statsHeatmapLess => 'Weniger';

  @override
  String get statsHeatmapMore => 'Mehr';

  @override
  String get statsRecords => 'Rekorde';

  @override
  String get statsLongestPrint => 'Längster Druck';

  @override
  String get statsHeaviestPrint => 'Schwerster Druck';

  @override
  String get statsMostExpensive => 'Teuerster Druck';

  @override
  String get statsBusiestDay => 'Aktivster Tag';

  @override
  String get statsSuccessStreak => 'Erfolgsserie';

  @override
  String statsConsecutive(int count) {
    return '$count in Folge';
  }

  @override
  String get statsFilamentTrends => 'Filament-Trends';

  @override
  String get statsPeriodFilament => 'Filament im Zeitraum';

  @override
  String get statsPeriodCost => 'Kosten im Zeitraum';

  @override
  String get statsAvgPerPrint => 'Durchschnitt pro Druck';

  @override
  String get statsUsageOverTime => 'Verbrauch im Zeitverlauf';

  @override
  String get statsEnergyOverTime => 'Energie im Zeitverlauf';

  @override
  String get statsMostEnergy => 'Höchster Energieverbrauch';

  @override
  String statsKwh(String value) {
    return '$value kWh';
  }

  @override
  String get statsByMaterialTitle => 'Nach Material';

  @override
  String get statsSuccessByMaterial => 'Erfolgsquote nach Material';

  @override
  String get statsColorDistribution => 'Farbverteilung';

  @override
  String get statsColorShareHint =>
      'Anteil des verbrauchten Filaments nach Gewicht';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Farben',
      one: 'Farbe',
    );
    return '$count $_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '+$count weitere';
  }

  @override
  String get statsPrintDuration => 'Druckdauer';

  @override
  String get statsPrintHabits => 'Druckgewohnheiten';

  @override
  String get statsPrintTimeOfDay => 'Drucke nach Tageszeit';

  @override
  String get aboutMenu => 'Über';

  @override
  String get aboutTitle => 'Über';

  @override
  String get aboutTagline =>
      'Nativer Android-Client für Bambuddy – ein selbstgehosteter Manager für Bambu-Lab-Drucker.';

  @override
  String appVersionLabel(String version) {
    return 'App $version';
  }

  @override
  String serverVersionLabel(String version) {
    return 'Server $version';
  }

  @override
  String get serverVersionUnknown => 'Serverversion unbekannt';

  @override
  String get aboutLicenseHeader => 'Lizenz';

  @override
  String get aboutLicenseBody =>
      'Bambuddy ist freie Software, die unter der GNU Affero General Public License v3.0 (AGPL-3.0) veröffentlicht wurde. Du kannst sie nutzen, untersuchen, weitergeben und modifizieren; wenn du eine modifizierte Version als Netzwerkdienst betreibst, musst du deren Quellcode den Benutzern zur Verfügung stellen.';

  @override
  String get aboutViewLicense => 'AGPL-3.0-Lizenz lesen';

  @override
  String get aboutSourceHeader => 'Quellcode';

  @override
  String get aboutSourceBody =>
      'Der vollständige Quellcode ist auf GitHub verfügbar.';

  @override
  String get aboutSourceLink => 'Open-Source-Repository';

  @override
  String get aboutThirdParty => 'Open-Source-Lizenzen';

  @override
  String get aboutThirdPartySubtitle => 'Lizenzen der verwendeten Bibliotheken';

  @override
  String get aboutOpenLinkError => 'Link konnte nicht geöffnet werden';

  @override
  String get fileManagerMenu => 'Dateimanager';

  @override
  String get fileManagerTitle => 'Dateimanager';

  @override
  String get fmRoot => 'Alle Dateien';

  @override
  String get fmSearchHint => 'Dateien suchen…';

  @override
  String get fmEmpty => 'Dieser Ordner ist leer';

  @override
  String get fmNoMatches => 'Keine Dateien entsprechen deinen Filtern';

  @override
  String get fmSortBy => 'Sortieren nach';

  @override
  String get fmSortDateNewest => 'Neueste zuerst';

  @override
  String get fmSortDateOldest => 'Älteste zuerst';

  @override
  String get fmSortNameAZ => 'Name A–Z';

  @override
  String get fmSortNameZA => 'Name Z–A';

  @override
  String get fmSortSizeLargest => 'Größte zuerst';

  @override
  String get fmSortSizeSmallest => 'Kleinste zuerst';

  @override
  String get fmFilterType => 'Dateityp';

  @override
  String get fmAllTypes => 'Alle Typen';

  @override
  String get fmNewFolder => 'Neuer Ordner';

  @override
  String get fmFolderName => 'Ordnername';

  @override
  String get fmFileName => 'Dateiname';

  @override
  String get fmSave => 'Speichern';

  @override
  String get fmRename => 'Umbenennen';

  @override
  String get fmRenameFolder => 'Ordner umbenennen';

  @override
  String get fmRenameFile => 'Datei umbenennen';

  @override
  String get fmRenamed => 'Umbenannt';

  @override
  String get fmFolderCreated => 'Ordner erstellt';

  @override
  String get fmDelete => 'Löschen';

  @override
  String get fmDeleted => 'In den Papierkorb verschoben';

  @override
  String get fmDeleteFile => 'Datei löschen';

  @override
  String fmDeleteFileConfirm(String name) {
    return '„$name“ in den Papierkorb verschieben?';
  }

  @override
  String get fmDeleteFolder => 'Ordner löschen';

  @override
  String fmDeleteFolderConfirm(String name) {
    return 'Ordner „$name“ und seinen gesamten Inhalt löschen?';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return '$count $_temp0 in den Papierkorb verschieben?';
  }

  @override
  String get fmMoveTo => 'Verschieben nach…';

  @override
  String get fmMoved => 'Verschoben';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Elemente',
      one: 'Element',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => 'Drucken';

  @override
  String get fmAddToQueue => 'Zur Warteschlange hinzufügen';

  @override
  String get fmAddedToQueue => 'Zur Warteschlange hinzugefügt';

  @override
  String get fmGroupAsVariants => 'Als Alternativen gruppieren';

  @override
  String get fmQueueAsVariants => 'Als einen Auftrag einreihen';

  @override
  String get fmUngroupVariants => 'Alternativen auflösen';

  @override
  String fmVariantsGrouped(int count) {
    return '$count Dateien als Alternativen gruppiert';
  }

  @override
  String get fmVariantsUngrouped => 'Alternativen aufgelöst';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count Alternativen';
  }

  @override
  String get fmVariantsGone => 'Diese Gruppe existiert nicht mehr';

  @override
  String get fmUpload => 'Datei hochladen';

  @override
  String get fmUploading => 'Wird hochgeladen…';

  @override
  String fmUploaded(String name) {
    return '$name hochgeladen';
  }

  @override
  String get fmUploadFailed => 'Upload fehlgeschlagen';

  @override
  String fmSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ordner',
      one: 'Ordner',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '$size frei';
  }

  @override
  String get fmTrash => 'Papierkorb';

  @override
  String get fmTrashTitle => 'Papierkorb';

  @override
  String get fmTrashEmpty => 'Papierkorb ist leer';

  @override
  String get fmRestore => 'Wiederherstellen';

  @override
  String get fmRestored => 'Wiederhergestellt';

  @override
  String get fmEmptyTrash => 'Papierkorb leeren';

  @override
  String get fmEmptyTrashConfirm =>
      'Alle Dateien im Papierkorb endgültig löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get fmHardDelete => 'Endgültig löschen';

  @override
  String fmHardDeleteConfirm(String name) {
    return '„$name“ endgültig löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get fmDeletedForever => 'Endgültig gelöscht';

  @override
  String get fmTags => 'Tags';

  @override
  String get fmTagsFilterTitle => 'Nach Tags filtern';

  @override
  String get fmTagsFilterHint =>
      'Tags durchsuchen die gesamte Bibliothek – der aktuelle Ordner wird ignoriert.';

  @override
  String get fmTagsManage => 'Tags verwalten';

  @override
  String get fmTagsEmpty => 'Noch keine Tags';

  @override
  String get fmTagsNone => 'Keine Tags';

  @override
  String get fmTagsApply => 'Anwenden';

  @override
  String get fmTagNew => 'Neuer Tag';

  @override
  String get fmTagName => 'Tag-Name';

  @override
  String get fmTagRename => 'Tag umbenennen';

  @override
  String get fmTagDelete => 'Tag löschen';

  @override
  String fmTagDeleteConfirm(String name) {
    return 'Tag „$name“ löschen? Die Dateien behalten alles andere – sie verlieren nur diesen Tag.';
  }

  @override
  String get fmTagCreated => 'Tag erstellt';

  @override
  String get fmTagDeleted => 'Tag gelöscht';

  @override
  String get fmTagExists => 'Ein Tag mit diesem Namen existiert bereits';

  @override
  String get fmTagsSaved => 'Tags aktualisiert';

  @override
  String fmTagsPartial(int count, int total) {
    return '$count von $total Dateien aktualisiert – die restlichen darfst du nicht bearbeiten';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return '$count $_temp0 taggen';
  }

  @override
  String get fmTagsAdd => 'Hinzufügen';

  @override
  String get fmTagsRemove => 'Entfernen';

  @override
  String get fmTagsReplace => 'Ersetzen';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return 'Alle Tags bei $count $_temp0 durch die ausgewählten ersetzen?';
  }

  @override
  String get fmTagsPickSome => 'Wähle mindestens einen Tag aus';

  @override
  String get makerworldMenu => 'MakerWorld';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get mwIntro =>
      'Füge eine MakerWorld-Modell-URL ein, um es direkt aus Bambuddy zu importieren und zu drucken.';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/en/models/… oder ein beliebiger MakerWorld-Link';

  @override
  String get mwResolve => 'Abrufen';

  @override
  String get mwEnterUrl => 'Gib eine MakerWorld-URL ein';

  @override
  String get mwUntitledModel => 'Unbenanntes Modell';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Druckplatten',
      one: '1 Druckplatte',
      zero: 'Keine Druckplatten',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => 'Keine Druckplatten für dieses Modell gefunden.';

  @override
  String get mwImport => 'Importieren';

  @override
  String mwShowAllPlates(int count) {
    return 'Alle $count Druckplatten anzeigen';
  }

  @override
  String get mwShowLess => 'Weniger anzeigen';

  @override
  String get mwInLibrary => 'In der Bibliothek';

  @override
  String get mwImported => 'In deine Bibliothek importiert';

  @override
  String get mwAlreadyInLibrary => 'Bereits in deiner Bibliothek';

  @override
  String get mwViewInFiles => 'Im Dateimanager anzeigen';

  @override
  String get mwRecentImports => 'Kürzlich importiert';

  @override
  String get mwNoRecent => 'Noch keine kürzlichen Importe';

  @override
  String get mwOpenOnMakerworld => 'Auf MakerWorld öffnen';

  @override
  String get mwLoginRequired =>
      'Melde dich bei deinem Bambu-Cloud-Konto an, um MakerWorld-Modelle herunterzuladen.';

  @override
  String get cloudAccountMenu => 'Bambu-Cloud-Konto';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote =>
      'Melde dich mit deinem Bambu-Lab-Konto an. Diese Zugangsdaten werden nur zum Herunterladen von Modellen von MakerWorld verwendet.';

  @override
  String get cloudEmail => 'E-Mail';

  @override
  String get cloudPassword => 'Passwort';

  @override
  String get cloudRegionGlobal => 'Global';

  @override
  String get cloudRegionChina => 'China';

  @override
  String get cloudSignIn => 'Anmelden';

  @override
  String get cloudSignOut => 'Abmelden';

  @override
  String get cloudSignedIn => 'Angemeldet';

  @override
  String get cloudSignedInOk => 'Bei Bambu Cloud angemeldet';

  @override
  String get cloudSignInFailed => 'Anmeldung fehlgeschlagen';

  @override
  String get cloudFillCredentials =>
      'Gib deine E-Mail-Adresse und dein Passwort ein';

  @override
  String get cloudVerify => 'Bestätigen';

  @override
  String get cloudVerificationCode => 'Bestätigungscode';

  @override
  String get cloudVerificationPrompt =>
      'Gib den Bestätigungscode ein, um die Anmeldung abzuschließen.';

  @override
  String get cloudEnterCode => 'Gib den Bestätigungscode ein';

  @override
  String get swatchCodesMenu => 'Farbmuster-Codes';

  @override
  String get swatchCodesTitle => 'Farbmuster-Codes';

  @override
  String get swatchSearchHint => 'Nach Code oder Name suchen';

  @override
  String get swatchSectionCodes => 'Codes';

  @override
  String get swatchSectionUncoded => 'Filamente im Bestand ohne Code';

  @override
  String get swatchNoCodes => 'Noch keine Farbmuster-Codes';

  @override
  String get swatchNoCodesHint =>
      'Erstelle einen Code, um ein Filament-Farbmuster zu kennzeichnen.';

  @override
  String swatchNoMatch(String query) {
    return 'Keine Codes entsprechen „$query“';
  }

  @override
  String get swatchAllCoded => 'Alle Filamente im Bestand haben einen Code';

  @override
  String get swatchNewCode => 'Neuer Code';

  @override
  String get swatchGenerate => 'Generieren';

  @override
  String get swatchGenerateCode => 'Code generieren';

  @override
  String get swatchExists => 'Dieses Filament hat bereits einen Code';

  @override
  String swatchCreatedSnack(String code) {
    return 'Code $code erstellt';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return 'Code $code aktualisiert';
  }

  @override
  String swatchCopied(String code) {
    return '$code kopiert';
  }

  @override
  String get swatchDelete => 'Löschen';

  @override
  String get swatchDeleteTitle => 'Code löschen?';

  @override
  String swatchDeleteBody(String code, String name) {
    return 'Code $code für $name wird entfernt.';
  }

  @override
  String get swatchExport => 'Exportieren';

  @override
  String get swatchImport => 'Importieren';

  @override
  String get swatchExportEmpty => 'Keine Codes zum Exportieren vorhanden';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Codes',
      one: '1 Code',
    );
    return '$_temp0 exportiert';
  }

  @override
  String get swatchExportFailed => 'Export fehlgeschlagen';

  @override
  String get swatchImportTitle => 'Codes importieren?';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return 'Dadurch werden alle $existing vorhandenen Codes durch $incoming Codes aus der Datei ersetzt. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get swatchImportConfirm => 'Alle ersetzen';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Codes',
      one: '1 Code',
    );
    return '$_temp0 importiert';
  }

  @override
  String get swatchImportFailed => 'Datei konnte nicht gelesen werden';

  @override
  String get swatchImportEmpty => 'Keine Codes in der Datei gefunden';

  @override
  String get swatchFormTitle => 'Neuer Farbmuster-Code';

  @override
  String get swatchEditTitle => 'Code bearbeiten';

  @override
  String get swatchSave => 'Speichern';

  @override
  String get swatchRegenerate => 'Neu generieren';

  @override
  String get swatchFieldCode => 'Code';

  @override
  String get swatchCodeInvalid =>
      'Verwende 6 Zeichen: Ziffern und Buchstaben, ohne 0, 1, I, L oder O';

  @override
  String get swatchCodeTaken => 'Dieser Code wird bereits verwendet';

  @override
  String get swatchFieldBrand => 'Hersteller';

  @override
  String get swatchFieldMaterial => 'Material';

  @override
  String get swatchFieldVariant => 'Variante';

  @override
  String get swatchFieldColor => 'Farbe';

  @override
  String get swatchFieldHex => 'Hex-Farbcode';

  @override
  String get swatchMaterialRequired => 'Material ist erforderlich';

  @override
  String get swatchNoCatalogColors =>
      'Keine Katalogfarben verfügbar. Gib Farbnamen und Hex-Code manuell ein.';

  @override
  String get projectsMenu => 'Projekte';

  @override
  String get projectsTitle => 'Projekte';

  @override
  String get projectsEmpty => 'Noch keine Projekte';

  @override
  String get projectsFilterAll => 'Alle';

  @override
  String get projectCreate => 'Neues Projekt';

  @override
  String get projectEdit => 'Projekt bearbeiten';

  @override
  String get projectDelete => 'Löschen';

  @override
  String get projectDeleteTitle => 'Projekt löschen?';

  @override
  String projectDeleteBody(String name) {
    return '„$name“ wird entfernt. Verknüpfte Drucke bleiben im Archiv erhalten.';
  }

  @override
  String get projectDeleted => 'Projekt gelöscht';

  @override
  String get projectDeleteFailed => 'Projekt konnte nicht gelöscht werden';

  @override
  String get projectSaved => 'Projekt gespeichert';

  @override
  String get projectName => 'Name';

  @override
  String get projectNameRequired => 'Name ist erforderlich';

  @override
  String get projectDescription => 'Beschreibung';

  @override
  String get projectNotes => 'Notizen';

  @override
  String get projectStatus => 'Status';

  @override
  String get projectPriority => 'Priorität';

  @override
  String get projectColor => 'Farbe';

  @override
  String get projectDueDate => 'Fälligkeitsdatum';

  @override
  String get projectDueDateClear => 'Löschen';

  @override
  String get projectBudget => 'Budget';

  @override
  String get projectTargetCount => 'Ziel-Druckplatten';

  @override
  String get projectTargetPartsCount => 'Ziel-Teile';

  @override
  String get projectTargetSets => 'Ziel-Sets';

  @override
  String get projectTargetSetsHint =>
      'Wie oft jede Datei im Projekt gedruckt werden soll';

  @override
  String get projectTags => 'Tags (kommagetrennt)';

  @override
  String get projectUrl => 'Link';

  @override
  String get projectParent => 'Übergeordnetes Projekt';

  @override
  String get projectParentNone => 'Keines';

  @override
  String get projectSave => 'Speichern';

  @override
  String get projectStatusPlanning => 'Planung';

  @override
  String get projectStatusActive => 'Aktiv';

  @override
  String get projectStatusOnHold => 'Pausiert';

  @override
  String get projectStatusCompleted => 'Abgeschlossen';

  @override
  String get projectStatusArchived => 'Archiviert';

  @override
  String get projectPriorityLow => 'Niedrig';

  @override
  String get projectPriorityNormal => 'Normal';

  @override
  String get projectPriorityHigh => 'Hoch';

  @override
  String get projectPriorityUrgent => 'Dringend';

  @override
  String get projectTabOverview => 'Übersicht';

  @override
  String get projectTabArchives => 'Archive';

  @override
  String get projectTabBom => 'BOM';

  @override
  String get projectTabQueue => 'Warteschlange';

  @override
  String get projectTabTimeline => 'Zeitleiste';

  @override
  String get projectTabFiles => 'Dateien';

  @override
  String get projectTabAttachments => 'Anhänge';

  @override
  String get projectStatsTitle => 'Statistiken';

  @override
  String get projectStatProgress => 'Fortschritt';

  @override
  String get projectStatPartsProgress => 'Teile';

  @override
  String get projectStatSets => 'Vollständige Sets';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done von $target';
  }

  @override
  String get projectStatPrints => 'Druckplatten';

  @override
  String get projectStatCompleted => 'Abgeschlossen';

  @override
  String get projectStatFailed => 'Fehlgeschlagen';

  @override
  String get projectStatQueued => 'In Warteschlange';

  @override
  String get projectStatInProgress => 'In Bearbeitung';

  @override
  String get projectStatPrintTime => 'Druckzeit';

  @override
  String get projectStatFilament => 'Filament';

  @override
  String get projectStatCost => 'Geschätzte Kosten';

  @override
  String get projectStatEnergy => 'Energie';

  @override
  String get projectStatEnergyCost => 'Energiekosten';

  @override
  String get projectStatRemaining => 'Verbleibend';

  @override
  String get projectStatBom => 'BOM';

  @override
  String get projectChildren => 'Unterprojekte';

  @override
  String get projectNoDescription => 'Keine Beschreibung';

  @override
  String projectDueOn(String date) {
    return 'Fällig am $date';
  }

  @override
  String get projectAddArchives => 'Archive hinzufügen';

  @override
  String get projectRemoveArchive => 'Aus Projekt entfernen';

  @override
  String get projectArchivesEmpty => 'Keine Archive verknüpft';

  @override
  String get projectArchiveRemoved => 'Aus Projekt entfernt';

  @override
  String get archiveAddToProject => 'Zum Projekt hinzufügen';

  @override
  String get projectArchivesAdded => 'Zum Projekt hinzugefügt';

  @override
  String get projectPickTitle => 'Projekt auswählen';

  @override
  String get projectBomEmpty => 'Keine BOM-Einträge';

  @override
  String get bomAdd => 'Eintrag hinzufügen';

  @override
  String get bomEditTitle => 'Eintrag bearbeiten';

  @override
  String get bomAddTitle => 'Neuer Eintrag';

  @override
  String get bomName => 'Name';

  @override
  String get bomQtyNeeded => 'Menge';

  @override
  String get bomQtyAcquired => 'Beschafft';

  @override
  String get bomUnitPrice => 'Stückpreis';

  @override
  String get bomSourcingUrl => 'Bezugsquellen-URL';

  @override
  String get bomRemarks => 'Bemerkungen';

  @override
  String get bomComplete => 'Vollständig';

  @override
  String get bomDelete => 'Eintrag löschen';

  @override
  String get bomDeleted => 'Eintrag gelöscht';

  @override
  String get projectQueueEmpty => 'Keine Einträge in der Warteschlange';

  @override
  String get projectTimelineEmpty => 'Noch keine Ereignisse';

  @override
  String get projectAttachmentsEmpty => 'Keine Anhänge';

  @override
  String get projectFilesEmpty => 'Keine druckbaren Dateien';

  @override
  String get projectAttachmentUpload => 'Datei hochladen';

  @override
  String get projectAttachmentDownload => 'Herunterladen';

  @override
  String get projectAttachmentDelete => 'Löschen';

  @override
  String get projectAttachmentDeleted => 'Anhang gelöscht';

  @override
  String get projectAttachmentUploaded => 'Anhang hochgeladen';

  @override
  String projectFileSaved(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get projectDownloadFailed => 'Download fehlgeschlagen';

  @override
  String get projectCoverUpload => 'Titelbild festlegen';

  @override
  String get projectCoverDelete => 'Titelbild entfernen';

  @override
  String get projectCoverUpdated => 'Titelbild aktualisiert';

  @override
  String get projectCoverRemoved => 'Titelbild entfernt';

  @override
  String get projectMenuExport => 'Exportieren';

  @override
  String get projectMenuCreateTemplate => 'Als Vorlage speichern';

  @override
  String get projectMenuImport => 'Projekt importieren';

  @override
  String get projectFromTemplate => 'Aus Vorlage erstellen';

  @override
  String get projectTemplateNone => 'Keine Vorlagen';

  @override
  String get projectTemplatePickTitle => 'Vorlage auswählen';

  @override
  String get projectTemplateNamePrompt => 'Neuer Projektname';

  @override
  String projectExported(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String get projectExportFailed => 'Export fehlgeschlagen';

  @override
  String get projectTemplateCreated => 'Vorlage erstellt';

  @override
  String get projectImported => 'Projekt importiert';

  @override
  String get projectImportFailed => 'Import fehlgeschlagen';

  @override
  String get projectUploading => 'Wird hochgeladen…';

  @override
  String get projectLinkFolder => 'Ordner verknüpfen';

  @override
  String get projectNoFoldersToLink => 'Keine Ordner zum Verknüpfen verfügbar';

  @override
  String get projectUnlinkFolder => 'Ordner trennen';

  @override
  String get projectFolderLinked => 'Ordner verknüpft';

  @override
  String get projectFolderUnlinked => 'Ordner getrennt';

  @override
  String get projectNotesEmpty => 'Noch keine Notizen';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '$count Datei',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    return '$count übrig';
  }

  @override
  String get sliceAction => 'Slicen';

  @override
  String get sliceTitle => 'Datei slicen';

  @override
  String get slicePrinter => 'Drucker';

  @override
  String get sliceProcess => 'Prozess / Qualität';

  @override
  String get sliceBedType => 'Druckplatte';

  @override
  String get sliceBedDefault => 'Standard (aus Profil)';

  @override
  String get sliceFilament => 'Filament';

  @override
  String sliceFilamentNumbered(String n) {
    return 'Filament $n';
  }

  @override
  String get sliceAutoOrient => 'Automatisch ausrichten';

  @override
  String get sliceAutoOrientHint =>
      'Dreht jedes Objekt auf seine beste Druckseite.';

  @override
  String get sliceAutoArrange => 'Automatisch anordnen';

  @override
  String get sliceAutoArrangeHint =>
      'Platziert die Objekte erneut auf der Druckplatte.';

  @override
  String sliceDesignedFor(String printer) {
    return 'Diese Datei ist für $printer';
  }

  @override
  String get sliceUseDesignedPrinter => 'Wechseln';

  @override
  String get sliceAsDesigned => 'Dateieigene Einstellungen verwenden';

  @override
  String get sliceAsDesignedHint =>
      'Die Einstellungen des Erstellers anstelle der obigen Profile.';

  @override
  String get sliceAsDesignedInactive =>
      'Nicht verwendet — die Datei entscheidet';

  @override
  String get sliceFilamentUnused => 'Auf dieser Druckplatte nicht verwendet';

  @override
  String get processSettingsTitle => 'Prozesseinstellungen';

  @override
  String get sliceProcessSettingsNeedsProcess =>
      'Zuerst ein Prozessprofil auswählen';

  @override
  String get sliceProcessSettingsUnchanged => 'Profil unverändert verwenden';

  @override
  String sliceProcessSettingsChanged(int count) {
    return '$count geändert';
  }

  @override
  String get processSettingsModeSimple => 'Einfach';

  @override
  String get processSettingsModeAdvanced => 'Erweitert';

  @override
  String get processSettingsModeExpert => 'Experte';

  @override
  String get processSettingsSearchHint => 'Einstellungen suchen';

  @override
  String get processSettingsNoMatches =>
      'Keine Einstellungen entsprechen dieser Suche.';

  @override
  String get processSettingsRevert => 'Auf Profilwert zurücksetzen';

  @override
  String processSettingsRevertAll(int count) {
    return '$count zurücksetzen';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return 'Der Slicer akzeptiert $range';
  }

  @override
  String get processSettingsDisabledHint =>
      'Der Slicer ignoriert dies bei deinen aktuellen Einstellungen.';

  @override
  String get processSettingsUnavailable =>
      'Dieser Server kann keine Prozesseinstellungen für das ausgewählte Profil abrufen.';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      'Slicer-Standardwerte werden angezeigt: Dein Slicer-Sidecar ist älter als diese Funktion und kann die Werte eines Profils nicht auslesen. Aktualisiere das Sidecar-Image, um sie zu sehen. Alles, was du nicht änderst, verwendet weiterhin das Profil.';

  @override
  String get processSettingsDefaultsNotConfigured =>
      'Slicer-Standardwerte werden angezeigt: Es ist kein Slicer-Sidecar konfiguriert, daher können die Werte eines Profils nicht ausgelesen werden. Alles, was du nicht änderst, verwendet weiterhin das Profil.';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      'Slicer-Standardwerte werden angezeigt: Das Slicer-Sidecar hat nicht geantwortet, daher können die Werte eines Profils nicht ausgelesen werden. Alles, was du nicht änderst, verwendet weiterhin das Profil.';

  @override
  String get processSettingsDefaultsUnavailable =>
      'Slicer-Standardwerte werden angezeigt: Die Werte des ausgewählten Profils konnten nicht ausgelesen werden. Alles, was du nicht änderst, verwendet weiterhin das Profil.';

  @override
  String get processSettingsFilamentDefault =>
      'Standard (Filament des jeweiligen Bereichs)';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot: $name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return 'Slot $slot — diese Datei hat keinen solchen Slot';
  }

  @override
  String get sliceSelect => 'Zum Auswählen tippen';

  @override
  String get sliceStart => 'Slicen';

  @override
  String get sliceShowAll => 'Alle';

  @override
  String get sliceSearchHint => 'Profile suchen';

  @override
  String get sliceOwnedEmpty =>
      'Keine passenden Profile für deinen Drucker und deine Filamente. Aktiviere „Alle“, um den gesamten Katalog zu durchsuchen.';

  @override
  String get sliceNoPresets => 'Keine Profile verfügbar';

  @override
  String get sliceInProgress => 'Wird geslict…';

  @override
  String get sliceDone => 'Slicing abgeschlossen';

  @override
  String get sliceFailed => 'Slicing fehlgeschlagen';

  @override
  String get sliceExternalFallback =>
      'In der Server-Bibliothek gespeichert — der Ordner der Datei konnte sie nicht aufnehmen.';

  @override
  String get sliceExternalReadonly => 'Dieser Ordner ist schreibgeschützt.';

  @override
  String get sliceExternalNoPath =>
      'Für diesen Ordner ist kein Pfad konfiguriert.';

  @override
  String get sliceExternalUnreachable =>
      'Der Pfad dieses Ordners ist derzeit nicht erreichbar.';

  @override
  String get sliceExternalNotWritable =>
      'Der Server kann nicht in diesen Ordner schreiben.';

  @override
  String get sliceExternalInvalidName =>
      'Dieser Ordner akzeptiert den Dateinamen nicht.';

  @override
  String get sliceClose => 'Schließen';

  @override
  String sliceResultTime(String time) {
    return 'Geschätzte Zeit: $time';
  }

  @override
  String get sliceRefusedStep =>
      'STEP-Dateien können nicht geslict werden. Exportiere das Modell zuerst aus deinem CAD als STL oder 3MF.';

  @override
  String get sliceRefusedFormat =>
      'Die Quelldatei muss ein STL oder ein 3MF sein.';

  @override
  String get sliceRefusedNoSource =>
      'Dieses Archiv enthält nur den gedruckten G-Code, nicht das Modell — es gibt nichts, was erneut geslict werden könnte.';

  @override
  String sliceResultFilament(String grams) {
    return 'Filament: $grams g';
  }

  @override
  String get sliceTierLocal => 'Lokales Profil';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => 'Integriert';

  @override
  String get pipelineSection => 'Pipeline';

  @override
  String get pipelineApply => 'Pipeline anwenden…';

  @override
  String get pipelineApplyEmpty => 'Keine gespeicherten Pipelines';

  @override
  String pipelineApplied(String name) {
    return '„$name“ angewendet';
  }

  @override
  String get pipelineSaveAs => 'Als Pipeline speichern';

  @override
  String get pipelineNameHint => 'Pipeline-Name';

  @override
  String get pipelineSaveConfirm => 'Speichern';

  @override
  String get pipelineSaved => 'Pipeline gespeichert';

  @override
  String get pipelineSaveHint =>
      'Drucker, Prozess, Filamente und Druckplatte von oben unter einem Namen, den du auf die nächste Datei anwenden kannst.';

  @override
  String get pipelinesMenu => 'Pipelines';

  @override
  String get pipelinesTitle => 'Pipelines';

  @override
  String get pipelinesEmpty => 'Noch keine Pipelines';

  @override
  String get pipelinesEmptyHint =>
      'Speichere eine aus dem Slicing-Formular — Drucker, Prozess, Filamente und Druckplatte als Paket, das du mit einem Fingertipp anwenden kannst.';

  @override
  String get pipelineProfiles => 'Profile';

  @override
  String pipelineFilamentsCount(int count) {
    return 'Filamente ($count)';
  }

  @override
  String get pipelineHistory => 'Ausführungsverlauf';

  @override
  String get pipelineCardActions => 'Pipeline-Aktionen';

  @override
  String pipelineSlotNumbered(int n) {
    return 'Filament $n';
  }

  @override
  String get pipelineBed => 'Druckplatte';

  @override
  String get pipelinePresetGone => 'Nicht mehr im Katalog vorhanden';

  @override
  String get pipelineNeedsTarget =>
      'Lege ein Ziel fest, bevor du diese Pipeline ausführst.';

  @override
  String get pipelineNoTargetChip => 'Kein Ziel';

  @override
  String get pipelineEditTitle => 'Pipeline bearbeiten';

  @override
  String get pipelineDescriptionHint => 'Beschreibung (optional)';

  @override
  String get pipelineTargetType => 'Ziel';

  @override
  String get pipelineTargetSpecific => 'Bestimmter Drucker';

  @override
  String get pipelineTargetClass => 'Druckermodell';

  @override
  String get pipelineTargetPickPrinter => 'Drucker auswählen';

  @override
  String get pipelineTargetPickClass => 'Modell auswählen';

  @override
  String get pipelineTargetNone => '— kein Ziel —';

  @override
  String pipelineTargetPrinterGone(int id) {
    return 'Drucker #$id (nicht mehr vorhanden)';
  }

  @override
  String get pipelineFanout => 'Verteilung der Kopien';

  @override
  String get pipelineFanoutMaxParallel =>
      'Maximal parallel — auf jedem freien passenden Drucker';

  @override
  String get pipelineFanoutRoundRobin =>
      'Round-Robin — reihum auf geeigneten Druckern';

  @override
  String get pipelineFanoutFillOneFirst =>
      'Einen zuerst füllen — alle Kopien auf einem Drucker';

  @override
  String get pipelineDelete => 'Pipeline löschen';

  @override
  String pipelineDeleteConfirm(String name) {
    return '„$name“ löschen? Bereits erfolgte Durchläufe behalten ihren Namen.';
  }

  @override
  String get pipelineDeleted => 'Pipeline gelöscht';

  @override
  String get pipelineDescriptionNoClear =>
      'Eine einmal gespeicherte Beschreibung kann nicht geleert werden — dieser Server überschreibt sie nur mit einer neuen.';

  @override
  String get pipelineRun => 'Ausführen';

  @override
  String pipelineRunTitle(String name) {
    return '„$name“ ausführen';
  }

  @override
  String get pipelineRunCopies => 'Kopien';

  @override
  String get pipelineRunStart => 'Starten';

  @override
  String get pipelineRunStarted => 'Durchlauf gestartet';

  @override
  String get pipelineRunAnyway => 'Trotzdem ausführen';

  @override
  String pipelineRunMaxCopies(int max) {
    return 'Dieser Server erlaubt maximal $max.';
  }

  @override
  String get pipelineCheckingEligibility => 'Drucker werden geprüft…';

  @override
  String get pipelineEligibilityOk => 'Bereit zur Ausführung.';

  @override
  String pipelineEligibilityClassCount(int ok, int total) {
    return '$ok von $total Druckern bereit';
  }

  @override
  String get pipelineEligibilityBlocked =>
      'Derzeit kann kein Drucker diesen Durchlauf übernehmen.';

  @override
  String get pipelineEligibilityAdvisory => 'Vor dem Start einen Blick wert.';

  @override
  String get pipelineIssuePrinterNotSet =>
      'Diese Pipeline hat keinen Zieldrucker.';

  @override
  String get pipelineIssuePrinterNotFound =>
      'Der Zieldrucker existiert nicht mehr.';

  @override
  String get pipelineIssuePrinterDisabled =>
      'Der Zieldrucker ist in bambuddy deaktiviert.';

  @override
  String get pipelineIssuePrinterOffline => 'Der Zieldrucker ist offline.';

  @override
  String get pipelineIssueFilamentType => 'Falscher Filamenttyp geladen.';

  @override
  String get pipelineIssueFilamentColor =>
      'Das geladene Filament hat eine andere Farbe.';

  @override
  String get pipelineIssueAmsSlotMissing =>
      'Das AMS hat weniger Slots, als diese Pipeline benötigt.';

  @override
  String get pipelineIssueFilamentUnverified =>
      'Dieses Filamentprofil kann von hier aus nicht geprüft werden — am besten selbst kontrollieren.';

  @override
  String get pipelineIssueNoClassMatches =>
      'Kein Drucker dieses Modells eingerichtet.';

  @override
  String get pipelineIssueClassNotSet =>
      'Für diese Pipeline ist kein Druckermodell festgelegt.';

  @override
  String pipelineIssueSlot(int n) {
    return 'Slot $n';
  }

  @override
  String pipelineIssueWantedGot(String expected, String actual) {
    return 'erwartet $expected, geladen $actual';
  }

  @override
  String pipelineIssueWanted(String expected) {
    return 'erwartet $expected';
  }

  @override
  String get pipelineRunsTitle => 'Pipeline-Durchläufe';

  @override
  String get pipelineRunsEmpty => 'Noch keine Durchläufe';

  @override
  String get pipelineRunsNoneMatch =>
      'Kein Durchlauf entspricht diesen Filtern';

  @override
  String get pipelineRunsFilter => 'Durchläufe filtern';

  @override
  String get pipelineCopiesLess => 'Eine Kopie weniger';

  @override
  String get pipelineCopiesMore => 'Eine Kopie mehr';

  @override
  String get pipelineEligible => 'Bereit';

  @override
  String get pipelineIneligible => 'Nicht bereit';

  @override
  String pipelineRunsFilterActive(int count) {
    return 'Durchläufe filtern ($count aktiv)';
  }

  @override
  String get pipelineRunsFilterAny => 'Beliebig';

  @override
  String get pipelineRunsFilterStatus => 'Status';

  @override
  String get pipelineRunsFilterStatusHint =>
      'Entspricht dem zuletzt erfassten Status, sodass ein Durchlauf noch dem Schritt vor seinem aktuellen entsprechen kann.';

  @override
  String get pipelineRunsFilterTarget => 'Ziel';

  @override
  String get pipelineRunsFilterTargetHint =>
      'Worauf die Pipeline aktuell zeigt — ein Zielwechsel verschiebt ihren gesamten Verlauf.';

  @override
  String get pipelineRunsFilterPipelineHint =>
      'Nach Durchläufen einer gelöschten Pipeline kann nicht gefiltert werden.';

  @override
  String get pipelineRunsFilterClear => 'Filter zurücksetzen';

  @override
  String get pipelineRunsLoadMore => 'Mehr laden';

  @override
  String pipelineRunsShowingAll(int count) {
    return 'Alle $count angezeigt';
  }

  @override
  String get pipelineRunsDone => 'Fertig';

  @override
  String get pipelineRunsClear => 'Abgeschlossene entfernen';

  @override
  String pipelineRunsCleared(int count) {
    return '$count entfernt';
  }

  @override
  String get pipelineRunsClearConfirm =>
      'Alle abgeschlossenen Durchläufe aus dieser Liste entfernen?';

  @override
  String pipelineRunCopiesProgress(int done, int total) {
    return '$done von $total Kopien';
  }

  @override
  String get pipelineRunCancel => 'Durchlauf abbrechen';

  @override
  String get pipelineRunCancelConfirm =>
      'Diesen Durchlauf abbrechen? Noch nicht gesendete Kopien werden verworfen; was bereits gedruckt wird, muss direkt am Drucker gestoppt werden.';

  @override
  String get pipelineRunCancelled => 'Durchlauf abgebrochen';

  @override
  String get pipelineRunRetry => 'Fehlgeschlagene wiederholen';

  @override
  String pipelineRunRetryStarted(int count) {
    return '$count Kopien werden wiederholt';
  }

  @override
  String get pipelineRunOverridden =>
      'Trotz fehlgeschlagener Prüfung gestartet';

  @override
  String get pipelineRunDeletedPipeline => 'Gelöschte Pipeline';

  @override
  String pipelineRunSource(String name) {
    return 'Von $name';
  }

  @override
  String pipelineRunRetryOf(int id) {
    return 'Wiederholung von Durchlauf #$id';
  }

  @override
  String pipelineRunOnPrinter(String printer) {
    return 'Auf $printer';
  }

  @override
  String pipelineRunOnClass(String model) {
    return 'Auf jedem $model';
  }

  @override
  String get pipelineStatusQueued => 'In Warteschlange';

  @override
  String get pipelineStatusSlicing => 'Slicing';

  @override
  String get pipelineStatusDispatching => 'Wird gesendet';

  @override
  String get pipelineStatusInProgress => 'Druckt';

  @override
  String get pipelineStatusCompleted => 'Abgeschlossen';

  @override
  String get pipelineStatusFailed => 'Fehlgeschlagen';

  @override
  String get pipelineStatusPartial => 'Teilweise fehlgeschlagen';

  @override
  String get pipelineStatusCancelled => 'Abgebrochen';

  @override
  String get pipelineStatusUnknown => 'Unbekannt';

  @override
  String pipelineJobCopy(int n) {
    return 'Kopie $n';
  }

  @override
  String get pipelineJobPending => 'Ausstehend';

  @override
  String get pipelineJobAwaitingPrinter => 'Wartet auf Drucker';

  @override
  String get pipelineJobQueued => 'In Warteschlange';

  @override
  String get pipelineJobPrinting => 'Druckt';

  @override
  String get pipelineJobCompleted => 'Fertig';

  @override
  String get pipelineJobFailed => 'Fehlgeschlagen';

  @override
  String get pipelineJobCancelled => 'Abgebrochen';

  @override
  String get pipelineJobUnknown => 'Unbekannt';

  @override
  String get queueFilamentMapping => 'Filament-Zuordnung';

  @override
  String get mappingNoPrinter =>
      'Weise diesem Eintrag zuerst einen Drucker zu, um dessen AMS-Slots zuzuordnen.';

  @override
  String get mappingNoSlots => 'Keine Filamentinformationen für diese Datei.';

  @override
  String mappingNoAms(String printer) {
    return 'Keine AMS-Filamente auf $printer geladen.';
  }

  @override
  String get mappingPickTray => 'AMS-Slot auswählen';

  @override
  String get mappingExternalSpool => 'Externe Spule';

  @override
  String mappingAmsSlot(String unit, String slot) {
    return 'AMS $unit · Slot $slot';
  }

  @override
  String get mappingSaved => 'Filament-Zuordnung gespeichert';

  @override
  String get plateClearTitle => 'Ist die Druckplatte frei?';

  @override
  String get plateClearBody =>
      'Stelle sicher, dass die Druckplatte leer ist, bevor du diesen Druck startest.';

  @override
  String get plateClearConfirm => 'Druckplatte ist frei';

  @override
  String get plateClearAction => 'Druckplatte als frei markieren';

  @override
  String get plateClearBadge => 'Druckplatte nicht frei';

  @override
  String get plateClearedSnack => 'Druckplatte als frei markiert';

  @override
  String get plateClearNeedsOnline =>
      'Dieser Server gibt die Druckplatte nur frei, solange der Drucker verbunden ist. Aktualisiere bambuddy, um dies bei einem ausgeschalteten Drucker zu tun.';

  @override
  String get pfmTitle => 'Dateimanager';

  @override
  String get pfmTooltip => 'Dateien auf dem Drucker';

  @override
  String pfmStorageUsed(String size) {
    return 'Belegt: $size';
  }

  @override
  String get pfmTabRoot => 'Root';

  @override
  String get pfmTabCache => 'Cache';

  @override
  String get pfmTabModels => 'Modelle';

  @override
  String get pfmTabTimelapse => 'Zeitraffer';

  @override
  String get pfmSearchHint => 'Dateien filtern…';

  @override
  String get pfmSortTooltip => 'Sortieren';

  @override
  String get pfmRefreshTooltip => 'Aktualisieren';

  @override
  String get pfmSortNameAsc => 'Name (A–Z)';

  @override
  String get pfmSortNameDesc => 'Name (Z–A)';

  @override
  String get pfmSortSizeLargest => 'Größe (größte zuerst)';

  @override
  String get pfmSortSizeSmallest => 'Größe (kleinste zuerst)';

  @override
  String get pfmSortDateNewest => 'Datum (neueste zuerst)';

  @override
  String get pfmSortDateOldest => 'Datum (älteste zuerst)';

  @override
  String get pfmUp => 'Einen Ordner nach oben';

  @override
  String get pfmSelectAll => 'Alle auswählen';

  @override
  String get pfmDeselectAll => 'Auswahl aufheben';

  @override
  String pfmSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get pfmEmpty => 'Dieser Ordner ist leer';

  @override
  String get pfmNoMatches => 'Keine Dateien entsprechen deinem Filter';

  @override
  String get pfmPrinterUnavailable =>
      'Der Drucker hat nicht geantwortet, daher konnten seine Dateien nicht aufgelistet werden';

  @override
  String get pfmDownloadTooLarge =>
      'Die Auswahl ist zu groß, um vom Server gebündelt zu werden';

  @override
  String get pfmDownloadNoServerSpace =>
      'Der Server hat keinen Speicherplatz, um diesen Download vorzubereiten';

  @override
  String get pfmDownloadTookTooLong =>
      'Die Vorbereitung des Downloads hat zu lange gedauert und der Server hat abgebrochen';

  @override
  String get pfmPreparingOnServer => 'Wird auf dem Server vorbereitet…';

  @override
  String get pfmDownloading => 'Wird heruntergeladen…';

  @override
  String get pfmDownloadCancelled => 'Download abgebrochen';

  @override
  String get pfmDownloadPrepareFailed =>
      'Der Server konnte diesen Download nicht vorbereiten';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Dateien wurden ausgelassen, da sie nicht vom Drucker gelesen werden konnten',
      one:
          'Eine Datei wurde ausgelassen, da sie nicht vom Drucker gelesen werden konnte',
    );
    return '$_temp0';
  }

  @override
  String get pfmDownloadSaved => 'Datei gespeichert';

  @override
  String get pfmDownloadNotSaved =>
      'Die Datei konnte am ausgewählten Ort nicht gespeichert werden';

  @override
  String get pfmDownload => 'Herunterladen';

  @override
  String get pfmDelete => 'Löschen';

  @override
  String get pfmDeleteConfirmTitle => 'Dateien löschen?';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return '$count $_temp0 dauerhaft vom Drucker löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dateien',
      one: 'Datei',
    );
    return '$count $_temp0 gelöscht';
  }

  @override
  String get wearConnectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String get wearNoPrinters => 'Keine Drucker';

  @override
  String get wearPrinterUnavailable => 'Drucker nicht verfügbar';

  @override
  String get wearNoActions => 'Keine Aktionen verfügbar';

  @override
  String get wearClearPlate => 'Platte leeren';

  @override
  String get wearPlateCleared => 'Platte geleert';

  @override
  String get wearPlateNeedsOnline =>
      'Dieser Server benötigt den Drucker online';

  @override
  String get wearStarted => 'Gestartet';

  @override
  String get wearPhoneUnreachable => 'Smartphone nicht erreichbar';

  @override
  String get wearPhoneNoResponse => 'Smartphone hat nicht geantwortet';

  @override
  String get wearConfirm => 'Bestätigen';

  @override
  String get wearServerUrl => 'Server-URL';

  @override
  String get wearConnect => 'Verbinden';

  @override
  String get wearAuthKey => 'Schlüssel';

  @override
  String get wearAuthLogin => 'Anmelden';

  @override
  String get wearUsername => 'Benutzername';

  @override
  String get wearSetupPhoneTitle => 'Vom Smartphone einrichten';

  @override
  String get wearSetupPhoneBody =>
      'Öffne Bambuddy auf deinem gekoppelten Smartphone — die Uhr übernimmt Server und Anmeldung.';

  @override
  String get wearSetupPhoneCheck => 'Erneut prüfen';

  @override
  String get wearSetupPhoneEmpty => 'Noch nichts vom Smartphone.';

  @override
  String get wearSetupManual => 'Manuell eingeben';

  @override
  String get wearSetupDemo => 'Demo';

  @override
  String get wearSetupTapToType => 'Tippen zur Eingabe';

  @override
  String get wearSettingsTitle => 'Einstellungen';

  @override
  String get wearFromPhone => 'Vom Smartphone';

  @override
  String get wearFromPhoneUse => 'Diesen Server verwenden';

  @override
  String get wearFromPhoneLater => 'Nicht jetzt';

  @override
  String get wearAuthNone => 'Ohne Anmeldung';

  @override
  String get wearFromPhoneWaiting =>
      'Das Smartphone bietet einen anderen Server an.';

  @override
  String get wearCurrentServer => 'Aktueller Server';

  @override
  String get wearOk => 'OK';

  @override
  String get commonOn => 'Ein';

  @override
  String get commonOff => 'Aus';

  @override
  String get commonAuto => 'Auto';

  @override
  String get queueEdit => 'Bearbeiten';

  @override
  String get queueEditTitle => 'Warteschlangeneintrag bearbeiten';

  @override
  String get queueEditSave => 'Speichern';

  @override
  String get queueEditSaved => 'Warteschlangeneintrag aktualisiert';

  @override
  String get queueCreateTitle => 'Drucken';

  @override
  String get queueCreateSubmit => 'Drucken';

  @override
  String get queueCreateAdded => 'Zur Warteschlange hinzugefügt';

  @override
  String get queueEditPrintJob => 'Druckauftrag';

  @override
  String get queueEditTarget => 'Ziel';

  @override
  String get queueEditSpecificPrinter => 'Bestimmter Drucker';

  @override
  String queueEditAnyModel(String model) {
    return 'Beliebiger $model';
  }

  @override
  String get queueEditAnyModelGeneric => 'Beliebiges Modell';

  @override
  String get queueEditTargetModel => 'Modell';

  @override
  String get queueEditTargetLocation => 'Standort';

  @override
  String get queueEditAnyLocation => 'Beliebiger Standort';

  @override
  String get queueEditMappingNeedsPrinter =>
      'Wähle einen Drucker, um Filamente zuzuordnen';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Slots',
      one: 'Slot',
    );
    return '$count $_temp0 zugeordnet';
  }

  @override
  String get queueEditMappingAuto => 'Automatisch (keine manuelle Zuordnung)';

  @override
  String get queueEditPlate => 'Druckplatte';

  @override
  String queueEditPlateSelected(int plate) {
    return 'Druckplatte $plate';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return 'Druckplatte $plate · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return 'Dieser Auftrag druckt Druckplatte $plate';
  }

  @override
  String get queuePlatePickTitle => 'Welche Druckplatte?';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte',
      one: '1 Objekt',
      zero: 'Keine Objekte',
    );
    return '$_temp0';
  }

  @override
  String get queueEditPrintOptions => 'Druckoptionen';

  @override
  String get queueOptBedLevelling => 'Bettnivellierung';

  @override
  String get queueOptBedLevellingDesc =>
      'Druckbett vor dem Druck automatisch nivellieren';

  @override
  String get queueOptFlowCali => 'Flusskalibrierung';

  @override
  String get queueOptFlowCaliDesc => 'Extrusionsfluss kalibrieren';

  @override
  String get queueOptVibrationCali => 'Vibrationskalibrierung';

  @override
  String get queueOptVibrationCaliDesc => 'Ringing-Artefakte reduzieren';

  @override
  String get queueOptLayerInspect => 'Inspektion der ersten Schicht';

  @override
  String get queueOptLayerInspectDesc => 'KI-Inspektion der ersten Schicht';

  @override
  String get queueOptTimelapse => 'Zeitraffer';

  @override
  String get queueOptTimelapseDesc => 'Zeitraffervideo aufnehmen';

  @override
  String get queueOptNozzleOffset => 'Düsenversatz-Kalibrierung';

  @override
  String get queueOptNozzleOffsetDesc =>
      'Düsenversatz zwischen Extrudern kalibrieren';

  @override
  String get queueEditPreheat => 'Vorheizen & Heat Soak';

  @override
  String get queueEditPreheatDesc =>
      'Druckbett und Kammer vor dem Druck aufheizen. Richtet sich standardmäßig nach dem Schalter unter Einstellungen → Workflow.';

  @override
  String get queuePreheatInherit => 'Übernehmen';

  @override
  String get queueEditChamberTarget =>
      'Kammertemperatur überschreiben (°C, leer = Filament-Standard)';

  @override
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

  @override
  String get queueEditWhenToPrint => 'Wann drucken';

  @override
  String get queueScheduleAsap => 'Sofort';

  @override
  String get queueScheduleQueue => 'Warteschlange';

  @override
  String get queueScheduleSchedule => 'Planen';

  @override
  String get queueEditPickTime => 'Datum & Uhrzeit wählen';

  @override
  String get queueEditRequireManualStart => 'Manuellen Start erfordern';

  @override
  String get queueEditRequirePrevious =>
      'Nur starten, wenn der vorherige Druck erfolgreich war';

  @override
  String get queueEditPowerOff => 'Drucker nach Abschluss ausschalten';

  @override
  String get queueEditGcodeInjection => 'Auto-Druck-G-Code einfügen';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return 'Kein G-Code-Snippet für $model vorhanden — es wird nichts eingefügt.';
  }

  @override
  String get queueEditNoModel => 'Zielmodell auswählen';

  @override
  String get queueEditNoPrinter => 'Drucker auswählen';

  @override
  String get queueEditFilamentOverride => 'Filament überschreiben';

  @override
  String get queueEditFilamentOverrideDesc =>
      'Optional Filamente für die modellbasierte Zuweisung überschreiben. Der Scheduler gleicht die ausgewählten Filamente anstelle der ursprünglichen 3MF-Werte ab.';

  @override
  String get queueEditNoFilamentReqs =>
      'Keine Filament-Anforderungen für diesen Auftrag.';

  @override
  String get queueEditOriginal => 'Original';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return 'Slot $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => 'Farbübereinstimmung erzwingen';

  @override
  String get queueEditNozzleRack => 'Düsenmagazin';

  @override
  String get queueEditNozzleRackDesc =>
      'Wähle, mit welcher Düse aus dem Magazin jedes Filament gedruckt wird. Bleibt dies automatisch, wird bei Druckbeginn eine passende Position gewählt.';

  @override
  String queueEditRackGroupLabel(String slots, String nozzle) {
    return 'Filament $slots · $nozzle';
  }

  @override
  String get queueEditRackAuto => 'Automatisch';

  @override
  String queueEditRackPosition(int position, String nozzle) {
    return 'Position $position · $nozzle';
  }

  @override
  String queueEditRackPositionTaken(int position, String nozzle) {
    return 'Position $position · $nozzle — bereits ausgewählt';
  }

  @override
  String queueEditRackPositionUnfit(int position, String nozzle) {
    return 'Position $position · $nozzle — passt nicht';
  }

  @override
  String get queueEditRackEmpty => 'leer';

  @override
  String get queueEditRackPickStale =>
      'Die gewählte Position passt nicht mehr zu diesem Filament — wähle eine andere, sonst wird der Druck beim Start abgelehnt.';

  @override
  String queueEditRackNoFit(String nozzle) {
    return 'Keine Position im Magazin enthält eine $nozzle-Düse — setze eine ein, sonst entscheidet der Drucker selbst.';
  }

  @override
  String get nozzleFlowStandard => 'Standard';

  @override
  String get nozzleFlowHigh => 'High-Flow';

  @override
  String get bugReportMenu => 'Fehler oder Idee melden';

  @override
  String get bugReportTitle => 'Fehler oder Idee melden';

  @override
  String get bugReportIntroHeader => 'So funktioniert es';

  @override
  String get bugReportStepRecord => 'Aufzeichnung starten';

  @override
  String get bugReportStepReproduce => 'Problem reproduzieren';

  @override
  String get bugReportStepFinish => 'Zurückkehren und abschließen';

  @override
  String get bugReportLogScreens =>
      'Bildschirme, die du öffnest, und Tasten, die du drückst';

  @override
  String get bugReportLogRequests =>
      'Anfragen an den Server und dessen Antworten';

  @override
  String get bugReportLogService =>
      'Die Live-Ansicht und welche Benachrichtigungen der Hintergrunddienst gesendet oder übersprungen hat';

  @override
  String get bugReportLogErrors =>
      'Fehler und Abstürze, einschließlich jener, die du nie siehst';

  @override
  String get bugReportLogSetup =>
      'App- und Server-Version, dein Smartphone, deine Sprache';

  @override
  String get bugReportLogNoKey => 'Dein API-Schlüssel oder Passwort';

  @override
  String get bugReportLogNoTyping => 'Der von dir eingegebene Text';

  @override
  String get bugReportLogNoAddress =>
      'Deine Serveradresse — nur http oder https, Name oder IP und der Port';

  @override
  String get bugReportLogNoData =>
      'Seriennummern der Drucker oder die Namen deiner Dateien, Modelle und Spulen';

  @override
  String get bugReportReviewFirst =>
      'Du kannst alles lesen, bevor es das Smartphone verlässt.';

  @override
  String get bugReportPrivacyHeader => 'Was im Log landet';

  @override
  String get bugReportStart => 'Aufzeichnung starten';

  @override
  String get bugReportRecordingHeader => 'Aufzeichnung läuft';

  @override
  String get bugReportRecordingBody =>
      'Kehre zur App zurück und reproduziere das Problem. Die Aufzeichnungsleiste bleibt sichtbar — schiebe sie beiseite oder klappe sie ein, wenn sie stört, und nutze sie, um den Moment des Fehlers zu markieren und die Aufnahme zu beenden.';

  @override
  String get bugReportMark => 'Moment markieren';

  @override
  String get bugReportMarked => 'Moment markiert';

  @override
  String get bugReportStop => 'Aufzeichnung beenden';

  @override
  String get bugReportStopShort => 'Beenden';

  @override
  String get bugReportBannerLabel => 'Aufzeichnung';

  @override
  String get bugReportBarMove => 'Aufzeichnungsleiste verschieben';

  @override
  String get bugReportBarCollapse => 'Aufzeichnungsleiste einklappen';

  @override
  String get bugReportBarExpand => 'Aufzeichnungsleiste ausklappen';

  @override
  String get bugReportReviewHeader => 'Vor dem Senden überprüfen';

  @override
  String get bugReportReviewBody =>
      'Dies ist alles, was aufgezeichnet wurde. Lies es durch — unten entscheidest du, ob es auf dem Smartphone bleibt oder als öffentliches Issue gemeldet wird.';

  @override
  String bugReportSummary(int records, int errors, int warnings) {
    return '$records Einträge · $errors Fehler · $warnings Warnungen';
  }

  @override
  String bugReportMarkers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count markierte Momente',
      one: '1 markierter Moment',
    );
    return '$_temp0';
  }

  @override
  String get bugReportTruncated =>
      'Die Sitzung war lang — die ältesten Einträge wurden verworfen.';

  @override
  String get bugReportEmpty => 'Es wurde nichts aufgezeichnet.';

  @override
  String get bugReportShowRaw => 'Roh-Log anzeigen';

  @override
  String get bugReportHideRaw => 'Roh-Log ausblenden';

  @override
  String bugReportRawClipped(int kb) {
    return 'Die ersten $kb kB werden hier nicht angezeigt. Die gespeicherte Datei enthält die gesamte Sitzung.';
  }

  @override
  String get bugReportSave => 'In Datei speichern';

  @override
  String get bugReportSaveShort => 'Speichern';

  @override
  String get bugReportSaved => 'Log in Datei gespeichert';

  @override
  String get bugReportSaveFailed => 'Das Log konnte nicht gespeichert werden.';

  @override
  String get bugReportDiscard => 'Verwerfen';

  @override
  String get bugReportDiscardQuestion => 'Diese Aufzeichnung verwerfen?';

  @override
  String get bugReportDiscardBody => 'Das Log wird vom Smartphone gelöscht.';

  @override
  String get bugReportDiscardBodyQueued =>
      'Das Log wird vom Smartphone gelöscht und der Bericht in der Warteschlange abgebrochen.';

  @override
  String bugReportLimit(int minutes) {
    return 'Eine Aufzeichnung stoppt automatisch nach $minutes Minuten.';
  }

  @override
  String bugReportLimitReached(int minutes) {
    return 'Aufzeichnung beendet — das Limit von $minutes Minuten wurde erreicht.';
  }

  @override
  String bugReportSizeLimitReached(int megabytes) {
    return 'Aufzeichnung beendet — das Log hat das Limit von $megabytes MB erreicht.';
  }

  @override
  String get bugReportShow => 'Anzeigen';

  @override
  String get bugReportRecoveredHeader =>
      'Eine Aufzeichnung hat einen Absturz überstanden';

  @override
  String get bugReportRecoveredBody =>
      'Die App wurde während der Aufzeichnung geschlossen. Was bereits aufgezeichnet wurde, befindet sich noch auf dem Smartphone — schau es dir an oder verwirf es.';

  @override
  String get bugReportDestinationHeader => 'Was mit diesem Log geschieht';

  @override
  String get bugReportDestinationFile => 'In Datei speichern';

  @override
  String get bugReportDestinationIssue => 'Auf GitHub melden';

  @override
  String get bugReportDestinationFileBody =>
      'Das Log wird am gewählten Ort gespeichert und verbleibt auf deinem Smartphone. Du entscheidest, ob du es irgendwohin sendest.';

  @override
  String get bugReportDestinationIssueBody =>
      'Das Log und deine Beschreibung werden als öffentliches Issue auf GitHub veröffentlicht, wo sie jeder lesen kann und dauerhaft bleiben. Gehe zuerst das Log unten durch.';

  @override
  String get bugReportDescriptionLabel => 'Was ist schiefgelaufen?';

  @override
  String get bugReportDescriptionHint =>
      'Was hast du getan, was hast du erwartet und was ist stattdessen passiert.';

  @override
  String get bugReportDescriptionRequired =>
      'Beschreibe, was schiefgelaufen ist — ein Log ohne Beschreibung ist kaum brauchbar.';

  @override
  String get bugReportSend => 'Melden';

  @override
  String get bugReportSending => 'Wird gesendet…';

  @override
  String bugReportSendWaiting(String clock) {
    return 'Wird in $clock gesendet';
  }

  @override
  String get bugReportSendWaitingBody =>
      'Das Relay staffelt Berichte zeitlich. Du kannst diesen Bildschirm verlassen — der Bericht wird automatisch gesendet.';

  @override
  String get bugReportSent => 'Bericht gesendet';

  @override
  String get bugReportSentBody =>
      'Vielen Dank. Das Issue ist eröffnet und das Log ist angehängt.';

  @override
  String get bugReportOpenIssue => 'Issue öffnen';

  @override
  String get bugReportDone => 'Fertig';

  @override
  String get bugReportSendFailedNotYet =>
      'Das Relay nimmt derzeit keine Berichte an. Versuche es später erneut oder speichere das Log in einer Datei.';

  @override
  String get bugReportSendFailedRefused =>
      'Das Relay hat diesen Bericht abgelehnt. Speichere das Log in einer Datei und hänge es selbst an.';

  @override
  String get bugReportSendFailedDuplicate => 'Dies wurde bereits gemeldet.';

  @override
  String get bugReportSendFailedUnreachable =>
      'Das Relay konnte nicht erreicht werden. Prüfe die Verbindung oder speichere das Log in einer Datei.';

  @override
  String get bugReportSendFailedRejected =>
      'Das Relay hat diesen Bericht zurückgewiesen. Speichere das Log in einer Datei und hänge es selbst an.';

  @override
  String get bugReportSendFailedDemo =>
      'Der Demo-Modus veröffentlicht keine Berichte. Speichere das Log stattdessen in einer Datei.';

  @override
  String get bugReportKindQuestion => 'Was möchtest du melden?';

  @override
  String get bugReportKindBug => 'Fehler';

  @override
  String get bugReportKindChange => 'Änderung';

  @override
  String get bugReportKindFeature => 'Neue Funktion';

  @override
  String get bugReportChangeHeader => 'Änderung vorschlagen';

  @override
  String get bugReportChangeBody =>
      'Etwas funktioniert, aber nicht so, wie es sollte.';

  @override
  String get bugReportChangeLabel => 'Was sollte sich ändern?';

  @override
  String get bugReportChangeHint =>
      'Was es jetzt tut und was es stattdessen tun sollte.';

  @override
  String get bugReportFeatureHeader => 'Neue Funktion vorschlagen';

  @override
  String get bugReportFeatureBody => 'Etwas, das die App noch nicht kann.';

  @override
  String get bugReportFeatureLabel => 'Was fehlt?';

  @override
  String get bugReportFeatureHint =>
      'Was du tun möchtest und warum die App dies nicht zulässt.';

  @override
  String get bugReportRequestPrivacyHeader => 'Was gesendet wird';

  @override
  String get bugReportRequestWhatYouWrite => 'Was du schreibst';

  @override
  String get bugReportRequestVersions => 'App- und Server-Version';

  @override
  String get bugReportRequestNoLog => 'Kein Log, keine Aufzeichnung';

  @override
  String get bugReportRequestNoData =>
      'Keine Daten über deine Drucker oder dein Smartphone';

  @override
  String get bugReportRequestPublic =>
      'Es wird ein öffentliches Issue auf GitHub — jeder kann es lesen und es bleibt dauerhaft bestehen.';

  @override
  String get bugReportRequestRequired =>
      'Beschreibe dein Anliegen — ein leeres Anliegen kann nicht bearbeitet werden.';

  @override
  String get bugReportRequestSentBody => 'Vielen Dank. Das Issue ist eröffnet.';

  @override
  String get bugReportCancelSend => 'Senden abbrechen';

  @override
  String get bugReportRequestFailedNotYet =>
      'Das Relay nimmt derzeit keine Berichte an. Versuche es später erneut.';

  @override
  String get bugReportRequestFailedRefused =>
      'Das Relay hat diese Anfrage abgelehnt. Du kannst das Issue selbst auf GitHub eröffnen.';

  @override
  String get bugReportRequestFailedUnreachable =>
      'Das Relay konnte nicht erreicht werden. Prüfe die Verbindung und versuche es erneut.';

  @override
  String get bugReportRequestFailedDemo =>
      'Der Demo-Modus veröffentlicht keine Berichte.';

  @override
  String get bugReportRequestNotPrepared =>
      'Die App konnte den Bericht nicht zusammenstellen. Es wurde nichts gesendet — versuche es erneut.';

  @override
  String get usersTitle => 'Benutzer';

  @override
  String get usersMenu => 'Benutzer';

  @override
  String get usersEmpty => 'Keine Konten auf diesem Server.';

  @override
  String get usersYou => 'du';

  @override
  String get usersRoleAdmin => 'Admin';

  @override
  String get usersRoleUser => 'Benutzer';

  @override
  String get usersInactive => 'Inaktiv';

  @override
  String get usersEmailLabel => 'E-Mail';

  @override
  String get usersEmailNone => 'keine';

  @override
  String get usersGroupsLabel => 'Gruppen';

  @override
  String get usersNoGroups => 'keine';

  @override
  String get usersPermissionsLabel => 'Berechtigungen';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Berechtigungen',
      one: '1 Berechtigung',
      zero: 'keine',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => 'vom Server nicht gemeldet';

  @override
  String get usersAuthSourceLabel => 'Anmeldung';

  @override
  String get usersAuthSourceLocal => 'Lokales Konto';

  @override
  String get usersCreatedLabel => 'Erstellt';

  @override
  String get usersOwnedTitle => 'VON DIESEM KONTO ERSTELLT';

  @override
  String get usersOwnedArchives => 'Drucke';

  @override
  String get usersOwnedQueue => 'Warteschlange';

  @override
  String get usersOwnedLibrary => 'Dateien';

  @override
  String get usersOwnedFailed =>
      'Inhalte dieses Kontos konnten nicht gelesen werden.';

  @override
  String get usersCreate => 'Konto hinzufügen';

  @override
  String get usersCreateTitle => 'Neues Konto';

  @override
  String get usersEdit => 'Bearbeiten';

  @override
  String get usersEditTitle => 'Konto bearbeiten';

  @override
  String get usersDelete => 'Löschen';

  @override
  String get usersSave => 'Speichern';

  @override
  String get usersSaved => 'Konto gespeichert';

  @override
  String get usersSaveFailed => 'Das Konto konnte nicht gespeichert werden.';

  @override
  String get usersDeleted => 'Konto gelöscht';

  @override
  String get usersFieldUsername => 'Benutzername';

  @override
  String get usersFieldEmail => 'E-Mail (optional)';

  @override
  String get usersFieldEmailRequired => 'E-Mail';

  @override
  String get usersFieldPassword => 'Passwort';

  @override
  String get usersFieldNewPassword => 'Neues Passwort';

  @override
  String get usersFieldConfirmPassword => 'Passwort wiederholen';

  @override
  String get usersFieldActive => 'Aktiv';

  @override
  String get usersFieldGroups => 'Gruppen';

  @override
  String get usersGroupSystem => '(integriert)';

  @override
  String get usersFieldRequired => 'Bitte ausfüllen';

  @override
  String get usersPasswordsDoNotMatch =>
      'Die beiden Passwörter stimmen nicht überein.';

  @override
  String get usersGroupsAdminHint =>
      'Die Mitgliedschaft in der Gruppe Administrators macht ein Konto zum Administrator.';

  @override
  String get usersActiveHint => 'Ein inaktives Konto kann sich nicht anmelden.';

  @override
  String get usersEmailAdvancedHint =>
      'Dieser Server versendet das Passwort per E-Mail, daher wird eine Adresse benötigt.';

  @override
  String get usersPasswordMailed =>
      'Der Server wählt das Passwort selbst und sendet es an diese Adresse. Niemand, auch du nicht, bekommt es zu sehen.';

  @override
  String get usersNoSmtpWarning =>
      'Es ist kein E-Mail-Server konfiguriert, sodass diese Nachricht nicht ankommt – das Konto würde mit einem Passwort erstellt, das niemand kennt.';

  @override
  String get usersLdapPasswordNote =>
      'Dieses Konto meldet sich über das Verzeichnis (LDAP) an. Sein Passwort wird dort verwaltet und kann hier nicht festgelegt werden.';

  @override
  String get usersPasswordKeepHint =>
      'Leer lassen, um das aktuelle Passwort beizubehalten.';

  @override
  String get usersPasswordRulesHint =>
      'Mindestens 8 Zeichen, darunter ein Groß- und ein Kleinbuchstabe, eine Ziffer und ein Sonderzeichen.';

  @override
  String get usersPasswordTooShort => 'Mindestens 8 Zeichen.';

  @override
  String get usersPasswordNoUppercase => 'Füge einen Großbuchstaben hinzu.';

  @override
  String get usersPasswordNoLowercase => 'Füge einen Kleinbuchstaben hinzu.';

  @override
  String get usersPasswordNoDigit => 'Füge eine Ziffer hinzu.';

  @override
  String get usersPasswordNoSpecial => 'Füge ein Sonderzeichen hinzu.';

  @override
  String usersDeleteTitle(String username) {
    return '$username löschen?';
  }

  @override
  String get usersDeleteBody =>
      'Das Konto, seine API-Schlüssel und der Anmeldestatus werden entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dieses Konto hat $count Objekte erstellt',
      one: 'Dieses Konto hat 1 Objekt erstellt',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => 'Diese ebenfalls löschen';

  @override
  String get usersDeleteItemsTooHint =>
      'Druckaufträge, Warteschlangeneinträge und Dateien des Kontos werden gelöscht.';

  @override
  String get usersDeleteItemsKeepHint =>
      'Druckaufträge, Warteschlangeneinträge und Dateien bleiben ohne Besitzer erhalten.';

  @override
  String get usersDeleteConfirm => 'Löschen';

  @override
  String get usersErrLastAdmin =>
      'Dies ist der letzte Administrator – der Server benötigt mindestens einen.';

  @override
  String get usersErrLastAdminDelete =>
      'Der letzte Administrator kann nicht gelöscht werden – es bliebe niemand übrig, der den Server verwalten kann.';

  @override
  String get usersErrLastAdminDeactivate =>
      'Der letzte Administrator kann nicht deaktiviert werden – es bliebe niemand übrig, der den Server verwalten kann.';

  @override
  String get usersErrLastAdminRole =>
      'Die Administratorrolle kann dem letzten Administrator nicht entzogen werden – es bliebe niemand übrig, der den Server verwalten kann.';

  @override
  String get usersErrSelfDelete =>
      'Du kannst das Konto, mit dem du angemeldet bist, nicht löschen.';

  @override
  String get usersErrUsernameTaken =>
      'Dieser Benutzername ist bereits vergeben.';

  @override
  String get usersErrEmailTaken =>
      'Diese E-Mail-Adresse wird bereits von einem anderen Konto verwendet.';

  @override
  String get usersErrLdapPassword =>
      'Das Passwort eines Verzeichnis-Kontos (LDAP) kann hier nicht festgelegt werden.';

  @override
  String get usersErrEmailRequired =>
      'Dieser Server erfordert eine E-Mail-Adresse für ein neues Konto.';

  @override
  String get usersErrPasswordRequired =>
      'Dieser Server erfordert ein Passwort für ein neues Konto.';

  @override
  String get usersErrGroupsInvalid =>
      'Eine der Gruppen existiert nicht mehr – öffne das Formular erneut.';

  @override
  String get groupsTitle => 'Gruppen';

  @override
  String get groupsMenu => 'Gruppen';

  @override
  String get groupsEmpty => 'Keine Gruppen auf diesem Server.';

  @override
  String get groupsNoDescription => 'Keine Beschreibung';

  @override
  String get groupsSystemPill => 'Integriert';

  @override
  String get groupsSystemNote =>
      'Eine integrierte Gruppe kann nicht umbenannt werden und ihre Berechtigungen sind festgelegt – nur die Mitglieder können geändert werden.';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten',
      one: '1 Konto',
      zero: 'keine Konten',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Berechtigungen',
      one: '1 Berechtigung',
      zero: 'keine Berechtigungen',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => 'MITGLIEDER';

  @override
  String get groupsNoMembers => 'Niemand ist in dieser Gruppe.';

  @override
  String get groupsAddMember => 'Mitglied hinzufügen';

  @override
  String groupsAddMemberTitle(String group) {
    return 'Zu $group hinzufügen';
  }

  @override
  String get groupsEveryoneIsIn => 'Alle Konten sind bereits in dieser Gruppe.';

  @override
  String get groupsRemoveMember => 'Entfernen';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return '$username aus $group entfernen?';
  }

  @override
  String get groupsRemoveMemberBody =>
      'Das Konto bleibt erhalten und verliert die Berechtigungen dieser Gruppe.';

  @override
  String get groupsCreate => 'Neue Gruppe';

  @override
  String get groupsCreateTitle => 'Neue Gruppe';

  @override
  String get groupsEditTitle => 'Gruppe bearbeiten';

  @override
  String get groupsDelete => 'Gruppe löschen';

  @override
  String get groupsSaved => 'Gruppe gespeichert';

  @override
  String get groupsDeleted => 'Gruppe gelöscht';

  @override
  String groupsDeleteQuestion(String group) {
    return '$group löschen?';
  }

  @override
  String get groupsDeleteBody =>
      'Die damit gewährten Berechtigungen werden ebenfalls entfernt.';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Konten gehören dazu und bleiben erhalten – sie verlieren lediglich die durch diese Gruppe gewährten Berechtigungen.',
      one:
          '1 Konto gehört dazu und bleibt erhalten – es verliert lediglich die durch diese Gruppe gewährten Berechtigungen.',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => 'Name';

  @override
  String get groupsFieldDescription => 'Verwendungszweck';

  @override
  String get groupsSystemFormNote =>
      'Eine integrierte Gruppe: Name und Berechtigungen werden vom Server vorgegeben. Hier kann nur die Beschreibung geändert werden.';

  @override
  String get groupsPermissionsHeader => 'BERECHTIGUNGEN';

  @override
  String groupsPermissionsSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get groupsAdvancedPermissions => 'Serveradministration';

  @override
  String get groupsAdvancedHint =>
      'Benutzer, API-Schlüssel, Einstellungen, Backups – alles, wofür die App selbst keine eigene Ansicht hat.';

  @override
  String get serverSettingsMenu => 'Servereinstellungen';

  @override
  String get serverSettingsTitle => 'Servereinstellungen';

  @override
  String get serverSettingsQueueSubtitle =>
      'Planung, Vorheizen und Warmhalten des Druckbetts zwischen Drucken';

  @override
  String get serverSettingsMaintenanceSubtitle =>
      'Wartungsaufgaben und Intervalle pro Drucker';

  @override
  String get serverSettingsAdminSubtitle => 'Konten, Gruppen und API-Schlüssel';

  @override
  String get serverSettingsCloudSubtitle =>
      'Das Bambu-Konto, mit dem der Server Dateien herunterlädt';

  @override
  String get queueSettingsTitle => 'Warteschlange und Vorheizen';

  @override
  String get queueSettingsReadOnlyApiKey =>
      'Ein API-Schlüssel kann niemals Servereinstellungen ändern. Melde dich mit einem Konto an, um diese zu bearbeiten.';

  @override
  String get queueSettingsReadOnlyPermission =>
      'Dein Konto darf diese Einstellungen lesen, aber nicht ändern.';

  @override
  String get queueSettingsUnavailable =>
      'Dieser Server meldet keine dieser Einstellungen. Entweder ist er älter als diese Funktionen oder sie konnten nicht gelesen werden – zum Wiederholen nach unten ziehen.';

  @override
  String get queueSettingsQueueHeader => 'Warteschlange';

  @override
  String get queueSettingsPlateClearTitle => 'Freie Druckplatte bestätigen';

  @override
  String get queueSettingsPlateClearDesc =>
      'Nach einem Druck wartet der Drucker darauf, dass jemand bestätigt, dass die Druckplatte frei ist.';

  @override
  String get queueSettingsShortestFirstTitle => 'Kürzester Druckauftrag zuerst';

  @override
  String get queueSettingsShortestFirstDesc =>
      'Den kürzesten wartenden Druckauftrag vorziehen, anstatt den am längsten wartenden zu nehmen.';

  @override
  String queueSettingsMaxUploads(int count) {
    return 'Gleichzeitig hochgeladene Dateien: $count';
  }

  @override
  String get queueSettingsPreheatHeader => 'Vorheizen';

  @override
  String get queueSettingsPreheatTitle => 'Vor dem Druckauftrag vorheizen';

  @override
  String get queueSettingsPreheatDesc =>
      'Wärmt die Kammer vor dem Senden der Datei auf. Ein einzelner Auftrag in der Warteschlange kann dies überschreiben.';

  @override
  String queueSettingsPreheatMaxWait(String duration) {
    return 'Maximale Wartezeit für die Kammer: $duration';
  }

  @override
  String queueSettingsPreheatSoak(String duration) {
    return 'Haltezeit nach Erreichen der Temperatur: $duration';
  }

  @override
  String get queueSettingsNoSoak => 'Keine Haltezeit';

  @override
  String get queueSettingsPreheatOffNote =>
      'Das Vorheizen ist deaktiviert, daher haben die folgenden Einstellungen keine Auswirkung.';

  @override
  String get queueSettingsKeepWarmHeader => 'Warmhalten';

  @override
  String get queueSettingsKeepWarmTitle =>
      'Druckbett zwischen Drucken warmhalten';

  @override
  String get queueSettingsKeepWarmDesc =>
      'Bis der fertige Druck abgenommen wird, bleibt das Druckbett heiß – so startet der nächste Auftrag mit beheizter Kammer nicht im kalten Zustand. Bei PLA und PETG übersprungen.';

  @override
  String queueSettingsKeepWarmTemp(int temp) {
    return 'Druckbetttemperatur zum Heizen der Kammer: $temp °C';
  }

  @override
  String queueSettingsKeepWarmMax(String duration) {
    return 'Maximale Haltedauer des Druckbetts: $duration';
  }

  @override
  String get queueSettingsMaxUploadsDesc =>
      'Bevor ein Auftrag in der Warteschlange startet, wird seine Datei per FTP an den Drucker gesendet, was einige Minuten dauern kann. Dies legt fest, wie viele Übertragungen gleichzeitig laufen – wirkt sich nur bei mehreren Druckern aus.';

  @override
  String get queueSettingsPreheatMaxWaitDesc =>
      'Ein X1C oder P2S hat keine aktive Kammerheizung – die Kammer wird über das Druckbett erwärmt, was 15–30 Minuten dauern kann. Danach wartet die Warteschlange nicht länger und geht zur Haltezeit über.';

  @override
  String get queueSettingsPreheatSoakDesc =>
      'Zusätzliche Zeit auf Temperatur, nachdem die Kammer diese erreicht hat oder die Wartezeit oben abgelaufen ist. Bei 0 wird dieser Schritt übersprungen.';

  @override
  String get queueSettingsKeepWarmTempDesc =>
      '90 hält die Kammerwärme in einem geschlossenen Drucker aufrecht und aktiviert nachgerüstete Kammerheizungen, die meist bei 80 °C Betttemperatur einschalten. Eine höhere Betttemperatur aus der Datei hat immer Vorrang.';

  @override
  String get queueSettingsKeepWarmMaxDesc =>
      'Stelle hier die Zeit ein, die du realistisch benötigst, um den Drucker zu erreichen. Ein zu kurzer Wert führt nur dazu, dass der nächste Druck von Grund auf neu aufheizen muss; ohne Begrenzung würde eine nicht abgeräumte Druckplatte das Druckbett dauerhaft heiß halten.';

  @override
  String get queueSettingsKeepWarmOffNote =>
      'Warmhalten ist deaktiviert. Die obige Druckbetttemperatur gilt weiterhin für das Vorheizen.';

  @override
  String get adminMenu => 'Administration';

  @override
  String get adminTitle => 'Administration';

  @override
  String adminSignedInAs(String username) {
    return 'Angemeldet als $username';
  }

  @override
  String get adminUsersSubtitle =>
      'Wer ein Konto besitzt und was die einzelnen Konten tun dürfen';

  @override
  String get adminGroupsSubtitle => 'Berechtigungssätze und deren Inhaber';

  @override
  String get adminApiKeysSubtitle =>
      'Zugangsdaten für alles außerhalb dieser App';

  @override
  String get apiKeysTitle => 'API-Schlüssel';

  @override
  String get apiKeysEmpty => 'Es wurden noch keine Schlüssel ausgestellt.';

  @override
  String get apiKeysCreate => 'Neuer Schlüssel';

  @override
  String get apiKeysCreateTitle => 'Neuer API-Schlüssel';

  @override
  String get apiKeysEditTitle => 'Schlüssel bearbeiten';

  @override
  String get apiKeysSaved => 'Schlüssel gespeichert';

  @override
  String get apiKeysRevoke => 'Widerrufen';

  @override
  String get apiKeysRevoked => 'Schlüssel widerrufen';

  @override
  String apiKeysRevokeQuestion(String name) {
    return '$name widerrufen?';
  }

  @override
  String get apiKeysRevokeBody =>
      'Alles, was diesen Schlüssel verwendet, funktioniert ab sofort nicht mehr. Dies kann nicht rückgängig gemacht werden – es müsste ein neuer Schlüssel ausgestellt werden.';

  @override
  String apiKeysLastUsed(String date) {
    return 'zuletzt verwendet $date';
  }

  @override
  String get apiKeysNeverUsed => 'nie verwendet';

  @override
  String get apiKeysDisabled => 'Deaktiviert';

  @override
  String get apiKeysExpired => 'Abgelaufen';

  @override
  String apiKeysExpiresOn(String date) {
    return 'bis $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Drucker',
      one: '1 Drucker',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => 'Kein Besitzer';

  @override
  String get apiKeysFieldName => 'Name';

  @override
  String get apiKeysFieldNameHint =>
      'Was diesen Schlüssel verwendet – „Home Assistant“, „SpoolBuddy“.';

  @override
  String get apiKeysFieldEnabled => 'Aktiv';

  @override
  String get apiKeysFieldEnabledHint =>
      'Durch das Deaktivieren funktioniert der Schlüssel nicht mehr, ohne ihn zu löschen.';

  @override
  String get apiKeysScopesHeader => 'ERLAUBTE AKTIONEN';

  @override
  String get apiKeysScopesHint =>
      'Ein Schlüssel kann niemals Konten, Gruppen, Schlüssel oder Einstellungen verwalten – der Server verweigert dies für alle Schlüssel.';

  @override
  String get apiKeysPrintersHeader => 'DRUCKER';

  @override
  String get apiKeysAllPrinters => 'Alle Drucker';

  @override
  String get apiKeysAllPrintersHint =>
      'Aus: Auswählen, auf welche Drucker dieser Schlüssel zugreifen darf.';

  @override
  String get apiKeysExpiryHeader => 'GÜLTIGKEIT';

  @override
  String get apiKeysNoExpiry => 'Läuft nicht ab';

  @override
  String get apiKeysExpiryHint =>
      'Tippen, um ein Ablaufdatum für den Schlüssel festzulegen.';

  @override
  String get apiKeysExpiryClear => 'Kein Ablaufdatum';

  @override
  String get apiKeysCreatedTitle => 'Schlüssel erstellt';

  @override
  String get apiKeysCreatedWarning =>
      'Kopiere ihn jetzt. Der Server speichert nur einen Hash – dies ist das letzte Mal, dass er angezeigt werden kann.';

  @override
  String get apiKeysCopy => 'Kopieren';

  @override
  String get apiKeysCopied => 'Schlüssel kopiert';

  @override
  String get apiKeysCreatedDone => 'Fertig';

  @override
  String get apiKeyScopeRead => 'Status lesen';

  @override
  String get apiKeyScopeReadHint =>
      'Drucker, Warteschlange, Archiv, Bibliothek, Statistiken – nur Leserechte.';

  @override
  String get apiKeyScopeQueue => 'Warteschlange';

  @override
  String get apiKeyScopeControl => 'Drucker steuern';

  @override
  String get apiKeyScopeControlHint =>
      'Pause, Stopp, Temperaturen, AMS, schaltbare Steckdosen.';

  @override
  String get apiKeyScopeLibrary => 'Dateien';

  @override
  String get apiKeyScopeInventory => 'Filamente';

  @override
  String get apiKeyScopeMaintenance => 'Wartung';

  @override
  String get apiKeyScopeArchives => 'Archiv';

  @override
  String get apiKeyScopeProjects => 'Projekte';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint =>
      'Liest Daten aus der Cloud im Namen des Kontos, das den Schlüssel erstellt. Erfordert serverseitig aktivierte Authentifizierung.';

  @override
  String get apiKeyScopeEnergy => 'Strompreis';

  @override
  String get apiKeyScopeEnergyHint =>
      'Der einzige Einstellungswert, den ein Schlüssel schreiben darf – für dynamische Stromtarife.';

  @override
  String get printLogTitle => 'Druckprotokoll';

  @override
  String get printLogSearchHint => 'Durchläufe durchsuchen';

  @override
  String get printLogEmpty => 'Noch keine Durchläufe aufgezeichnet';

  @override
  String get printLogNoMatches => 'Keine Durchläufe entsprechen den Filtern';

  @override
  String get printLogLoadFailed => 'Druckprotokoll konnte nicht geladen werden';

  @override
  String get printLogFilters => 'Filter';

  @override
  String get printLogFilterPrinter => 'Drucker';

  @override
  String get printLogFilterUser => 'Benutzer';

  @override
  String get printLogFilterStatus => 'Status';

  @override
  String get printLogFilterDates => 'Datumsbereich';

  @override
  String get printLogAnyPrinter => 'Alle Drucker';

  @override
  String get printLogAnyUser => 'Alle Benutzer';

  @override
  String get printLogAnyStatus => 'Jeder Status';

  @override
  String get printLogNoUser => 'Kein Benutzer';

  @override
  String get printLogOrphan => 'Archiv gelöscht';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded von $total';
  }

  @override
  String get printLogLoadMore => 'Mehr laden';

  @override
  String get printLogSort => 'Sortieren nach';

  @override
  String get printLogSortDate => 'Datum';

  @override
  String get printLogSortName => 'Name';

  @override
  String get printLogSortPrinter => 'Drucker';

  @override
  String get printLogSortUser => 'Benutzer';

  @override
  String get printLogSortStatus => 'Status';

  @override
  String get printLogSortDuration => 'Dauer';

  @override
  String get printLogSortFilament => 'Verbrauchtes Filament';

  @override
  String get printLogSortCost => 'Kosten';

  @override
  String get printLogSortEnergy => 'Energie';

  @override
  String get printLogSortDirection => 'Reihenfolge';

  @override
  String get printLogSortDescending => 'Absteigend';

  @override
  String get printLogSortAscending => 'Aufsteigend';

  @override
  String get printLogStatusCompleted => 'Abgeschlossen';

  @override
  String get printLogStatusFailed => 'Fehlgeschlagen';

  @override
  String get printLogStatusStopped => 'Angehalten';

  @override
  String get printLogStatusCancelled => 'Abgebrochen';

  @override
  String get printLogStatusSkipped => 'Übersprungen';

  @override
  String get printLogStatusAborted => 'Vorzeitig abgebrochen';

  @override
  String printLogEnergy(String value) {
    return '$value kWh';
  }

  @override
  String get printLogClassifyTitle => 'Diesen Durchlauf klassifizieren';

  @override
  String get printLogDetailStarted => 'Gestartet';

  @override
  String get printLogDetailFinished => 'Beendet';

  @override
  String get printLogDetailDuration => 'Dauer';

  @override
  String get printLogDetailFilament => 'Filament';

  @override
  String get printLogDetailCost => 'Kosten';

  @override
  String get printLogDetailEnergy => 'Energie';

  @override
  String get printLogFailureCause => 'Fehlerursache';

  @override
  String get printLogNoClassification => 'Nicht klassifiziert';

  @override
  String get printLogStatusLabel => 'Status';

  @override
  String get printLogCountsAsFailure =>
      'Wird als Fehldruck gewertet – dieser Durchlauf und seine Ursache erscheinen in der Fehleranalyse.';

  @override
  String get printLogNotCountedAsFailure =>
      'Wird nicht als Fehldruck gewertet, sodass die Ursache nicht in der Fehleranalyse erscheint.';

  @override
  String printLogStatusOneWay(String status) {
    return 'Dieser Server kann „$status“ nicht zurückschreiben. Wird er geändert, ist der ursprüngliche Status unwiderruflich verloren.';
  }

  @override
  String get printLogSave => 'Speichern';

  @override
  String get printLogSaveFailed =>
      'Klassifizierung konnte nicht gespeichert werden';

  @override
  String get printLogDelete => 'Durchlauf löschen';

  @override
  String get printLogDeleteTitle => 'Diesen Durchlauf löschen?';

  @override
  String get printLogDeleteBody =>
      'Er wird aus dem Protokoll entfernt und sein Filamentverbrauch, die Kosten sowie die Zeit werden aus der Statistik herausgerechnet. Das verknüpfte Archiv bleibt erhalten.';

  @override
  String get printLogDeleteFailed => 'Durchlauf konnte nicht gelöscht werden';

  @override
  String get printLogClear => 'Druckprotokoll leeren';

  @override
  String get printLogClearTitle => 'Gesamtes Druckprotokoll leeren?';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Durchläufe werden gelöscht',
      one: 'Der einzige Durchlauf im Protokoll wird gelöscht',
    );
    return '$_temp0 – aller Benutzer, nicht nur deine – und ihr Filamentverbrauch, die Kosten sowie die Zeit werden aus der Statistik entfernt. Archive und die Warteschlange bleiben unberührt. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get printLogClearBodyFiltered =>
      'Jeder Durchlauf im Protokoll wird gelöscht – aller Benutzer, nicht nur deine, und der aktive Filter schränkt dies nicht ein – und ihr Filamentverbrauch, die Kosten sowie die Zeit werden aus der Statistik entfernt. Archive und die Warteschlange bleiben unberührt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Durchläufe gelöscht',
      one: '$count Durchlauf gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed =>
      'Druckprotokoll konnte nicht geleert werden';

  @override
  String get failureReasonAdhesion => 'Mangelnde Druckbetthaftung';

  @override
  String get failureReasonSpaghetti => 'Spaghetti / abgelöster Druck';

  @override
  String get failureReasonLayerShift => 'Schichtversatz';

  @override
  String get failureReasonCloggedNozzle => 'Verstopfte Düse';

  @override
  String get failureReasonFilamentRunout => 'Filament aufgebraucht';

  @override
  String get failureReasonWarping => 'Warping (Verzug)';

  @override
  String get failureReasonStringing => 'Stringing (Fadenbildung)';

  @override
  String get failureReasonUnderExtrusion => 'Unterextrusion';

  @override
  String get failureReasonPowerFailure => 'Stromausfall';

  @override
  String get failureReasonUserCancelled => 'Vom Benutzer abgebrochen';

  @override
  String get failureReasonOther => 'Sonstiges';

  @override
  String get failureReasonUnknown => 'Unbekannt';
}
