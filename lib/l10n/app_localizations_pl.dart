// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get printersTitle => 'Drukarki';

  @override
  String get changeServer => 'Zmień serwer';

  @override
  String get sessionExpired => 'Sesja wygasła — zaloguj się ponownie';

  @override
  String get serverUnreachableStale =>
      'Serwer nieosiągalny — dane mogą być nieaktualne';

  @override
  String get wsReconnecting => 'Brak połączenia na żywo — odświeżanie co 5 s';

  @override
  String get connLive => 'Na żywo';

  @override
  String get connLiveTooltip =>
      'Aktualizacje w czasie rzeczywistym przez WebSocket';

  @override
  String get connPolling => 'Odświeżanie';

  @override
  String get connPollingTooltip =>
      'Brak łącza na żywo — odświeżanie co 5 s (REST)';

  @override
  String get connectFailed => 'Nie udało się połączyć z serwerem';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get searchPrinters => 'Szukaj drukarek…';

  @override
  String get noPrinters => 'Brak drukarek — dodaj je na serwerze';

  @override
  String noSearchResults(String query) {
    return 'Brak wyników dla „$query”';
  }

  @override
  String get changeServerQuestion => 'Zmienić serwer?';

  @override
  String get changeServerWarning =>
      'Zapisany profil i poświadczenia zostaną usunięte.';

  @override
  String get cancel => 'Anuluj';

  @override
  String get clear => 'Wyczyść';

  @override
  String get change => 'Zmień';

  @override
  String get noActivePrints => 'Brak aktywnych wydruków';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count drukuje',
      many: '$count drukuje',
      few: '$count drukują',
      one: '$count drukuje',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => 'Następna wolna: ';

  @override
  String get tempNozzle => 'Dysza';

  @override
  String get tempBed => 'Stół';

  @override
  String get tempChamber => 'Komora';

  @override
  String tempNozzleNumbered(String n) {
    return 'Dysza $n';
  }

  @override
  String get ctrlFanPart => 'Wentylator hotendu';

  @override
  String get ctrlFanAux => 'Wentylator pomocniczy';

  @override
  String get ctrlFanChamber => 'Wentylator komory';

  @override
  String get ctrlFanPartShort => 'Hotend';

  @override
  String get ctrlFanAuxShort => 'Pomoc.';

  @override
  String get ctrlFanChamberShort => 'Komora';

  @override
  String get ctrlSpeed => 'Prędkość';

  @override
  String get ctrlLight => 'Światło komory';

  @override
  String get ctrlLightOn => 'Wł.';

  @override
  String get ctrlLightOff => 'Wył.';

  @override
  String get ctrlAirduct => 'Nawiew';

  @override
  String get ctrlAirductCooling => 'Chłodzenie';

  @override
  String get ctrlAirductHeating => 'Grzanie';

  @override
  String get ctrlPause => 'Pauza';

  @override
  String get ctrlResume => 'Wznów';

  @override
  String get ctrlStop => 'Zatrzymaj';

  @override
  String get ctrlStopConfirmTitle => 'Zatrzymać wydruk?';

  @override
  String get ctrlStopConfirmBody =>
      'To anuluje bieżący wydruk. Nie da się go wznowić.';

  @override
  String get ctrlForbidden => 'Ten klucz API nie może sterować drukarką';

  @override
  String get ctrlFailed => 'Nie udało się wysłać polecenia';

  @override
  String get skipObjectsTitle => 'Pomiń obiekty';

  @override
  String get skipObjectsSkip => 'Pomiń';

  @override
  String get skipObjectsSkippedTag => 'Pominięto';

  @override
  String skipObjectsSkippedToast(String name) {
    return 'Pominięto „$name”';
  }

  @override
  String get skipObjectsConfirmTitle => 'Pominąć ten obiekt?';

  @override
  String skipObjectsConfirmBody(String name) {
    return '„$name” zostanie pominięty do końca tego wydruku. Nie można tego cofnąć.';
  }

  @override
  String get skipObjectsMatchInfo => 'Dopasuj ID do ekranu drukarki';

  @override
  String get skipObjectsMatchHint =>
      'Ekran drukarki pokazuje ID obiektów na stole';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '$skipped/$total pominięto';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count aktywnych';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return 'Pomijanie dostępne od warstwy 2 (obecnie warstwa $layer)';
  }

  @override
  String get skipObjectsEmpty => 'Brak obiektów do druku';

  @override
  String get skipObjectsEmptyHint =>
      'Obiekty wczytują się po rozpoczęciu wydruku. Odśwież, jeśli druk trwa.';

  @override
  String get skipObjectsReload => 'Odśwież';

  @override
  String get skipObjectsLoadFailed => 'Nie udało się wczytać obiektów.';

  @override
  String get speedSilent => 'Cichy';

  @override
  String get speedStandard => 'Standard';

  @override
  String get speedSport => 'Sport';

  @override
  String get speedLudicrous => 'Ekstremalny';

  @override
  String get smartPlugOn => 'Wł.';

  @override
  String get smartPlugOff => 'Wył.';

  @override
  String get smartPlugUnreachable => 'Niedostępne';

  @override
  String get smartPlugCantPowerOff =>
      'Nie można odciąć zasilania w trakcie druku';

  @override
  String get smartPlugOffConfirmTitle => 'Odciąć zasilanie?';

  @override
  String get smartPlugOffConfirmBody =>
      'Drukarka natychmiast straci zasilanie.';

  @override
  String get smartPlugTurnOff => 'Wyłącz';

  @override
  String get smartPlugOnConfirmTitle => 'Załączyć zasilanie?';

  @override
  String get smartPlugOnConfirmBody => 'Drukarka zostanie zasilona.';

  @override
  String get smartPlugTurnOn => 'Włącz';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => 'Łączny pobór mocy ze wszystkich gniazdek';

  @override
  String get queueEmpty => 'Kolejka jest pusta';

  @override
  String get queueDeleteTitle => 'Usunąć z kolejki?';

  @override
  String get queueDeleteBody => 'Element zostanie usunięty z kolejki wydruku.';

  @override
  String get queueDeleteConfirm => 'Usuń';

  @override
  String get queueStart => 'Uruchom teraz';

  @override
  String get queueStartNext => 'Uruchom następny';

  @override
  String get queueCancel => 'Anuluj';

  @override
  String get queueNoFreePrinters => 'Brak wolnych drukarek';

  @override
  String get queuePrintStarted => 'Wydruk uruchomiony';

  @override
  String get queueStatusPending => 'Oczekuje';

  @override
  String get queueStatusScheduled => 'Zaplanowany';

  @override
  String get queueStatusPrinting => 'Drukuje';

  @override
  String get queueStatusPaused => 'Wstrzymany';

  @override
  String get archiveSearchHint => 'Szukaj w archiwum';

  @override
  String get archiveEmpty => 'Brak zarchiwizowanych wydruków';

  @override
  String archiveSearchFailed(String query) {
    return 'Nie udało się wyszukać „$query”. Spróbuj innej frazy.';
  }

  @override
  String get archiveReprint => 'Drukuj ponownie';

  @override
  String get archiveAddToQueue => 'Dodaj do kolejki';

  @override
  String get gcodeViewerTitle => 'Podgląd G-code';

  @override
  String get gcodeViewerOpen => 'Podgląd G-code';

  @override
  String get gcodeViewerError => 'Nie udało się załadować podglądu G-code.';

  @override
  String get archiveReprintConfirmTitle => 'Uruchomić ponowny wydruk?';

  @override
  String archiveReprintConfirmBody(String printer) {
    return 'Plik zostanie wysłany na $printer i wydruk ruszy.';
  }

  @override
  String get archiveReprintStarted => 'Wydruk uruchomiony';

  @override
  String get archiveAddedToQueue => 'Dodano do kolejki';

  @override
  String get archiveDelete => 'Usuń';

  @override
  String get archiveDeleteTitle => 'Usunąć wydruk?';

  @override
  String archiveDeleteBody(String name) {
    return 'Usuń „$name” z archiwum.';
  }

  @override
  String get archiveDeletePurgeStats => 'Usuń też ze statystyk';

  @override
  String get archiveDeletePurgeStatsHint =>
      'W przeciwnym razie wydruk pozostanie w podsumowaniach statystyk.';

  @override
  String get archiveDeleted => 'Wydruk usunięty';

  @override
  String get archiveDeleteFailed => 'Nie udało się usunąć wydruku';

  @override
  String get archiveSelectAll => 'Zaznacz wszystko';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zaznaczonych',
      many: '$count zaznaczonych',
      few: '$count zaznaczone',
      one: '1 zaznaczony',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usunąć $count wydruków?',
      many: 'Usunąć $count wydruków?',
      few: 'Usunąć $count wydruki?',
      one: 'Usunąć 1 wydruk?',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody => 'Usuń zaznaczone wydruki z archiwum.';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usunięto $count wydruków',
      many: 'Usunięto $count wydruków',
      few: 'Usunięto $count wydruki',
      one: 'Usunięto 1 wydruk',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return 'Usunięto $ok, nie udało się $failed';
  }

  @override
  String get archivePurgeOlder => 'Usuń stare wydruki…';

  @override
  String get archivePurgeTitle => 'Usuń stare wydruki';

  @override
  String get archivePurgeOlderThan => 'Starsze niż';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dni',
      many: '$days dni',
      few: '$days dni',
      one: '1 dzień',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wydruków · $size',
      many: '$count wydruków · $size',
      few: '$count wydruki · $size',
      one: '1 wydruk · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing => 'Brak wydruków starszych niż tyle.';

  @override
  String get archivePurgePreviewError => 'Nie udało się wczytać podglądu.';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usunięto $count wydruków',
      many: 'Usunięto $count wydruków',
      few: 'Usunięto $count wydruki',
      one: 'Usunięto 1 wydruk',
      zero: 'Nie usunięto żadnych wydruków',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => 'Wybierz drukarkę';

  @override
  String get noPrintersAvailable => 'Brak dostępnych drukarek';

  @override
  String get detailsShow => 'Szczegóły';

  @override
  String get detailsHide => 'Ukryj szczegóły';

  @override
  String get cameraTooltip => 'Kamera';

  @override
  String get cameraConnecting => 'Łączenie z kamerą…';

  @override
  String get cameraError => 'Nie udało się wczytać strumienia kamery';

  @override
  String get cameraDemoUnavailable =>
      'Podgląd kamery nie jest dostępny w trybie demo';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'Szpula zewnętrzna';

  @override
  String get traySlotEmpty => 'Pusty';

  @override
  String get extruderLeft => 'Lewy ekstruder';

  @override
  String get extruderRight => 'Prawy ekstruder';

  @override
  String get extruderLeftShort => 'L';

  @override
  String get extruderRightShort => 'P';

  @override
  String get amsHumidityTooltip => 'Wilgotność AMS';

  @override
  String get amsTempTooltip => 'Temperatura AMS';

  @override
  String amsHistoryTitle(String ams) {
    return 'Historia $ams';
  }

  @override
  String get amsHistoryHumidity => 'Wilgotność';

  @override
  String get amsHistoryTemperature => 'Temperatura';

  @override
  String get amsHistoryCurrent => 'Aktualnie';

  @override
  String get amsHistoryAverage => 'Średnia';

  @override
  String get amsHistoryMin => 'Min';

  @override
  String get amsHistoryMax => 'Maks';

  @override
  String get amsHistoryRange6h => '6 h';

  @override
  String get amsHistoryRange24h => '24 h';

  @override
  String get amsHistoryRange48h => '48 h';

  @override
  String get amsHistoryRange7d => '7 d';

  @override
  String get amsHistoryGood => 'Dobra';

  @override
  String get amsHistoryFair => 'Umiarkowana';

  @override
  String get amsHistoryEmpty => 'Brak danych w tym zakresie';

  @override
  String get amsHistoryError => 'Nie udało się wczytać historii';

  @override
  String get amsHistoryRecordingInfo =>
      'Zapisywane co 5 minut, gdy drukarka jest połączona';

  @override
  String get wifiTooltip => 'Sygnał Wi-Fi';

  @override
  String get doorOpen => 'Drzwiczki otwarte';

  @override
  String get doorClosed => 'Drzwiczki zamknięte';

  @override
  String get firmwareUpToDate => 'Oprogramowanie aktualne';

  @override
  String firmwareUpdateAvailable(String version) {
    return 'Dostępna aktualizacja oprogramowania: $version';
  }

  @override
  String get statusUnavailable => 'status niedostępny';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

  @override
  String get widgetNoPrinter => 'Brak drukarki';

  @override
  String get widgetStatusPrinting => 'Drukuje';

  @override
  String get widgetStatusPaused => 'Wstrzymano';

  @override
  String get widgetStatusFinished => 'Zakończono';

  @override
  String get widgetStatusFailed => 'Błąd';

  @override
  String get widgetStatusIdle => 'Bezczynna';

  @override
  String get widgetStatusOffline => 'Offline';

  @override
  String get widgetStatusError => 'Błąd';

  @override
  String get widgetMultiTitle => 'Drukarki';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total aktywne';
  }

  @override
  String widgetMultiMore(int count) {
    return '+$count więcej';
  }

  @override
  String get widgetMultiGaugeLabel => 'drukuje';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count bezczynna';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count offline';
  }

  @override
  String get widgetMultiName => 'Bambuddy · Drukarki';

  @override
  String get widgetMultiDescription => 'Wszystkie drukarki na raz';

  @override
  String remaining(String time) {
    return 'pozostało $time';
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
  String get connectToServer => 'Połącz z serwerem';

  @override
  String get serverAddressLabel => 'Adres serwera bambuddy';

  @override
  String get serverAddressHint => 'np. 192.168.1.10:8000';

  @override
  String get serverAddressHelper =>
      'Dostęp zdalny: użyj HTTPS przez reverse proxy';

  @override
  String get testConnection => 'Testuj połączenie';

  @override
  String get serverRequiresAuth => 'Serwer wymaga uwierzytelnienia';

  @override
  String get authModeApiKey => 'Klucz API (zalecane)';

  @override
  String get authModeLogin => 'Login i hasło';

  @override
  String get apiKeyExplain =>
      'Klucz API nie wygasa i ma ograniczone uprawnienia — utwórz go na serwerze: Settings → API Keys.';

  @override
  String get apiKeyLabel => 'Klucz API';

  @override
  String get saveAndConnect => 'Zapisz i połącz';

  @override
  String get loginExplain =>
      'Sesja logowania wygasa po 24 h. Zaznacz „Zapamiętaj mnie”, żeby aplikacja logowała się ponownie automatycznie.';

  @override
  String get usernameLabel => 'Login lub e-mail';

  @override
  String get passwordLabel => 'Hasło';

  @override
  String get rememberMe => 'Zapamiętaj mnie';

  @override
  String get rememberMeSubtitle =>
      'Hasło trafi do szyfrowanego magazynu (Android Keystore)';

  @override
  String get signInAndConnect => 'Zaloguj i połącz';

  @override
  String get tryDemo => 'Wypróbuj wersję demo';

  @override
  String get scanApiKeyTitle => 'Zeskanuj klucz API';

  @override
  String get scanApiKeyHint => 'Skieruj aparat na kod QR z kluczem API';

  @override
  String get cameraPermissionTitle => 'Potrzebny dostęp do aparatu';

  @override
  String get cameraPermissionBody =>
      'Zezwól na dostęp do aparatu, aby skanować kody QR.';

  @override
  String get errMissingUrl => 'Podaj adres serwera';

  @override
  String get errMissingApiKey => 'Podaj klucz API';

  @override
  String get errMissingCredentials => 'Podaj login i hasło';

  @override
  String get errRequiresServerSetup =>
      'Serwer wymaga początkowej konfiguracji — dokończ ją w przeglądarce i wróć tutaj.';

  @override
  String get errServerUnreachable => 'Serwer nieosiągalny';

  @override
  String get errUnauthorized => 'Brak autoryzacji';

  @override
  String get errForbidden =>
      'Brak uprawnień — Twój klucz API nie ma do tego dostępu';

  @override
  String errBadResponse(int code) {
    return 'Serwer odpowiedział błędem $code';
  }

  @override
  String get errBadCertificate =>
      'Nieprawidłowy certyfikat TLS (self-signed nieobsługiwany w v1)';

  @override
  String get errConnection => 'Błąd połączenia';

  @override
  String get errMalformedResponse => 'Nieprawidłowa odpowiedź serwera';

  @override
  String get errInvalidCredentials => 'Nieprawidłowy login lub hasło';

  @override
  String get errTwoFactorUnsupported =>
      'Konto wymaga 2FA — nieobsługiwane w tej wersji. Użyj klucza API (Ustawienia → API Keys na serwerze).';

  @override
  String get errApiKeyRejected =>
      'Klucz API odrzucony — sprawdź klucz i jego scope (wymagany can_read_status)';

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent% · ETA $eta';
  }

  @override
  String notifMorePrints(int count) {
    return '+$count';
  }

  @override
  String get printFinishedTitle => 'Wydruk zakończony';

  @override
  String printFinishedBody(String name) {
    return '$name gotowe';
  }

  @override
  String get printFailedTitle => 'Wydruk nieudany';

  @override
  String printFailedBody(String name) {
    return '$name — błąd';
  }

  @override
  String get notifStartedTitle => 'Wydruk rozpoczęty';

  @override
  String notifStartedBody(String name) {
    return '$name rozpoczął drukowanie';
  }

  @override
  String get notifFirstLayerTitle => 'Pierwsza warstwa gotowa';

  @override
  String notifFirstLayerBody(String name) {
    return '$name ukończył pierwszą warstwę';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return 'Wydrukowano $percent%';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name — postęp $percent%';
  }

  @override
  String get notifPlateTitle => 'Płyta niepusta';

  @override
  String notifPlateBody(String printer) {
    return '$printer wymaga zdjęcia wydruku przed kolejnym zadaniem';
  }

  @override
  String get notifOfflineTitle => 'Drukarka offline';

  @override
  String notifOfflineBody(String printer) {
    return '$printer utraciła połączenie';
  }

  @override
  String get notifErrorTitle => 'Błąd drukarki';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer: $detail';
  }

  @override
  String get notifLowFilamentTitle => 'Niski filament';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return '$printer — pozostało $percent% filamentu';
  }

  @override
  String get notifHumidityTitle => 'Wysoka wilgotność AMS';

  @override
  String get notifHumidityHtTitle => 'Wysoka wilgotność AMS-HT';

  @override
  String notifHumidityBody(String printer, int value) {
    return '$printer — wilgotność AMS $value%';
  }

  @override
  String get notifBedCooledTitle => 'Stół wystygł';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return '$printer — stół wystygł do $temp°C';
  }

  @override
  String get notifSettingsTitle => 'Powiadomienia';

  @override
  String get notifSettingsHint =>
      'Wybierz, które zdarzenia mają wywoływać powiadomienie. Zmiany działają od następnego uruchomienia monitoringu w tle.';

  @override
  String get notifMasterTitle => 'Powiadomienia o zdarzeniach';

  @override
  String get notifMasterDesc =>
      'Wyłącz, aby wyciszyć wszystkie alerty. Wiszące powiadomienie o postępie wydruku pozostaje.';

  @override
  String get notifEventsHeader => 'Zdarzenia';

  @override
  String get notifThresholdsHeader => 'Progi';

  @override
  String get notifEvtStarted => 'Wydruk rozpoczęty';

  @override
  String get notifEvtStartedDesc => 'Gdy rozpoczyna się wydruk';

  @override
  String get notifEvtFinished => 'Wydruk zakończony';

  @override
  String get notifEvtFinishedDesc => 'Gdy wydruk zakończy się sukcesem';

  @override
  String get notifEvtFailed => 'Wydruk nieudany';

  @override
  String get notifEvtFailedDesc => 'Gdy wydruk się nie powiedzie';

  @override
  String get notifEvtFirstLayer => 'Pierwsza warstwa gotowa';

  @override
  String get notifEvtFirstLayerDesc => 'Gdy ukończy się pierwsza warstwa';

  @override
  String get notifEvtMilestones => 'Kamienie milowe postępu';

  @override
  String get notifEvtMilestonesDesc => 'Przy 25%, 50% i 75%';

  @override
  String get notifEvtPlate => 'Płyta niepusta';

  @override
  String get notifEvtPlateDesc =>
      'Gdy trzeba zdjąć wydruk przed kolejnym zadaniem';

  @override
  String get notifEvtOffline => 'Drukarka offline';

  @override
  String get notifEvtOfflineDesc => 'Gdy drukarka traci połączenie';

  @override
  String get notifEvtError => 'Błąd drukarki (HMS)';

  @override
  String get notifEvtErrorDesc => 'Gdy drukarka zgłosi błąd HMS';

  @override
  String get notifEvtLowFilament => 'Niski filament';

  @override
  String get notifEvtLowFilamentDesc =>
      'Gdy pozostały filament spadnie poniżej progu';

  @override
  String get notifEvtHumidity => 'Wysoka wilgotność AMS';

  @override
  String get notifEvtHumidityDesc => 'Gdy wilgotność AMS przekroczy próg';

  @override
  String get notifEvtBedCooled => 'Stół wystygł';

  @override
  String get notifEvtBedCooledDesc => 'Gdy stół wystygnie po wydruku';

  @override
  String notifBedCooledThreshold(int temp) {
    return 'Stół wystygł poniżej $temp°C';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'Wilgotność AMS powyżej $value%';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return 'Niski filament poniżej $percent%';
  }

  @override
  String get notifEventsMenu => 'Zdarzenia powiadomień';

  @override
  String get hmsSeverityFatal => 'Krytyczny';

  @override
  String get hmsSeveritySerious => 'Poważny';

  @override
  String get hmsSeverityCommon => 'Zwykły';

  @override
  String get hmsSeverityInfo => 'Informacja';

  @override
  String get hmsModuleMainboard => 'płyta główna';

  @override
  String get hmsModuleAms => 'AMS';

  @override
  String get hmsModuleToolhead => 'głowica';

  @override
  String get hmsModuleXcam => 'kamera';

  @override
  String get hmsModuleMc => 'sterownik ruchu';

  @override
  String get hmsErrorsHeader => 'Aktywne błędy';

  @override
  String get hmsViewInWiki => 'Otwórz w wiki Bambu';

  @override
  String get batteryOptTitle => 'Niezawodne powiadomienia w tle';

  @override
  String get batteryOptBody =>
      'Aby powiadomienia o wydruku działały, gdy aplikacja jest w tle, zezwól Bambuddy na pracę bez ograniczeń baterii. Na telefonach Samsung to konieczne.';

  @override
  String get batteryOptAllow => 'Otwórz ustawienia';

  @override
  String get batteryOptLater => 'Później';

  @override
  String get batteryOptMenu => 'Powiadomienia w tle';

  @override
  String get notificationsReady => 'Powiadomienia są skonfigurowane';

  @override
  String get notificationsBlocked =>
      'Powiadomienia są wyłączone — włącz je w ustawieniach systemu';

  @override
  String get bgServiceTitle => 'Bambuddy';

  @override
  String get bgServiceText => 'Monitoruję drukarki';

  @override
  String get bgMonitoringToggle => 'Monitorowanie w tle';

  @override
  String get bgMonitoringSubtitle =>
      'Śledź wydruki, gdy aplikacja jest zamknięta. Pokazuje stałe powiadomienie.';

  @override
  String get bgMonitoringOn => 'Monitorowanie w tle włączone';

  @override
  String get bgMonitoringOff => 'Monitorowanie w tle wyłączone';

  @override
  String get navDashboard => 'Drukarki';

  @override
  String get navQueue => 'Kolejka';

  @override
  String get navArchive => 'Archiwum';

  @override
  String get navMaintenance => 'Konserwacja';

  @override
  String get navFilaments => 'Filamenty';

  @override
  String get inventoryEmpty => 'Brak szpul w magazynie';

  @override
  String get inventoryNoMatches => 'Brak filamentów pasujących do wyszukiwania';

  @override
  String get inventorySearchHint => 'Szukaj: materiał, marka, kolor…';

  @override
  String get inventoryShowArchived => 'Pokaż zarchiwizowane';

  @override
  String get inventoryArchived => 'Zarchiwizowana';

  @override
  String get inventoryLowStock => 'Mało';

  @override
  String get inventoryFilters => 'Filtry';

  @override
  String get inventoryFilterStatus => 'Status';

  @override
  String get inventoryStatusActive => 'Aktywne';

  @override
  String get inventoryStatusArchived => 'Archiwum';

  @override
  String get inventoryFilterStock => 'Zapas';

  @override
  String get inventoryStockAll => 'Wszystkie';

  @override
  String get inventoryStockLow => 'Mało';

  @override
  String get inventoryFilterMaterial => 'Materiał';

  @override
  String get inventoryFilterBrand => 'Marka';

  @override
  String get inventoryFiltersClear => 'Wyczyść';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count szpul',
      few: '$count szpule',
      one: '$count szpula',
    );
    return '$_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return 'zostało $grams g';
  }

  @override
  String inventoryOfTotal(int total) {
    return 'z $total g';
  }

  @override
  String inventoryLoadedIn(String slot) {
    return 'Załadowana w $slot';
  }

  @override
  String get inventoryNotLoaded => 'Nie załadowana w żadnym slocie AMS';

  @override
  String get inventoryLocation => 'Lokalizacja';

  @override
  String get inventoryNozzleTemp => 'Temp. dyszy';

  @override
  String inventoryCostPerKg(String cost) {
    return '$cost/kg';
  }

  @override
  String get inventoryNote => 'Notatka';

  @override
  String get inventoryTag => 'Tag';

  @override
  String get inventoryId => 'ID filamentu';

  @override
  String get inventoryUsageHistory => 'Historia zużycia';

  @override
  String get inventoryUsageEmpty => 'Brak zapisanego zużycia';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => 'Kalibracja (K)';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle mm · K $k';
  }

  @override
  String get inventoryAddSpool => 'Dodaj szpulę';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpuli',
      many: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Dodaj $count $_temp0';
  }

  @override
  String get inventoryNewSpool => 'Nowa szpula';

  @override
  String get inventoryEditSpool => 'Edytuj szpulę';

  @override
  String get inventorySave => 'Zapisz';

  @override
  String get inventoryFieldQuantity => 'Ilość';

  @override
  String get inventoryQuantityHint => 'Dodaj naraz kilka identycznych szpul';

  @override
  String get inventoryEdit => 'Edytuj';

  @override
  String get inventoryDelete => 'Usuń';

  @override
  String get inventoryArchive => 'Archiwizuj';

  @override
  String get inventoryRestore => 'Przywróć';

  @override
  String get inventoryResetUsage => 'Resetuj zużycie';

  @override
  String get inventoryFieldSlicerPreset => 'Profil slicera';

  @override
  String get inventorySlicerPresetHint =>
      'Profil druku, z jakim dodawana jest szpula';

  @override
  String get inventorySlicerPresetNone => 'Brak profilu';

  @override
  String get inventorySlicerPresetSearch => 'Szukaj profili…';

  @override
  String get inventorySlicerPresetUnavailable =>
      'Brak dostępnych profili slicera. Włącz krojenie na serwerze (i połącz Bambu Cloud, aby mieć profile z chmury).';

  @override
  String get inventoryFieldMaterial => 'Materiał';

  @override
  String get inventoryFieldBrand => 'Marka';

  @override
  String get inventoryFieldSubtype => 'Wariant';

  @override
  String get inventoryFieldColorName => 'Nazwa koloru';

  @override
  String get inventoryFieldColorHex => 'Kolor (hex)';

  @override
  String get inventoryFieldLabelWeight => 'Waga szpuli (g)';

  @override
  String get inventoryFieldWeightUsed => 'Zużyto (g)';

  @override
  String get inventoryFieldCostPerKg => 'Cena za kg';

  @override
  String get inventoryFieldLowStock => 'Próg niskiego zapasu (%)';

  @override
  String get inventoryFieldLocation => 'Miejsce przechowywania';

  @override
  String get inventoryFieldNozzleMin => 'Dysza min (°C)';

  @override
  String get inventoryFieldNozzleMax => 'Dysza maks (°C)';

  @override
  String get inventoryFieldNote => 'Notatka';

  @override
  String get inventoryFieldRequired => 'Wymagane';

  @override
  String get inventoryFieldInvalidNumber => 'Podaj liczbę';

  @override
  String get inventorySectionBasics => 'Podstawy';

  @override
  String get inventorySectionWeight => 'Waga i koszt';

  @override
  String get inventorySectionDetails => 'Szczegóły';

  @override
  String get inventorySectionFilament => 'Filament';

  @override
  String get inventorySectionColor => 'Kolor';

  @override
  String get inventorySectionAdditional => 'Dodatkowe';

  @override
  String get inventoryFieldEmptySpoolWeight => 'Waga pustej szpuli (g)';

  @override
  String get inventoryCoreWeightSelect => 'Wybierz…';

  @override
  String get inventoryCoreWeightSearch => 'Szukaj szpul…';

  @override
  String get inventoryFieldRemainingWeight => 'Pozostała waga (g)';

  @override
  String get inventoryFieldMeasuredWeight => 'Zmierzona waga (g)';

  @override
  String get inventoryFieldCategory => 'Kategoria';

  @override
  String get inventoryFieldExtraColors => 'Dodatkowe kolory';

  @override
  String get inventoryExtraColorsHint => '2–8 hexów koloru, po przecinku';

  @override
  String get inventoryFieldEffect => 'Efekt';

  @override
  String get inventoryEffectNone => 'Brak';

  @override
  String get inventoryColorCommon => 'Popularne kolory';

  @override
  String get inventoryColorSearchHint => 'Szukaj kolorów…';

  @override
  String get inventoryColorPickTitle => 'Wybierz kolor';

  @override
  String get inventoryColorSelect => 'Wybierz';

  @override
  String get inventoryColorNone => 'Brak koloru';

  @override
  String get inventoryLowStockHint => 'Puste = próg globalny';

  @override
  String inventoryRemainingOfLabel(int total) {
    return 'z $total g';
  }

  @override
  String get inventoryDeleteTitle => 'Usunąć szpulę?';

  @override
  String inventoryDeleteConfirm(String name) {
    return 'Trwale usunąć $name? Tej operacji nie można cofnąć.';
  }

  @override
  String get inventoryResetUsageConfirm =>
      'Wyzerować zużycie? Szpula znów będzie liczona jako pełna.';

  @override
  String get inventorySpoolCreated => 'Dodano szpulę';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpuli',
      many: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Dodano $count $_temp0';
  }

  @override
  String get inventorySpoolUpdated => 'Zaktualizowano szpulę';

  @override
  String get inventorySpoolDeleted => 'Usunięto szpulę';

  @override
  String get inventorySpoolArchived => 'Zarchiwizowano szpulę';

  @override
  String get inventorySpoolRestored => 'Przywrócono szpulę';

  @override
  String get inventoryUsageReset => 'Wyzerowano zużycie';

  @override
  String get inventorySaveFailed => 'Nie udało się zapisać szpuli';

  @override
  String get inventoryActionFailed => 'Operacja nie powiodła się';

  @override
  String get inventoryUnassign => 'Odepnij';

  @override
  String get inventoryAssign => 'Przypisz do slotu';

  @override
  String get inventoryAssignPrinter => 'Drukarka';

  @override
  String get inventoryAssignNoPrinters => 'Brak dostępnych drukarek';

  @override
  String get inventorySlotAms => 'Slot AMS';

  @override
  String get inventoryAssignUnit => 'Jednostka AMS';

  @override
  String get inventoryAssignSlot => 'Slot';

  @override
  String get inventoryAssignExtruder => 'Ekstruder';

  @override
  String get inventoryAssignExternalHint =>
      'Przypisze do zewnętrznego uchwytu szpuli';

  @override
  String get inventoryAssignConfirm => 'Przypisz';

  @override
  String get inventoryAssignTitle => 'Przypisz szpulę';

  @override
  String get inventoryAssignCurrent => 'Obecnie w tym slocie';

  @override
  String get inventoryAssignPick => 'Wybierz szpulę';

  @override
  String get inventoryReassignTitle => 'Przenieść szpulę?';

  @override
  String inventoryReassignMessage(String slot) {
    return 'Ta szpula jest teraz w $slot. Zostanie stamtąd odpięta i przypisana do tego slotu.';
  }

  @override
  String get inventoryReassignAction => 'Przenieś';

  @override
  String get inventorySpoolAssigned => 'Szpula przypisana';

  @override
  String get inventorySpoolUnassigned => 'Szpula odpięta';

  @override
  String get inventoryScanSpool => 'Skanuj QR';

  @override
  String get inventoryScanTitle => 'Skanuj kod QR szpuli';

  @override
  String get inventoryScanHint => 'Skieruj aparat na kod QR szpuli';

  @override
  String get inventoryScanPermissionTitle => 'Potrzebny dostęp do aparatu';

  @override
  String get inventoryScanPermissionBody =>
      'Zezwól na dostęp do aparatu, aby skanować kody QR szpul.';

  @override
  String get inventoryScanOpenSettings => 'Otwórz ustawienia';

  @override
  String get inventoryScanInvalid => 'Nierozpoznany kod QR';

  @override
  String inventoryScanNotFound(int id) {
    return 'Nie znaleziono szpuli #$id';
  }

  @override
  String inventorySelectedCount(int count) {
    return 'Zaznaczono: $count';
  }

  @override
  String get inventorySelectAll => 'Zaznacz wszystkie';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Zarchiwizować $_temp0?';
  }

  @override
  String get inventoryBulkArchiveBody =>
      'Znikną z listy aktywnych. Możesz je później przywrócić.';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Przywrócić $_temp0?';
  }

  @override
  String get inventoryBulkRestoreBody => 'Wrócą na listę aktywnych.';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Usunąć $_temp0?';
  }

  @override
  String get inventoryBulkDeleteBody =>
      'Trwale je usuwa — tej operacji nie da się cofnąć.';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count szpul',
      one: 'szpuli',
    );
    return 'Zresetować zużycie $_temp0?';
  }

  @override
  String get inventoryBulkResetBody => 'Będą liczone jako pełne.';

  @override
  String inventoryBulkDone(int count) {
    return 'Zaktualizowano: $count';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return 'Udało się: $ok, błędów: $failed';
  }

  @override
  String get inventoryLabelsTitle => 'Drukuj etykiety szpul';

  @override
  String get inventoryLabelsPrint => 'Drukuj etykiety';

  @override
  String get inventoryLabelsPrintAll => 'Drukuj etykiety wszystkich';

  @override
  String get inventoryLabelsSearchHint => 'Szukaj: nazwa, marka lub #ID';

  @override
  String get inventoryLabelsPickSpools =>
      'Wybierz szpule do wydrukowania etykiet:';

  @override
  String get inventoryLabelsMaterial => 'Materiał:';

  @override
  String get inventoryLabelsAllMaterials => 'Wszystkie';

  @override
  String get inventoryLabelsSort => 'Sortuj:';

  @override
  String get inventoryLabelsSortById => 'Po ID';

  @override
  String get inventoryLabelsSortByColor => 'Po kolorze';

  @override
  String get inventoryLabelsSelectVisible => 'Zaznacz widoczne';

  @override
  String get inventoryLabelsDeselectVisible => 'Odznacz widoczne';

  @override
  String get inventoryLabelsClearAll => 'Wyczyść';

  @override
  String get inventoryLabelsNoMatches =>
      'Żadna szpula nie pasuje do wyszukiwania ani filtra.';

  @override
  String get inventoryLabelsMonochrome =>
      'Monochromatycznie (drukarka czarno-biała)';

  @override
  String get inventoryLabelsMonochromeHint =>
      'Pomija próbkę koloru i poszerza tekst';

  @override
  String get inventoryLabelsShare => 'Udostępnij PDF zamiast drukować';

  @override
  String get inventoryLabelsPickTemplate =>
      'Wybierz rozmiar etykiety do druku:';

  @override
  String inventoryLabelsTooMany(int max) {
    return 'Wybierz maksymalnie $max szpul na jeden wydruk';
  }

  @override
  String get inventoryLabelsFailed => 'Nie udało się wygenerować etykiet';

  @override
  String get inventoryLabelsAmsSmall => 'Uchwyt AMS — mały (74 × 33 mm)';

  @override
  String get inventoryLabelsAmsSmallHint =>
      'Jedna na stronę; pasuje do etykiety z modelu MakerWorld 752566.';

  @override
  String get inventoryLabelsAmsLarge => 'Uchwyt AMS — duży (75 × 55 mm)';

  @override
  String get inventoryLabelsAmsLargeHint =>
      'Jedna na stronę; pasuje do wersji z wkładką z kartonu tego samego uchwytu.';

  @override
  String get inventoryLabelsBox40 => 'Etykieta pudełkowa (40 × 30 mm)';

  @override
  String get inventoryLabelsBox40Hint =>
      'Jedna na stronę; typowy rozmiar rolki DK/Brother, dobra na woreczki i pojemniki.';

  @override
  String get inventoryLabelsBox62 => 'Etykieta pudełkowa (62 × 29 mm)';

  @override
  String get inventoryLabelsBox62Hint =>
      'Jedna na stronę; pod Brother PT/QL i małe etykiety Dymo.';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 — arkusz A4 (38,1 × 63,5 mm × 21)';

  @override
  String get inventoryLabelsAveryL7160Hint =>
      'Arkusze europejskie; 21 etykiet na stronie A4.';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 — arkusz US Letter (25,4 × 66,7 mm × 30)';

  @override
  String get inventoryLabelsAvery5160Hint =>
      'Arkusze amerykańskie; 30 etykiet na stronie Letter.';

  @override
  String get maintenanceEmpty => 'Brak danych o konserwacji';

  @override
  String maintenanceTotalHours(int hours) {
    return '$hours h łącznie';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count zaległe';
  }

  @override
  String maintenanceWarningBadge(int count) {
    return '$count wkrótce';
  }

  @override
  String maintenanceDueIn(int hours) {
    return 'Za $hours h';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return 'Przeterminowane o $hours h';
  }

  @override
  String get maintenancePerform => 'Oznacz wykonane';

  @override
  String get maintenancePerformConfirm =>
      'Zresetować licznik dla tej czynności konserwacji?';

  @override
  String get maintenanceNotesHint => 'Notatka (opcjonalnie)';

  @override
  String get maintenanceHistory => 'Historia';

  @override
  String get maintenanceHistoryEmpty => 'Brak historii';

  @override
  String get maintenanceDone => 'Konserwacja oznaczona jako wykonana';

  @override
  String get maintenanceFailed => 'Nie udało się zaktualizować konserwacji';

  @override
  String get maintenanceSaved => 'Zapisano';

  @override
  String get maintenanceSettingsTitle => 'Ustawienia konserwacji';

  @override
  String get maintenanceOverridesTitle => 'Nadpisania interwałów';

  @override
  String get maintenanceOverridesSubtitle =>
      'Wycisz zadania lub dostosuj interwały per drukarka';

  @override
  String get maintenanceTabStatus => 'Status';

  @override
  String get maintenanceTabSettings => 'Ustawienia';

  @override
  String get maintenanceMute => 'Wycisz';

  @override
  String get maintenanceUnmute => 'Wznów';

  @override
  String get maintenanceMuted => 'Zadanie wyciszone';

  @override
  String get maintenanceUnmuted => 'Zadanie wznowione';

  @override
  String get maintenanceEditInterval => 'Edytuj interwał';

  @override
  String get maintenanceResetInterval => 'Przywróć domyślny';

  @override
  String get maintenanceTypesTitle => 'Typy konserwacji';

  @override
  String get maintenanceTypesSubtitle => 'Typy systemowe i własne zadania';

  @override
  String get maintenanceRestoreDefaults => 'Przywróć domyślne';

  @override
  String get maintenanceRestoreConfirm =>
      'Przywrócić wszystkie ukryte domyślne typy konserwacji?';

  @override
  String get maintenanceAddType => 'Dodaj własny typ';

  @override
  String get maintenanceEditType => 'Edytuj typ';

  @override
  String get maintenanceSystemType => 'Systemowy';

  @override
  String maintenanceEveryHours(int count) {
    return 'Co $count h';
  }

  @override
  String maintenanceEveryDays(int count) {
    return 'Co $count dni';
  }

  @override
  String get maintenanceDeleteTypeTitle => 'Usunąć typ konserwacji?';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return 'Usunąć „$name\"? Tej operacji nie można cofnąć.';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return 'Ukryć domyślny typ „$name\"? Możesz go później przywrócić.';
  }

  @override
  String get maintenanceFieldName => 'Nazwa';

  @override
  String get maintenanceFieldNameHint => 'np. Wymiana filtra HEPA';

  @override
  String get maintenanceFieldIntervalType => 'Typ interwału';

  @override
  String get maintenanceFieldInterval => 'Interwał';

  @override
  String get maintenanceIntervalHours => 'Godziny druku';

  @override
  String get maintenanceIntervalDays => 'Dni';

  @override
  String get maintenanceIntervalInvalid => 'Podaj wartość ≥ 1';

  @override
  String get maintenanceFieldIcon => 'Ikona';

  @override
  String get maintenanceFieldDocLink => 'Link do dokumentacji (opcjonalnie)';

  @override
  String get maintenanceAssignPrinters => 'Przypisz do drukarek';

  @override
  String get maintenanceSelectPrinter => 'Wybierz co najmniej jedną drukarkę';

  @override
  String get notifEvtMaintenance => 'Konserwacja zaległa';

  @override
  String get notifEvtMaintenanceDesc =>
      'Gdy czynność konserwacji staje się przeterminowana';

  @override
  String get maintenanceNotifTitle => 'Konserwacja zaległa';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer: $task';
  }

  @override
  String get maintenanceReminderTitle => 'Przypomnienie o konserwacji';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'zaległych czynności',
      many: 'zaległych czynności',
      few: 'zaległe czynności',
      one: 'zaległą czynność',
    );
    return '$printer ma $count $_temp0 konserwacji';
  }

  @override
  String get maintenanceNotifAction => 'Oznacz wykonane';

  @override
  String get navMenu => 'Menu';

  @override
  String get menuStatistics => 'Statystyki';

  @override
  String get statsTitle => 'Statystyki';

  @override
  String get statsRangeAllTime => 'Cały okres';

  @override
  String get statsRangeLast7Days => 'Ostatnie 7 dni';

  @override
  String get statsRangeLast30Days => 'Ostatnie 30 dni';

  @override
  String get statsRangeLast90Days => 'Ostatnie 90 dni';

  @override
  String get statsRangeThisYear => 'Ten rok';

  @override
  String get statsRangeCustom => 'Własny zakres';

  @override
  String get statsEmpty => 'Brak wydruków w tym okresie';

  @override
  String get statsLoadFailed => 'Nie udało się wczytać statystyk';

  @override
  String get statsOverview => 'Przegląd';

  @override
  String get statsTotalPrints => 'Wydruki łącznie';

  @override
  String get statsPrintTime => 'Czas druku';

  @override
  String get statsFilamentUsed => 'Zużyty filament';

  @override
  String get statsFilamentCost => 'Koszt filamentu';

  @override
  String get statsEnergyUsed => 'Zużyta energia';

  @override
  String get statsEnergyCost => 'Koszt energii';

  @override
  String get statsTotalCost => 'Koszt łącznie';

  @override
  String get statsEnergyWarmingUp => 'Dane o energii dopiero się zbierają';

  @override
  String get statsSuccessRate => 'Skuteczność';

  @override
  String statsSuccessful(int count) {
    return 'Udane: $count';
  }

  @override
  String statsFailed(int count) {
    return 'Nieudane: $count';
  }

  @override
  String statsCancelled(int count) {
    return 'Anulowane: $count';
  }

  @override
  String get statsAllUsers => 'Wszyscy użytkownicy';

  @override
  String get statsNoUser => 'Brak użytkownika (system)';

  @override
  String get statsTimeAccuracy => 'Dokładność czasu';

  @override
  String get statsTimeAccuracyHint => '100% = idealny szacunek';

  @override
  String get statsByMaterial => 'Wydruki wg materiału';

  @override
  String get statsByPrinter => 'Wydruki wg drukarki';

  @override
  String get statsTimeAccuracyByPrinter => 'Dokładność czasu wg drukarki';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wydruku',
      many: '$count wydruków',
      few: '$count wydruki',
      one: '$count wydruk',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours h';
  }

  @override
  String statsPrinterFallback(String id) {
    return 'Drukarka #$id';
  }

  @override
  String get statsMetricWeight => 'Waga';

  @override
  String get statsMetricPrints => 'Wydruki';

  @override
  String get statsMetricTime => 'Czas';

  @override
  String get statsFailureAnalysis => 'Analiza niepowodzeń';

  @override
  String get statsFailureRate => 'Odsetek niepowodzeń';

  @override
  String statsFailurePeriod(int days) {
    return 'Ostatnie $days dni';
  }

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total wydruków nieudanych';
  }

  @override
  String get statsTopFailureReasons => 'Najczęstsze powody';

  @override
  String get statsNoFailures => 'Brak niepowodzeń w tym okresie';

  @override
  String get statsPrintActivity => 'Aktywność wydruków';

  @override
  String get statsHeatmapLess => 'Mniej';

  @override
  String get statsHeatmapMore => 'Więcej';

  @override
  String get statsRecords => 'Rekordy';

  @override
  String get statsLongestPrint => 'Najdłuższy wydruk';

  @override
  String get statsHeaviestPrint => 'Najcięższy wydruk';

  @override
  String get statsMostExpensive => 'Najdroższy';

  @override
  String get statsBusiestDay => 'Najbardziej zajęty dzień';

  @override
  String get statsSuccessStreak => 'Seria sukcesów';

  @override
  String statsConsecutive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count z rzędu',
      one: '$count z rzędu',
    );
    return '$_temp0';
  }

  @override
  String get statsFilamentTrends => 'Trendy filamentu';

  @override
  String get statsPeriodFilament => 'Filament w okresie';

  @override
  String get statsPeriodCost => 'Koszt w okresie';

  @override
  String get statsAvgPerPrint => 'Średnio na wydruk';

  @override
  String get statsUsageOverTime => 'Zużycie w czasie';

  @override
  String get statsByMaterialTitle => 'Wg materiału';

  @override
  String get statsSuccessByMaterial => 'Skuteczność wg materiału';

  @override
  String get statsColorDistribution => 'Rozkład kolorów';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count koloru',
      many: '$count kolorów',
      few: '$count kolory',
      one: '$count kolor',
    );
    return '$_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '+$count więcej';
  }

  @override
  String get statsPrintDuration => 'Czas trwania wydruku';

  @override
  String get statsPrintHabits => 'Nawyki drukowania';

  @override
  String get statsPrintTimeOfDay => 'Pora dnia wydruku';

  @override
  String get aboutMenu => 'O aplikacji';

  @override
  String get aboutTitle => 'O aplikacji';

  @override
  String get aboutTagline =>
      'Natywny klient Android dla bambuddy — self-hostowanego menedżera drukarek Bambu Lab.';

  @override
  String aboutVersion(String version) {
    return 'Wersja $version';
  }

  @override
  String get aboutLicenseHeader => 'Licencja';

  @override
  String get aboutLicenseBody =>
      'Bambuddy to wolne oprogramowanie wydane na licencji GNU Affero General Public License v3.0 (AGPL-3.0). Możesz go używać, badać, udostępniać i modyfikować; jeśli uruchamiasz zmodyfikowaną wersję jako usługę sieciową, musisz udostępnić jej źródła użytkownikom.';

  @override
  String get aboutViewLicense => 'Przeczytaj licencję AGPL-3.0';

  @override
  String get aboutSourceHeader => 'Kod źródłowy';

  @override
  String get aboutSourceBody => 'Pełne źródła są dostępne na Codeberg.';

  @override
  String get aboutSourceLink => 'Otwórz repozytorium źródeł';

  @override
  String get aboutThirdParty => 'Licencje open-source';

  @override
  String get aboutThirdPartySubtitle => 'Licencje dołączonych bibliotek';

  @override
  String get aboutOpenLinkError => 'Nie udało się otworzyć linku';

  @override
  String get fileManagerMenu => 'Menedżer plików';

  @override
  String get fileManagerTitle => 'Menedżer plików';

  @override
  String get fmRoot => 'Wszystkie pliki';

  @override
  String get fmSearchHint => 'Szukaj plików…';

  @override
  String get fmEmpty => 'Ten folder jest pusty';

  @override
  String get fmNoMatches => 'Brak plików pasujących do filtrów';

  @override
  String get fmSortBy => 'Sortuj według';

  @override
  String get fmSortDateNewest => 'Najnowsze';

  @override
  String get fmSortDateOldest => 'Najstarsze';

  @override
  String get fmSortNameAZ => 'Nazwa A–Z';

  @override
  String get fmSortNameZA => 'Nazwa Z–A';

  @override
  String get fmSortSizeLargest => 'Największe';

  @override
  String get fmSortSizeSmallest => 'Najmniejsze';

  @override
  String get fmFilterType => 'Typ pliku';

  @override
  String get fmAllTypes => 'Wszystkie typy';

  @override
  String get fmNewFolder => 'Nowy folder';

  @override
  String get fmFolderName => 'Nazwa folderu';

  @override
  String get fmFileName => 'Nazwa pliku';

  @override
  String get fmSave => 'Zapisz';

  @override
  String get fmRename => 'Zmień nazwę';

  @override
  String get fmRenameFolder => 'Zmień nazwę folderu';

  @override
  String get fmRenameFile => 'Zmień nazwę pliku';

  @override
  String get fmRenamed => 'Zmieniono nazwę';

  @override
  String get fmFolderCreated => 'Utworzono folder';

  @override
  String get fmDelete => 'Usuń';

  @override
  String get fmDeleted => 'Przeniesiono do kosza';

  @override
  String get fmDeleteFile => 'Usuń plik';

  @override
  String fmDeleteFileConfirm(String name) {
    return 'Przenieść „$name” do kosza?';
  }

  @override
  String get fmDeleteFolder => 'Usuń folder';

  @override
  String fmDeleteFolderConfirm(String name) {
    return 'Usunąć folder „$name” wraz z całą zawartością?';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pliku',
      many: 'plików',
      few: 'pliki',
      one: 'plik',
    );
    return 'Przenieść $count $_temp0 do kosza?';
  }

  @override
  String get fmMoveTo => 'Przenieś do…';

  @override
  String get fmMoved => 'Przeniesiono';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'elementu',
      many: 'elementów',
      few: 'elementy',
      one: 'element',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => 'Drukuj';

  @override
  String fmPrintConfirmBody(String name, String printer) {
    return 'Wysłać „$name” na $printer i rozpocząć druk?';
  }

  @override
  String get fmPrintStarted => 'Wysłano na drukarkę';

  @override
  String get fmAddToQueue => 'Dodaj do kolejki';

  @override
  String get fmAddedToQueue => 'Dodano do kolejki';

  @override
  String get fmUpload => 'Wgraj plik';

  @override
  String get fmUploading => 'Wgrywanie…';

  @override
  String fmUploaded(String name) {
    return 'Wgrano $name';
  }

  @override
  String get fmUploadFailed => 'Nie udało się wgrać pliku';

  @override
  String fmSelectedCount(int count) {
    return 'Zaznaczono: $count';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pliku',
      many: 'plików',
      few: 'pliki',
      one: 'plik',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'folderu',
      many: 'folderów',
      few: 'foldery',
      one: 'folder',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '$size wolnego';
  }

  @override
  String get fmTrash => 'Kosz';

  @override
  String get fmTrashTitle => 'Kosz';

  @override
  String get fmTrashEmpty => 'Kosz jest pusty';

  @override
  String get fmRestore => 'Przywróć';

  @override
  String get fmRestored => 'Przywrócono';

  @override
  String get fmEmptyTrash => 'Opróżnij kosz';

  @override
  String get fmEmptyTrashConfirm =>
      'Trwale usunąć wszystkie pliki z kosza? Tej operacji nie można cofnąć.';

  @override
  String get fmHardDelete => 'Usuń trwale';

  @override
  String fmHardDeleteConfirm(String name) {
    return 'Trwale usunąć „$name”? Tej operacji nie można cofnąć.';
  }

  @override
  String get fmDeletedForever => 'Usunięto trwale';

  @override
  String get makerworldMenu => 'MakerWorld';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get mwIntro =>
      'Wklej link do modelu z MakerWorld, aby zaimportować go i drukować bezpośrednio z Bambuddy.';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/pl/models/… lub dowolny link MakerWorld';

  @override
  String get mwResolve => 'Rozwiąż';

  @override
  String get mwEnterUrl => 'Wpisz link do MakerWorld';

  @override
  String get mwUntitledModel => 'Model bez nazwy';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count płyty',
      many: '$count płyt',
      few: '$count płyty',
      one: '1 płyta',
      zero: 'Brak płyt',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => 'Nie znaleziono płyt dla tego modelu.';

  @override
  String get mwImport => 'Importuj';

  @override
  String mwShowAllPlates(int count) {
    return 'Pokaż wszystkie ($count)';
  }

  @override
  String get mwShowLess => 'Pokaż mniej';

  @override
  String get mwInLibrary => 'W bibliotece';

  @override
  String get mwImported => 'Zaimportowano do biblioteki';

  @override
  String get mwAlreadyInLibrary => 'Już jest w bibliotece';

  @override
  String get mwViewInFiles => 'Pokaż w menedżerze plików';

  @override
  String get mwRecentImports => 'Ostatnie importy';

  @override
  String get mwNoRecent => 'Brak ostatnich importów';

  @override
  String get mwOpenOnMakerworld => 'Otwórz w MakerWorld';

  @override
  String get mwLoginRequired =>
      'Zaloguj się do konta Bambu Cloud, aby pobierać modele z MakerWorld.';

  @override
  String get cloudAccountMenu => 'Konto Bambu Cloud';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote =>
      'Zaloguj się kontem Bambu Lab. Dane logowania służą wyłącznie do pobierania modeli z MakerWorld.';

  @override
  String get cloudEmail => 'E-mail';

  @override
  String get cloudPassword => 'Hasło';

  @override
  String get cloudRegionGlobal => 'Globalny';

  @override
  String get cloudRegionChina => 'Chiny';

  @override
  String get cloudSignIn => 'Zaloguj';

  @override
  String get cloudSignOut => 'Wyloguj';

  @override
  String get cloudSignedIn => 'Zalogowano';

  @override
  String get cloudSignedInOk => 'Zalogowano do Bambu Cloud';

  @override
  String get cloudSignInFailed => 'Logowanie nie powiodło się';

  @override
  String get cloudFillCredentials => 'Podaj e-mail i hasło';

  @override
  String get cloudVerify => 'Zweryfikuj';

  @override
  String get cloudVerificationCode => 'Kod weryfikacyjny';

  @override
  String get cloudVerificationPrompt =>
      'Wpisz kod weryfikacyjny, aby dokończyć logowanie.';

  @override
  String get cloudEnterCode => 'Wpisz kod weryfikacyjny';

  @override
  String get swatchCodesMenu => 'Kody próbek';

  @override
  String get swatchCodesTitle => 'Kody próbek';

  @override
  String get swatchSearchHint => 'Szukaj po kodzie lub nazwie';

  @override
  String get swatchSectionCodes => 'Kody';

  @override
  String get swatchSectionUncoded => 'Filamenty z magazynu bez kodu';

  @override
  String get swatchNoCodes => 'Brak kodów próbek';

  @override
  String get swatchNoCodesHint => 'Utwórz kod, aby oznaczyć próbkę filamentu.';

  @override
  String swatchNoMatch(String query) {
    return 'Brak kodów pasujących do „$query”';
  }

  @override
  String get swatchAllCoded => 'Wszystkie filamenty z magazynu mają kody';

  @override
  String get swatchNewCode => 'Nowy kod';

  @override
  String get swatchGenerate => 'Generuj';

  @override
  String get swatchGenerateCode => 'Generuj kod';

  @override
  String get swatchExists => 'Ten filament ma już kod';

  @override
  String swatchCreatedSnack(String code) {
    return 'Utworzono kod $code';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return 'Zaktualizowano kod $code';
  }

  @override
  String swatchCopied(String code) {
    return 'Skopiowano $code';
  }

  @override
  String get swatchDelete => 'Usuń';

  @override
  String get swatchDeleteTitle => 'Usunąć kod?';

  @override
  String swatchDeleteBody(String code, String name) {
    return 'Kod $code dla $name zostanie usunięty.';
  }

  @override
  String get swatchExport => 'Eksport';

  @override
  String get swatchImport => 'Import';

  @override
  String get swatchExportEmpty => 'Brak kodów do eksportu';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kodu',
      many: '$count kodów',
      few: '$count kody',
      one: '1 kod',
    );
    return 'Wyeksportowano $_temp0';
  }

  @override
  String get swatchExportFailed => 'Eksport nie powiódł się';

  @override
  String get swatchImportTitle => 'Zaimportować kody?';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return 'To zastąpi wszystkie obecne kody ($existing) kodami z pliku ($incoming). Tej operacji nie można cofnąć.';
  }

  @override
  String get swatchImportConfirm => 'Zastąp wszystkie';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kodu',
      many: '$count kodów',
      few: '$count kody',
      one: '1 kod',
    );
    return 'Zaimportowano $_temp0';
  }

  @override
  String get swatchImportFailed => 'Nie udało się odczytać pliku';

  @override
  String get swatchImportEmpty => 'Nie znaleziono kodów w pliku';

  @override
  String get swatchFormTitle => 'Nowy kod próbki';

  @override
  String get swatchEditTitle => 'Edytuj kod';

  @override
  String get swatchSave => 'Zapisz';

  @override
  String get swatchRegenerate => 'Wygeneruj ponownie';

  @override
  String get swatchFieldCode => 'Kod';

  @override
  String get swatchCodeInvalid =>
      'Użyj 6 znaków: cyfry i litery, bez 0, 1, I, L i O';

  @override
  String get swatchCodeTaken => 'Ten kod jest już używany';

  @override
  String get swatchFieldBrand => 'Producent';

  @override
  String get swatchFieldMaterial => 'Materiał';

  @override
  String get swatchFieldVariant => 'Wariant';

  @override
  String get swatchFieldColor => 'Kolor';

  @override
  String get swatchFieldHex => 'Kolor hex';

  @override
  String get swatchMaterialRequired => 'Materiał jest wymagany';

  @override
  String get swatchNoCatalogColors =>
      'Brak kolorów w katalogu. Wpisz nazwę i hex ręcznie.';

  @override
  String get projectsMenu => 'Projekty';

  @override
  String get projectsTitle => 'Projekty';

  @override
  String get projectsEmpty => 'Brak projektów';

  @override
  String get projectsFilterAll => 'Wszystkie';

  @override
  String get projectCreate => 'Nowy projekt';

  @override
  String get projectEdit => 'Edytuj projekt';

  @override
  String get projectDelete => 'Usuń';

  @override
  String get projectDeleteTitle => 'Usunąć projekt?';

  @override
  String projectDeleteBody(String name) {
    return '„$name” zostanie usunięty. Powiązane wydruki pozostaną w archiwum.';
  }

  @override
  String get projectDeleted => 'Projekt usunięty';

  @override
  String get projectDeleteFailed => 'Nie udało się usunąć projektu';

  @override
  String get projectSaved => 'Projekt zapisany';

  @override
  String get projectActionForbidden =>
      'Klucz API nie ma uprawnień do tej akcji';

  @override
  String get projectActionFailed => 'Akcja nie powiodła się';

  @override
  String get projectName => 'Nazwa';

  @override
  String get projectNameRequired => 'Nazwa jest wymagana';

  @override
  String get projectDescription => 'Opis';

  @override
  String get projectNotes => 'Notatki';

  @override
  String get projectStatus => 'Status';

  @override
  String get projectPriority => 'Priorytet';

  @override
  String get projectColor => 'Kolor';

  @override
  String get projectDueDate => 'Termin';

  @override
  String get projectDueDateClear => 'Wyczyść';

  @override
  String get projectBudget => 'Budżet';

  @override
  String get projectTargetCount => 'Docelowe płyty';

  @override
  String get projectTargetPartsCount => 'Docelowa liczba części';

  @override
  String get projectTags => 'Tagi (po przecinku)';

  @override
  String get projectUrl => 'Link';

  @override
  String get projectParent => 'Projekt nadrzędny';

  @override
  String get projectParentNone => 'Brak';

  @override
  String get projectSave => 'Zapisz';

  @override
  String get projectStatusPlanning => 'Planowanie';

  @override
  String get projectStatusActive => 'Aktywny';

  @override
  String get projectStatusOnHold => 'Wstrzymany';

  @override
  String get projectStatusCompleted => 'Ukończony';

  @override
  String get projectStatusArchived => 'Zarchiwizowany';

  @override
  String get projectPriorityLow => 'Niski';

  @override
  String get projectPriorityNormal => 'Normalny';

  @override
  String get projectPriorityHigh => 'Wysoki';

  @override
  String get projectPriorityUrgent => 'Pilny';

  @override
  String get projectTabOverview => 'Przegląd';

  @override
  String get projectTabArchives => 'Archiwa';

  @override
  String get projectTabBom => 'BOM';

  @override
  String get projectTabQueue => 'Kolejka';

  @override
  String get projectTabTimeline => 'Oś czasu';

  @override
  String get projectTabFiles => 'Pliki';

  @override
  String get projectTabAttachments => 'Załączniki';

  @override
  String get projectStatsTitle => 'Statystyki';

  @override
  String get projectStatProgress => 'Postęp';

  @override
  String get projectStatPartsProgress => 'Części';

  @override
  String get projectStatPrints => 'Płyty';

  @override
  String get projectStatCompleted => 'Ukończone';

  @override
  String get projectStatFailed => 'Nieudane';

  @override
  String get projectStatQueued => 'W kolejce';

  @override
  String get projectStatInProgress => 'W trakcie';

  @override
  String get projectStatPrintTime => 'Czas druku';

  @override
  String get projectStatFilament => 'Filament';

  @override
  String get projectStatCost => 'Szac. koszt';

  @override
  String get projectStatEnergy => 'Energia';

  @override
  String get projectStatEnergyCost => 'Koszt energii';

  @override
  String get projectStatRemaining => 'Pozostało';

  @override
  String get projectStatBom => 'BOM';

  @override
  String get projectChildren => 'Podprojekty';

  @override
  String get projectNoDescription => 'Brak opisu';

  @override
  String projectDueOn(String date) {
    return 'Termin $date';
  }

  @override
  String get projectAddArchives => 'Dodaj archiwa';

  @override
  String get projectRemoveArchive => 'Usuń z projektu';

  @override
  String get projectArchivesEmpty => 'Brak powiązanych archiwów';

  @override
  String get projectArchiveRemoved => 'Usunięto z projektu';

  @override
  String get archiveAddToProject => 'Dodaj do projektu';

  @override
  String get projectArchivesAdded => 'Dodano do projektu';

  @override
  String get projectPickTitle => 'Wybierz projekt';

  @override
  String get projectBomEmpty => 'Brak pozycji BOM';

  @override
  String get bomAdd => 'Dodaj pozycję';

  @override
  String get bomEditTitle => 'Edytuj pozycję';

  @override
  String get bomAddTitle => 'Nowa pozycja';

  @override
  String get bomName => 'Nazwa';

  @override
  String get bomQtyNeeded => 'Ilość';

  @override
  String get bomQtyAcquired => 'Posiadane';

  @override
  String get bomUnitPrice => 'Cena jedn.';

  @override
  String get bomSourcingUrl => 'Link do źródła';

  @override
  String get bomRemarks => 'Uwagi';

  @override
  String get bomComplete => 'Skompletowane';

  @override
  String get bomDelete => 'Usuń pozycję';

  @override
  String get bomDeleted => 'Pozycja usunięta';

  @override
  String get projectQueueEmpty => 'Brak elementów w kolejce';

  @override
  String get projectTimelineEmpty => 'Brak zdarzeń';

  @override
  String get projectAttachmentsEmpty => 'Brak załączników';

  @override
  String get projectFilesEmpty => 'Brak plików do druku';

  @override
  String get projectAttachmentUpload => 'Wgraj plik';

  @override
  String get projectAttachmentDownload => 'Pobierz';

  @override
  String get projectAttachmentDelete => 'Usuń';

  @override
  String get projectAttachmentDeleted => 'Załącznik usunięty';

  @override
  String get projectAttachmentUploaded => 'Załącznik wgrany';

  @override
  String projectFileSaved(String path) {
    return 'Zapisano w $path';
  }

  @override
  String get projectDownloadFailed => 'Pobieranie nie powiodło się';

  @override
  String get projectSaveCancelled => 'Anulowano zapis';

  @override
  String get projectCoverUpload => 'Ustaw okładkę';

  @override
  String get projectCoverDelete => 'Usuń okładkę';

  @override
  String get projectCoverUpdated => 'Okładka zaktualizowana';

  @override
  String get projectCoverRemoved => 'Okładka usunięta';

  @override
  String get projectMenuExport => 'Eksportuj';

  @override
  String get projectMenuCreateTemplate => 'Zapisz jako szablon';

  @override
  String get projectMenuImport => 'Importuj projekt';

  @override
  String get projectFromTemplate => 'Utwórz z szablonu';

  @override
  String get projectTemplateNone => 'Brak szablonów';

  @override
  String get projectTemplatePickTitle => 'Wybierz szablon';

  @override
  String get projectTemplateNamePrompt => 'Nazwa nowego projektu';

  @override
  String projectExported(String path) {
    return 'Wyeksportowano do $path';
  }

  @override
  String get projectExportFailed => 'Eksport nie powiódł się';

  @override
  String get projectTemplateCreated => 'Szablon utworzony';

  @override
  String get projectImported => 'Projekt zaimportowany';

  @override
  String get projectImportFailed => 'Import nie powiódł się';

  @override
  String get projectUploading => 'Wysyłanie…';

  @override
  String get projectLinkFolder => 'Podłącz folder';

  @override
  String get projectNoFoldersToLink => 'Brak folderów do podłączenia';

  @override
  String get projectUnlinkFolder => 'Odłącz folder';

  @override
  String get projectFolderLinked => 'Folder podłączony';

  @override
  String get projectFolderUnlinked => 'Folder odłączony';

  @override
  String get projectNotesEmpty => 'Brak notatek';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plików',
      many: '$count plików',
      few: '$count pliki',
      one: '$count plik',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    return 'pozostało $count';
  }

  @override
  String get sliceAction => 'Potnij';

  @override
  String get sliceTitle => 'Potnij plik';

  @override
  String get slicePrinter => 'Drukarka';

  @override
  String get sliceProcess => 'Proces / Jakość';

  @override
  String get sliceBedType => 'Płyta robocza';

  @override
  String get sliceBedDefault => 'Domyślna (z profilu)';

  @override
  String get sliceFilament => 'Filament';

  @override
  String sliceFilamentNumbered(String n) {
    return 'Filament $n';
  }

  @override
  String get sliceSelect => 'Dotknij, aby wybrać';

  @override
  String get sliceStart => 'Potnij';

  @override
  String get sliceShowAll => 'Wszystkie';

  @override
  String get sliceSearchHint => 'Szukaj profili';

  @override
  String get sliceOwnedEmpty =>
      'Brak pasujących profili dla Twojej drukarki i filamentów. Włącz „Wszystkie”, aby przeglądać pełny katalog.';

  @override
  String get sliceNoPresets => 'Brak dostępnych profili';

  @override
  String get sliceInProgress => 'Cięcie…';

  @override
  String get sliceDone => 'Cięcie zakończone';

  @override
  String get sliceFailed => 'Cięcie nie powiodło się';

  @override
  String get sliceClose => 'Zamknij';

  @override
  String sliceResultTime(String time) {
    return 'Szacowany czas: $time';
  }

  @override
  String sliceResultFilament(String grams) {
    return 'Filament: $grams g';
  }

  @override
  String get sliceTierLocal => 'Profil lokalny';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => 'Wbudowany';

  @override
  String get queueFilamentMapping => 'Mapowanie filamentów';

  @override
  String get mappingNoPrinter =>
      'Najpierw przypisz drukarkę do tej pozycji, aby mapować sloty AMS.';

  @override
  String get mappingNoSlots => 'Brak informacji o filamentach dla tego pliku.';

  @override
  String mappingNoAms(String printer) {
    return 'Brak filamentów w AMS drukarki $printer.';
  }

  @override
  String get mappingPickTray => 'Wybierz slot AMS';

  @override
  String get mappingExternalSpool => 'Szpula zewnętrzna';

  @override
  String mappingAmsSlot(String unit, String slot) {
    return 'AMS $unit · slot $slot';
  }

  @override
  String get mappingSaved => 'Zapisano mapowanie filamentów';

  @override
  String get plateClearTitle => 'Czy płyta jest pusta?';

  @override
  String get plateClearBody =>
      'Upewnij się, że płyta robocza jest pusta przed rozpoczęciem tego wydruku.';

  @override
  String get plateClearConfirm => 'Płyta jest pusta';

  @override
  String get plateClearAction => 'Oznacz płytę jako pustą';

  @override
  String get plateClearBadge => 'Płyta niewyczyszczona';

  @override
  String get plateClearedSnack => 'Oznaczono płytę jako pustą';

  @override
  String get pfmTitle => 'Menedżer plików';

  @override
  String get pfmTooltip => 'Pliki na drukarce';

  @override
  String pfmStorageUsed(String size) {
    return 'Użyto: $size';
  }

  @override
  String get pfmTabRoot => 'Główny';

  @override
  String get pfmTabCache => 'Cache';

  @override
  String get pfmTabModels => 'Modele';

  @override
  String get pfmTabTimelapse => 'Timelapse';

  @override
  String get pfmSearchHint => 'Filtruj pliki…';

  @override
  String get pfmSortTooltip => 'Sortuj';

  @override
  String get pfmRefreshTooltip => 'Odśwież';

  @override
  String get pfmSortNameAsc => 'Nazwa (A–Z)';

  @override
  String get pfmSortNameDesc => 'Nazwa (Z–A)';

  @override
  String get pfmSortSizeLargest => 'Rozmiar (największe)';

  @override
  String get pfmSortSizeSmallest => 'Rozmiar (najmniejsze)';

  @override
  String get pfmSortDateNewest => 'Data (najnowsze)';

  @override
  String get pfmSortDateOldest => 'Data (najstarsze)';

  @override
  String get pfmSelectAll => 'Zaznacz wszystko';

  @override
  String get pfmDeselectAll => 'Odznacz wszystko';

  @override
  String pfmSelected(int count) {
    return 'Zaznaczono: $count';
  }

  @override
  String get pfmEmpty => 'Ten folder jest pusty';

  @override
  String get pfmNoMatches => 'Brak plików pasujących do filtra';

  @override
  String get pfmDownload => 'Pobierz';

  @override
  String get pfmDelete => 'Usuń';

  @override
  String get pfmDownloadSaved => 'Zapisano plik';

  @override
  String get pfmDeleteConfirmTitle => 'Usunąć pliki?';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plików',
      few: '$count pliki',
      one: '$count plik',
    );
    return 'Trwale usunąć $_temp0 z drukarki? Tej operacji nie można cofnąć.';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plików',
      few: '$count pliki',
      one: '$count plik',
    );
    return 'Usunięto $_temp0';
  }

  @override
  String get wearConnectionFailed => 'Błąd połączenia';

  @override
  String get wearNoPrinters => 'Brak drukarek';

  @override
  String get wearPrinterUnavailable => 'Drukarka niedostępna';

  @override
  String get wearNoActions => 'Brak dostępnych akcji';

  @override
  String get wearClearPlate => 'Zwolnij płytę';

  @override
  String get wearPlateCleared => 'Płyta zwolniona';

  @override
  String get wearStarted => 'Uruchomiono';

  @override
  String get wearPhoneUnreachable => 'Telefon nieosiągalny';

  @override
  String get wearPhoneNoResponse => 'Telefon nie odpowiedział';

  @override
  String get wearConfirm => 'Potwierdź';

  @override
  String get wearServerUrl => 'Adres serwera';

  @override
  String get wearConnect => 'Połącz';

  @override
  String get wearAuthKey => 'Klucz';

  @override
  String get wearAuthLogin => 'Logowanie';

  @override
  String get wearUsername => 'Użytkownik';

  @override
  String get commonOn => 'Wł.';

  @override
  String get commonOff => 'Wył.';

  @override
  String get queueEdit => 'Edytuj';

  @override
  String get queueEditTitle => 'Edytuj pozycję kolejki';

  @override
  String get queueEditSave => 'Zapisz';

  @override
  String get queueEditSaved => 'Zaktualizowano pozycję kolejki';

  @override
  String get queueEditPrintJob => 'Zadanie druku';

  @override
  String get queueEditTarget => 'Cel';

  @override
  String get queueEditSpecificPrinter => 'Konkretna drukarka';

  @override
  String queueEditAnyModel(String model) {
    return 'Dowolna $model';
  }

  @override
  String get queueEditAnyModelGeneric => 'Dowolny model';

  @override
  String get queueEditTargetModel => 'Model';

  @override
  String get queueEditTargetLocation => 'Lokalizacja';

  @override
  String get queueEditAnyLocation => 'Dowolna lokalizacja';

  @override
  String get queueEditMappingNeedsPrinter =>
      'Wybierz drukarkę, aby zmapować filamenty';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slotu',
      many: '$count slotów',
      few: '$count sloty',
      one: '$count slot',
    );
    return 'Zmapowano $_temp0';
  }

  @override
  String get queueEditMappingAuto => 'Automatycznie (bez ręcznego mapowania)';

  @override
  String get queueEditPrintOptions => 'Opcje druku';

  @override
  String get queueOptBedLevelling => 'Poziomowanie stołu';

  @override
  String get queueOptBedLevellingDesc =>
      'Automatyczne poziomowanie przed drukiem';

  @override
  String get queueOptFlowCali => 'Kalibracja przepływu';

  @override
  String get queueOptFlowCaliDesc => 'Kalibracja przepływu ekstruzji';

  @override
  String get queueOptVibrationCali => 'Kalibracja drgań';

  @override
  String get queueOptVibrationCaliDesc => 'Redukcja artefaktów rezonansu';

  @override
  String get queueOptLayerInspect => 'Inspekcja pierwszej warstwy';

  @override
  String get queueOptLayerInspectDesc => 'Inspekcja AI pierwszej warstwy';

  @override
  String get queueOptTimelapse => 'Timelapse';

  @override
  String get queueOptTimelapseDesc => 'Nagrywanie filmu timelapse';

  @override
  String get queueOptNozzleOffset => 'Kalibracja offsetu dysz';

  @override
  String get queueOptNozzleOffsetDesc =>
      'Kalibracja offsetów dysz między ekstruderami';

  @override
  String get queueEditPreheat => 'Nagrzewanie i wygrzewanie';

  @override
  String get queueEditPreheatDesc =>
      'Nagrzej stół i komorę przed startem druku. Domyślnie z globalnego przełącznika Ustawienia → Workflow.';

  @override
  String get queuePreheatInherit => 'Dziedzicz';

  @override
  String get queueEditChamberTarget =>
      'Nadpisanie temp. komory (°C, puste = domyślna filamentu)';

  @override
  String get queueEditWhenToPrint => 'Kiedy drukować';

  @override
  String get queueScheduleAsap => 'ASAP';

  @override
  String get queueScheduleQueue => 'Kolejka';

  @override
  String get queueScheduleSchedule => 'Zaplanuj';

  @override
  String get queueEditPickTime => 'Wybierz datę i godzinę';

  @override
  String get queueEditRequireManualStart => 'Wymagaj ręcznego startu';

  @override
  String get queueEditRequirePrevious =>
      'Startuj tylko jeśli poprzedni druk się powiódł';

  @override
  String get queueEditPowerOff => 'Wyłącz drukarkę po zakończeniu';

  @override
  String get queueEditNoModel => 'Wybierz docelowy model';

  @override
  String get queueEditNoPrinter => 'Wybierz drukarkę';

  @override
  String get queueEditFilamentOverride => 'Nadpisanie filamentu';

  @override
  String get queueEditFilamentOverrideDesc =>
      'Opcjonalnie nadpisz filamenty dla przypisania po modelu. Scheduler dopasuje wybrane filamenty zamiast oryginalnych wartości z 3MF.';

  @override
  String get queueEditNoFilamentReqs =>
      'Brak wymagań filamentowych dla tego zadania.';

  @override
  String get queueEditOriginal => 'Oryginał';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return 'Slot $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => 'Wymuś zgodność koloru';
}
