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
  String get wsReconnecting => 'Wznawianie podglądu na żywo…';

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
      'Aby powiadomienia o wydruku działały, gdy aplikacja jest w tle, zezwól BambuBuddy na pracę bez ograniczeń baterii. Na telefonach Samsung to konieczne.';

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
  String get bgServiceTitle => 'BambuBuddy';

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
  String get inventoryNewSpool => 'Nowa szpula';

  @override
  String get inventoryEditSpool => 'Edytuj szpulę';

  @override
  String get inventorySave => 'Zapisz';

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
      'BamBuddy to wolne oprogramowanie wydane na licencji GNU Affero General Public License v3.0 (AGPL-3.0). Możesz go używać, badać, udostępniać i modyfikować; jeśli uruchamiasz zmodyfikowaną wersję jako usługę sieciową, musisz udostępnić jej źródła użytkownikom.';

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
}
