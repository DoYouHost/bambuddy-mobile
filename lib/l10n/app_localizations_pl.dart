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
  String get signInRequiredTitle => 'Zaloguj się ponownie';

  @override
  String get signInRequiredBody =>
      'Serwer odrzucił zapisane hasło, więc aplikacja przestała je wysyłać — kolejne próby blokują konto. Zaloguj się ponownie, a jeśli hasło zostało zmienione, podaj nowe.';

  @override
  String get signInRequiredAction => 'Zaloguj';

  @override
  String get signInRequiredTwoFactorBody =>
      'Konto wymaga teraz drugiego składnika, a aplikacja nie poda go w tle — więc przestała logować się sama. Zaloguj się ponownie i wpisz kod.';

  @override
  String get later => 'Później';

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
  String get filePickerFailed => 'Nie udało się otworzyć okna wyboru pliku';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get back => 'Wróć';

  @override
  String get searchPrinters => 'Szukaj drukarek…';

  @override
  String get noPrinters => 'Brak drukarek — dodaj je na serwerze';

  @override
  String noSearchResults(String query) {
    return 'Brak wyników dla „$query”';
  }

  @override
  String get noPrintersMatchFilters => 'Żadna drukarka nie pasuje do filtrów';

  @override
  String get dashboardFilters => 'Filtry';

  @override
  String get filterStatus => 'Status';

  @override
  String get filtersClear => 'Wyczyść';

  @override
  String get hideOffline => 'Ukryj offline';

  @override
  String get statusAll => 'Wszystkie';

  @override
  String get statusPrinting => 'Drukuje';

  @override
  String get statusIdle => 'Bezczynna';

  @override
  String get statusPaused => 'Wstrzymana';

  @override
  String get statusFinished => 'Zakończone';

  @override
  String get statusErrorFilter => 'Błąd';

  @override
  String get statusOfflineFilter => 'Offline';

  @override
  String get addPrinterTitle => 'Dodaj drukarkę';

  @override
  String get addPrinterName => 'Nazwa';

  @override
  String get addPrinterIp => 'Adres IP';

  @override
  String get addPrinterSerial => 'Numer seryjny';

  @override
  String get addPrinterAccessCode => 'Kod dostępu';

  @override
  String get addPrinterModel => 'Model';

  @override
  String get addPrinterModelOptional => 'Opcjonalnie';

  @override
  String get addPrinterModelNone => 'Nie ustawiono';

  @override
  String get addPrinterLocation => 'Lokalizacja';

  @override
  String get addPrinterLocationOptional => 'Opcjonalnie';

  @override
  String get addPrinterSubmit => 'Dodaj drukarkę';

  @override
  String get addPrinterConnectionNote =>
      'Serwer sprawdza połączenie przed zapisaniem, więc błędny adres IP lub kod dostępu zostanie zgłoszony i nic nie zostanie utworzone.';

  @override
  String get addPrinterRequiredField => 'Wymagane';

  @override
  String get addPrinterSuccess => 'Dodano drukarkę';

  @override
  String get addPrinterErrConnection =>
      'Nie udało się połączyć z drukarką. Sprawdź adres IP, numer seryjny i kod dostępu oraz upewnij się, że tryb LAN-only jest włączony.';

  @override
  String get addPrinterErrDuplicate =>
      'Drukarka o tym numerze seryjnym już istnieje';

  @override
  String get addPrinterErrForbidden =>
      'Nie masz uprawnień do dodawania drukarek';

  @override
  String get addPrinterErrGeneric =>
      'Nie udało się dodać drukarki. Spróbuj ponownie.';

  @override
  String get addPrinterAutoArchive =>
      'Automatycznie archiwizuj ukończone wydruki';

  @override
  String get addPrinterScanTitle => 'Znajdź drukarki w sieci';

  @override
  String get addPrinterSubnet => 'Podsieć do skanowania';

  @override
  String get addPrinterScanButton => 'Skanuj podsieć w poszukiwaniu drukarek';

  @override
  String get addPrinterDiscoverNetwork => 'Wyszukaj drukarki w sieci';

  @override
  String addPrinterScanning(int scanned, int total) {
    return 'Skanowanie… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => 'Skanowanie…';

  @override
  String get addPrinterScanNoResults => 'Nie znaleziono drukarek';

  @override
  String get addPrinterScanError =>
      'Skanowanie nie powiodło się. Spróbuj ponownie.';

  @override
  String get addPrinterSubnetCustomOption => 'Własna podsieć…';

  @override
  String get addPrinterSubnetCustomLabel => 'Własna podsieć (CIDR)';

  @override
  String get addPrinterSubnetDockerNote =>
      'Wykryto Docker. Podaj podsieć drukarki w notacji CIDR. Wymaga network_mode: host w docker-compose.yml.';

  @override
  String get addPrinterSubnetCustomNote =>
      'Użyj własnej podsieci, jeśli drukarka jest w innej sieci niż serwer. Porty FTP (990) i MQTT (8883) muszą być osiągalne przez granicę routingu.';

  @override
  String get addPrinterDiagnostic => 'Uruchom diagnostykę';

  @override
  String get addPrinterDiagnosticRunning => 'Trwa diagnostyka…';

  @override
  String get addPrinterDiagnosticError =>
      'Diagnostyka nie powiodła się. Spróbuj ponownie.';

  @override
  String get diagOverallOk => 'Wszystkie testy zaliczone';

  @override
  String get diagOverallWarnings => 'Ukończono z ostrzeżeniami';

  @override
  String get diagOverallProblems => 'Wykryto problemy';

  @override
  String get diagCheckPortMqtt => 'Port MQTT (8883)';

  @override
  String get diagCheckPortFtps => 'Port FTPS (990)';

  @override
  String get diagCheckPortRtsps => 'Port kamery (322)';

  @override
  String get diagCheckNetworkMode => 'Tryb sieci';

  @override
  String get diagCheckSubnet => 'Dostępność podsieci';

  @override
  String get diagCheckMqttAuth => 'Dane logowania MQTT';

  @override
  String get diagCheckDeveloperMode => 'Tryb deweloperski / LAN';

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
  String get ctrlFanPart => 'Wentylator chłodzący wydruk';

  @override
  String get ctrlFanAux => 'Wentylator pomocniczy';

  @override
  String get ctrlFanAux2 => 'Lewy wentylator pomocniczy';

  @override
  String get ctrlFanChamber => 'Wentylator komory';

  @override
  String get ctrlFanExhaust => 'Wentylator wyciągowy';

  @override
  String get ctrlFanPartShort => 'Wydruk';

  @override
  String get ctrlFanAuxShort => 'Pomoc.';

  @override
  String get ctrlFanAux2Short => 'Pomoc. L';

  @override
  String get ctrlFanChamberShort => 'Komora';

  @override
  String get ctrlFanExhaustShort => 'Wyciąg';

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
  String get ctrlOff => 'Wył.';

  @override
  String get ctrlSet => 'Ustaw';

  @override
  String get ctrlActivate => 'Aktywuj';

  @override
  String get ctrlNozzleActive => 'Aktywna';

  @override
  String get ctrlDry => 'Suszenie';

  @override
  String get ctrlDrying => 'Suszenie';

  @override
  String get ctrlDryStart => 'Start';

  @override
  String get ctrlDryFilament => 'Filament';

  @override
  String get ctrlDryTemp => 'Temperatura';

  @override
  String get ctrlDryDuration => 'Czas';

  @override
  String ctrlDryHours(int h) {
    return '$h godz';
  }

  @override
  String get ctrlDryAutoIdle => 'Auto-suszenie przy wysokiej wilgotności.';

  @override
  String get ctrlDryAutoQueue => 'Auto-suszenie między wydrukami.';

  @override
  String get ctrlDryAutoWhilePrinting => 'Także w druku.';

  @override
  String get ctrlDryStartWhen => 'Kiedy zacząć';

  @override
  String get ctrlDryStartNow => 'Teraz';

  @override
  String get ctrlDryStartAfter => 'Później';

  @override
  String get ctrlDryStartAt => 'O godzinie';

  @override
  String get ctrlDryPickTime => 'Wybierz termin';

  @override
  String get ctrlDrySchedule => 'Zaplanuj';

  @override
  String get ctrlDryScheduled => 'Suszenie zaplanowane';

  @override
  String get ctrlDryScheduleTimePast => 'Wybierz termin w przyszłości';

  @override
  String ctrlDryScheduledFor(String time) {
    return 'Suszenie: $time';
  }

  @override
  String get ctrlDryScheduledAsap => 'Suszenie zaplanowane, czeka na drukarkę';

  @override
  String get ctrlDryScheduleCancel => 'Anuluj zaplanowane suszenie';

  @override
  String get ctrlDryScheduleDismiss => 'Odrzuć';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return 'Zaplanowane suszenie nie ruszyło: $reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => 'nieznany błąd';

  @override
  String get ctrlDryWaitPower => 'Podłącz zasilacz AMS';

  @override
  String get ctrlDryWaitRetract => 'Wycofaj filament z wylotu AMS';

  @override
  String get ctrlDryWaitBlocked => 'AMS nie może teraz zacząć suszyć';

  @override
  String get ctrlDryWaitAmsNotFound => 'Czeka na wykrycie AMS';

  @override
  String get ctrlDryWaitOffline => 'Czeka na połączenie z drukarką';

  @override
  String get ctrlDryWaitBusy => 'Czeka, aż drukarka będzie wolna';

  @override
  String get ctrlDryWaitAlreadyDrying => 'Czeka na koniec trwającego cyklu';

  @override
  String get ctrlDryWaitInterrupted =>
      'Przerwane, wznowi się, gdy drukarka będzie wolna';

  @override
  String get ctrlMove => 'Ruch';

  @override
  String get ctrlMoveHome => 'Bazuj osie';

  @override
  String get ctrlMoveHomeStarted => 'Rozpoczęto bazowanie';

  @override
  String get ctrlMoveStep => 'Krok';

  @override
  String get ctrlMoveZ => 'Z (szczelina)';

  @override
  String get ctrlMoveZUp => 'W górę';

  @override
  String get ctrlMoveZDown => 'W dół';

  @override
  String get ctrlMoveExtruder => 'Ekstruder';

  @override
  String get ctrlMoveExtrude => 'Wytłocz';

  @override
  String get ctrlMoveRetract => 'Wycofaj';

  @override
  String get ctrlMoveLength => 'Długość';

  @override
  String ctrlMoveMm(int d) {
    return '$d mm';
  }

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
  String get ctrlForbidden => 'Brak uprawnień do sterowania tą drukarką';

  @override
  String get ctrlFailed => 'Nie udało się wysłać polecenia';

  @override
  String get skipObjectsTitle => 'Pomiń obiekty';

  @override
  String get skipObjectsSkip => 'Pomiń';

  @override
  String get skipObjectsSkippedTag => 'Pominięto';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pominięto $count obiektów',
      many: 'Pominięto $count obiektów',
      few: 'Pominięto $count obiekty',
      one: 'Pominięto „$names”',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pominąć $count obiektów?',
      many: 'Pominąć $count obiektów?',
      few: 'Pominąć $count obiekty?',
      one: 'Pominąć ten obiekt?',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '„$names” zostaną pominięte do końca tego wydruku. Nie można tego cofnąć.',
      one:
          '„$names” zostanie pominięty do końca tego wydruku. Nie można tego cofnąć.',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    return 'Zaznaczono: $count';
  }

  @override
  String get skipObjectsSelectHint =>
      'Dotknij obiektu powyżej lub poniżej, aby zaznaczyć go do pominięcia';

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
  String get smartPlugMonitorOnly => 'Tylko podgląd';

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
  String get queueAmsFromSlicer => 'AMS ze slicera';

  @override
  String queueAnyOfModels(String models) {
    return 'Dowolny z: $models';
  }

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
  String get archiveNoMatches => 'Żaden wydruk nie pasuje do filtrów';

  @override
  String get archiveFilters => 'Filtry';

  @override
  String get archiveFiltersClear => 'Wyczyść filtry';

  @override
  String get archiveSortLabel => 'Sortuj wg';

  @override
  String get archiveSortDateDesc => 'Najnowsze';

  @override
  String get archiveSortDateAsc => 'Najstarsze';

  @override
  String get archiveSortNameAsc => 'Nazwa A–Z';

  @override
  String get archiveSortNameDesc => 'Nazwa Z–A';

  @override
  String get archiveSortSizeDesc => 'Największe';

  @override
  String get archiveSortSizeAsc => 'Najmniejsze';

  @override
  String get archiveFilterFileType => 'Pliki';

  @override
  String get archiveFileTypeAll => 'Wszystkie';

  @override
  String get archiveFileTypeGcode => 'Pocięte';

  @override
  String get archiveFileTypeSource => 'Źródłowe';

  @override
  String get archiveFilterFlags => 'Pokaż';

  @override
  String get archiveFilterFavorites => 'Ulubione';

  @override
  String get archiveFilterHideFailed => 'Ukryj nieudane';

  @override
  String get archiveFilterHideDuplicates => 'Ukryj duplikaty';

  @override
  String get archiveFilterPrinter => 'Drukarka';

  @override
  String get archiveFilterMaterial => 'Materiał';

  @override
  String get archiveFilterColors => 'Kolory';

  @override
  String get archiveColorModeAny => 'Dowolny';

  @override
  String get archiveColorModeAll => 'Wszystkie';

  @override
  String get archiveFavorite => 'Dodaj do ulubionych';

  @override
  String get archiveUnfavorite => 'Usuń z ulubionych';

  @override
  String get archiveFavoriteFailed => 'Nie udało się zmienić ulubionego';

  @override
  String get archiveReprint => 'Drukuj ponownie';

  @override
  String get archiveAddToQueue => 'Dodaj do kolejki';

  @override
  String get archiveTimelapse => 'Obejrzyj timelapse';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zobacz zdjęcia ($count)',
      many: 'Zobacz zdjęcia ($count)',
      few: 'Zobacz zdjęcia ($count)',
      one: 'Zobacz zdjęcie',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaAction => 'Nagrania i zdjęcia';

  @override
  String get archiveMediaOnServer => 'Na serwerze';

  @override
  String archiveMediaOnPrinter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Na drukarce ($count)',
      zero: 'Na drukarce',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSearching => 'Szukam na drukarce…';

  @override
  String get archiveMediaNothingOnPrinter => 'Nic na drukarce';

  @override
  String archiveMediaPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zdjęcia',
      many: '$count zdjęć',
      few: '$count zdjęcia',
      one: 'jedno zdjęcie',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaKindTimelapse => 'Timelapse';

  @override
  String get archiveMediaKindIpcam => 'Kamera';

  @override
  String archiveMediaDownloadSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pliku',
      many: '$count plików',
      few: '$count pliki',
      one: 'jeden plik',
      zero: 'zaznaczone',
    );
    return 'Pobierz $_temp0';
  }

  @override
  String get archiveMediaSaved => 'Zapisano film';

  @override
  String get archiveMediaNoFilePermission =>
      'Brak uprawnień do plików drukarki';

  @override
  String get archiveMediaPrinterMissing => 'Drukarki już nie ma';

  @override
  String get archiveMediaTimelapseUnavailable =>
      'Timelapse: drukarka nie odpowiedziała';

  @override
  String get archiveMediaIpcamUnavailable =>
      'Kamera: drukarka nie odpowiedziała';

  @override
  String archivePlate(int plate) {
    return 'Płyta $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return 'Płyta $plate z pliku wielopłytowego';
  }

  @override
  String get archivePhotosTitle => 'Zdjęcia';

  @override
  String get archivePhotosEmpty => 'Ten wydruk nie ma zdjęć';

  @override
  String get archivePhotoFailed => 'Nie udało się wczytać tego zdjęcia.';

  @override
  String get archiveFilamentUsed => 'Zużycie filamentu';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zużyto $grams w $count przebiegach',
      many: 'Zużyto $grams w $count przebiegach',
      few: 'Zużyto $grams w $count przebiegach',
      one: 'Zużyto $grams',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => 'Bez zapisanego zużycia';

  @override
  String get archiveFilamentSaving => 'Zapisywanie';

  @override
  String get archiveFilamentNone => 'Nie zapisano';

  @override
  String get archiveFilamentLabel => 'Masa (g)';

  @override
  String get archiveFilamentNotANumber =>
      'Podaj liczbę albo zostaw puste, żeby wyczyścić masę.';

  @override
  String archiveFilamentOutOfRange(String max) {
    return 'Masa od 0 do $max g.';
  }

  @override
  String get archiveFilamentSaved => 'Zapisano masę filamentu';

  @override
  String get archiveFilamentUnsupported =>
      'Ten serwer nie zapisuje jeszcze ręcznie podanej masy filamentu. Zaktualizuj bambuddy.';

  @override
  String get archiveHasTimelapse => 'Ma timelapse';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ma $count zdjęć',
      many: 'Ma $count zdjęć',
      few: 'Ma $count zdjęcia',
      one: 'Ma zdjęcie',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => 'Timelapse';

  @override
  String get timelapseError => 'Nie udało się odtworzyć tego timelapse.';

  @override
  String timelapseHttpError(int status) {
    return 'Serwer nie wydał tego timelapse ($status).';
  }

  @override
  String get timelapseStalled =>
      'Serwer wydaje wideo, ale odtwarzacz go nie uruchomił.';

  @override
  String get timelapsePlay => 'Odtwórz';

  @override
  String get timelapsePause => 'Wstrzymaj';

  @override
  String get timelapseSave => 'Zapisz w galerii';

  @override
  String get timelapseShare => 'Udostępnij';

  @override
  String get timelapseSaved => 'Zapisano w galerii';

  @override
  String get timelapseSaveFailed => 'Nie udało się zapisać filmu';

  @override
  String get timelapseSaveDenied =>
      'Na tej wersji Androida zapis w galerii wymaga zgody na dostęp do plików.';

  @override
  String get timelapseEdit => 'Edytuj';

  @override
  String get timelapseEditSave => 'Zapisz';

  @override
  String get timelapseEditTitle => 'Edycja timelapse';

  @override
  String get timelapseEditTrim => 'Przycięcie';

  @override
  String get timelapseEditSpeed => 'Prędkość';

  @override
  String timelapseEditOutput(String length) {
    return 'Wynik: $length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return 'Oryginał: $length w $width×$height';
  }

  @override
  String get timelapseEditSaveTitle => 'Nadpisać nagranie?';

  @override
  String get timelapseEditSaveMessage =>
      'Serwer przekoduje timelapse i zastąpi oryginał. Nie ma kopii, do której da się wrócić.';

  @override
  String get timelapseEditProcessing =>
      'Serwer przekodowuje film. Na słabszym sprzęcie to kilka minut — wyjście z tego ekranu tego nie przerwie.';

  @override
  String get timelapseEdited => 'Timelapse zaktualizowany';

  @override
  String get gcodeViewerTitle => 'Podgląd G-code';

  @override
  String get gcodeViewerOpen => 'Podgląd G-code';

  @override
  String get gcodeViewerError => 'Nie udało się załadować podglądu G-code.';

  @override
  String get gcodeViewerLoading => 'Pobieranie G-code…';

  @override
  String get gcodeViewerParsing => 'Wczytywanie ścieżki narzędzia…';

  @override
  String get gcodeViewerTravels => 'Ruchy jałowe';

  @override
  String get gcodeViewerColorByFilament => 'Filament';

  @override
  String get gcodeViewerColorByFeature => 'Cechy';

  @override
  String get gcodeViewerColorByHeight => 'Wysokość';

  @override
  String get gcodeViewerColorByWidth => 'Szerokość';

  @override
  String get gcodeSingleLayer => 'jedna warstwa';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return 'Filament $n';
  }

  @override
  String get gcodeViewerEmpty =>
      'W tym pliku nie ma ścieżki narzędzia — nie został jeszcze pocięty.';

  @override
  String gcodeViewerHttpError(int status) {
    return 'Serwer nie wydał G-code tego pliku ($status).';
  }

  @override
  String get gcodeFeatureWall => 'Ściany';

  @override
  String get gcodeFeatureSparseInfill => 'Wypełnienie rzadkie';

  @override
  String get gcodeFeatureSolidInfill => 'Wypełnienie pełne';

  @override
  String get gcodeFeatureSkirt => 'Obwódka / rant';

  @override
  String get gcodeFeatureSupport => 'Podpory';

  @override
  String get gcodeFeatureGapFill => 'Wypełnianie szczelin';

  @override
  String get gcodeFeatureBridge => 'Mosty / nawisy';

  @override
  String get gcodeFeatureIroning => 'Prasowanie';

  @override
  String get gcodeFeaturePrimeTower => 'Wieża czyszcząca';

  @override
  String get archiveNo3mfTitle =>
      'Część ostatnich wydruków zarchiwizowała się bez miniatur';

  @override
  String get archiveNo3mfBody =>
      'Slicer nie zostawił pliku .gcode.3mf na karcie drukarki, więc Bambuddy nie miał skąd wziąć miniatury ani danych ze slicera. Zwykle znaczy to, że w slicerze (zakładka Device) jest wyłączone „Store sent files on external storage”.';

  @override
  String get archiveNo3mfTitleInternal =>
      'Część ostatnich wydruków została w pamięci wewnętrznej drukarki';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio wysłało pocięty plik do pamięci wewnętrznej drukarki, a nie na kartę — przez FTP nie ma tam czego czytać. W H2 i P2S przycisk Drukuj zawsze robi to tak, więc włączanie ustawienia w slicerze nic nie zmieni. Takie wydruki i tak trafiają do archiwum z nazwą i czasem, tylko bez miniatury i danych ze slicera. Żeby archiwum było pełne, zaczynaj wydruk z Bambuddy albo tnij w OrcaSlicerze — w obu przypadkach z kartą lub pendrivem w drukarce.';

  @override
  String get archiveNo3mfTitleNoStorage =>
      'Część ostatnich wydruków nie mogła się zarchiwizować — brak nośnika w drukarce';

  @override
  String get archiveNo3mfBodyNoStorage =>
      'Drukarka nie widzi karty ani pendrive\'a w gniazdzie, więc pocięty plik nie miał gdzie wylądować, a Bambuddy nie miał czego czytać. Włóż nośnik i kolejny wydruk zarchiwizuje się w całości.';

  @override
  String get archiveNo3mfDocs => 'Zobacz krok 4 instalacji';

  @override
  String get archiveNo3mfDocsWhy => 'Dlaczego tak się dzieje';

  @override
  String get archiveNo3mfDismiss => 'Zamknij tę informację';

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
  String get amsSlotFilament => 'Filament';

  @override
  String get amsLoad => 'Załaduj';

  @override
  String get amsUnload => 'Wyładuj';

  @override
  String get amsRfidReread => 'Odczytaj tag';

  @override
  String get amsLoadStarted => 'Ładowanie filamentu…';

  @override
  String get amsUnloadStarted => 'Wyładowywanie filamentu…';

  @override
  String get amsRfidRereadStarted => 'Ponowny odczyt tagu…';

  @override
  String amsFeedTitle(String slot) {
    return 'Do której dyszy podać $slot?';
  }

  @override
  String get amsFeedPrompt =>
      'Filament Track Switch może poprowadzić ten slot do obu dysz, więc drukarka sama nie ustali, dokąd ma trafić filament.';

  @override
  String get amsFeedAlreadyLoaded => 'już załadowany';

  @override
  String get amsSwitchNotReady =>
      'Filament Track Switch nie jest jeszcze skonfigurowany. Przypisz każdy AMS do wejścia na drukarce i spróbuj ponownie.';

  @override
  String get amsUnloadSlotNotLoaded =>
      'Z tego slotu nie jest zasilana żadna dysza';

  @override
  String get amsActionsWhilePrinting => 'Niedostępne, gdy drukarka drukuje';

  @override
  String get amsSlotConfigure => 'Skonfiguruj slot';

  @override
  String get amsSlotConfigTitle => 'Konfiguracja slotu';

  @override
  String get amsSlotConfigSearch => 'Szukaj presetu';

  @override
  String get amsSlotConfigColour => 'Kolor';

  @override
  String get amsSlotConfigApply => 'Zapisz w drukarce';

  @override
  String get amsSlotConfigStarted => 'Konfigurowanie slotu…';

  @override
  String get amsSlotConfigNameNotSaved =>
      'Slot skonfigurowany, ale nazwy presetu nie udało się zapisać';

  @override
  String get amsSlotConfigEmpty => 'Brak dostępnych presetów filamentu';

  @override
  String get amsSlotConfigNoMatch => 'Żaden preset nie pasuje do wyszukiwania';

  @override
  String get amsSlotConfigCloudHint =>
      'Zaloguj się do Bambu Cloud, żeby wybierać spośród własnych presetów.';

  @override
  String get amsSlotConfigCloudAction => 'Zaloguj';

  @override
  String get amsSlotConfigTierLocal => 'Zaimportowane';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => 'Wbudowane';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return 'Tylko dla $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return 'Tylko dla $model (ukryto $hidden)';
  }

  @override
  String get amsSlotConfigModelUnknown =>
      'Nieznany model drukarki — pokazuję wszystkie presety';

  @override
  String get amsSlotConfigCurrent => 'Ustawiony teraz';

  @override
  String get amsSlotConfigKProfile => 'Profil K';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return 'Domyślny (K $value)';
  }

  @override
  String get amsSlotConfigKProfileOther => 'Pozostałe profile';

  @override
  String get amsSlotConfigKProfileNone =>
      'Drukarka nie ma zapisanych profili K dla tej dyszy';

  @override
  String get amsSlotConfigKProfileUnavailable =>
      'Nie udało się odczytać profili K z drukarki';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return 'Drukarka nie podała średnicy dyszy — przyjmuję $diameter mm';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => 'Kolory z katalogu';

  @override
  String get amsSlotConfigColourCustom => 'Własny kolor';

  @override
  String get amsSlotReset => 'Wyczyść slot';

  @override
  String get amsSlotResetConfirmTitle => 'Wyczyścić slot?';

  @override
  String get amsSlotResetConfirmMessage =>
      'Drukarka zapomni skonfigurowany tu filament, a bambuddy zapomni, jaki to był preset.';

  @override
  String get amsSlotResetStarted => 'Czyszczenie slotu…';

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
  String get sensorHistoryCurrent => 'Aktualnie';

  @override
  String get sensorHistoryAverage => 'Średnia';

  @override
  String get sensorHistoryMin => 'Min';

  @override
  String get sensorHistoryMax => 'Maks';

  @override
  String get sensorHistoryRange6h => '6 h';

  @override
  String get sensorHistoryRange24h => '24 h';

  @override
  String get sensorHistoryRange48h => '48 h';

  @override
  String get sensorHistoryRange7d => '7 d';

  @override
  String get amsHistoryGood => 'Dobra';

  @override
  String get amsHistoryFair => 'Umiarkowana';

  @override
  String get sensorHistoryEmpty => 'Brak danych w tym zakresie';

  @override
  String get sensorHistoryError => 'Nie udało się wczytać historii';

  @override
  String get amsHistoryRecordingInfo =>
      'Zapisywane co 5 minut, gdy drukarka jest połączona';

  @override
  String get heaterHistoryTitle => 'Historia temperatur';

  @override
  String get heaterHistoryOpen => 'Historia temperatur';

  @override
  String get heaterHistoryReading => 'Odczyt';

  @override
  String get heaterHistoryTarget => 'Zadana';

  @override
  String get heaterHistoryRecordingInfo =>
      'Zapisywane co minutę, gdy drukarka jest połączona';

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
  String get twoFactorTitle => 'Uwierzytelnianie dwuskładnikowe';

  @override
  String get twoFactorMethodTotp => 'Aplikacja';

  @override
  String get twoFactorMethodEmail => 'E-mail';

  @override
  String get twoFactorMethodBackup => 'Kod zapasowy';

  @override
  String get twoFactorExplainTotp =>
      'Wpisz 6-cyfrowy kod z aplikacji uwierzytelniającej.';

  @override
  String get twoFactorExplainEmail =>
      'Poproś serwer o wysłanie 6-cyfrowego kodu na e-mail i wpisz go tutaj.';

  @override
  String get twoFactorExplainEmailSent =>
      '6-cyfrowy kod poszedł na adres przypisany do konta. Wygasa po 10 minutach.';

  @override
  String get twoFactorExplainBackup =>
      'Wpisz jeden z 8-znakowych kodów zapasowych zapisanych przy włączaniu 2FA. Każdy działa raz.';

  @override
  String get twoFactorCodeLabel => 'Kod';

  @override
  String get twoFactorSendEmail => 'Wyślij kod na e-mail';

  @override
  String get twoFactorResendEmail => 'Wyślij kolejny kod';

  @override
  String get twoFactorVerify => 'Potwierdź i połącz';

  @override
  String get twoFactorBack => 'Zaloguj się na inne konto';

  @override
  String get twoFactorSessionNote =>
      'Aplikacja nie odnowi sesji z 2FA sama, więc po jej wygaśnięciu zapyta ponownie. Klucz API nie wygasa i pomija ten krok.';

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
      'Brak uprawnień — serwer odmówił wykonania tej akcji';

  @override
  String errForbiddenDetail(String reason) {
    return 'Brak uprawnień: $reason';
  }

  @override
  String get errApiKeyOwnerDisabled =>
      'Konto właściciela tego klucza API zostało wyłączone lub usunięte — klucz będzie odrzucany, dopóki to konto nie wróci.';

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
  String get errTwoFactorCodeRejected =>
      'Zły kod — sprawdź go i spróbuj ponownie.';

  @override
  String get errTwoFactorChallengeExpired =>
      'Próba logowania wygasła — podaj hasło jeszcze raz, żeby dostać nowy kod.';

  @override
  String get errTwoFactorMethodUnavailable =>
      'Ta metoda nie jest dostępna na tym koncie — wybierz inną.';

  @override
  String get errTwoFactorEmailUnavailable =>
      'Serwer nie wysłał kodu — nie ma skonfigurowanej poczty albo konto nie ma adresu. Użyj innej metody.';

  @override
  String get errMissingTwoFactorCode => 'Wpisz kod';

  @override
  String get errApiKeyRejected =>
      'Klucz API odrzucony — sprawdź klucz i jego scope (wymagany can_read_status)';

  @override
  String get errTooManyAttempts =>
      'Za dużo prób — serwer blokuje logowanie na kilka minut. Odczekaj i spróbuj ponownie albo użyj klucza API.';

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
  String get notifExtrasHeader => 'Szczegóły';

  @override
  String get notifFinishPhotoTitle => 'Zdjęcie skończonego wydruku';

  @override
  String get notifFinishPhotoDesc =>
      'Dokłada do powiadomienia o zakończeniu lub błędzie zdjęcie, które serwer robi po wydruku — gdy tylko dojdzie';

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
  String get hmsErrorsHeader => 'Aktywne błędy';

  @override
  String get hmsViewInWiki => 'Otwórz w wiki Bambu';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count błędu',
      many: '$count błędów',
      few: '$count błędy',
      one: '1 błąd',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => 'Odrzuć wszystkie';

  @override
  String get hmsDismissed => 'Błędy wyczyszczone na drukarce';

  @override
  String get hmsDismissFailed => 'Nie udało się wyczyścić błędów';

  @override
  String get hmsActionSent => 'Wysłano do drukarki';

  @override
  String get hmsActionFailed => 'Drukarka odrzuciła akcję';

  @override
  String get hmsActionNotAcknowledged =>
      'Drukarka nie potwierdziła akcji — sprawdź jej ekran';

  @override
  String get hmsStopConfirmTitle => 'Zatrzymać wydruk?';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer porzuci bieżące zadanie. Tego nie da się cofnąć.';
  }

  @override
  String get hmsStopConfirmAction => 'Zatrzymaj wydruk';

  @override
  String get hmsActionResume => 'Wznów';

  @override
  String get hmsActionResumeDefects => 'Wznów mimo wad';

  @override
  String get hmsActionResumeSolved => 'Naprawione, wznów';

  @override
  String get hmsActionProblemSolvedResume => 'Naprawione, wznów';

  @override
  String get hmsActionFilamentLoadedResume => 'Załadowany, wznów';

  @override
  String get hmsActionProceed => 'Kontynuuj';

  @override
  String get hmsActionStopPrinting => 'Zatrzymaj';

  @override
  String get hmsActionIgnoreResume => 'Zignoruj i wznów';

  @override
  String get hmsActionIgnoreNoReminder => 'Zignoruj na stałe';

  @override
  String get hmsActionDontRemind => 'Nie przypominaj';

  @override
  String get hmsActionNoReminder => 'Ukryj ostrzeżenie';

  @override
  String get hmsActionFilamentExtruded => 'Wytłoczony';

  @override
  String get hmsActionRetryFilamentExtruded => 'Jeszcze nie, ponów';

  @override
  String get hmsActionContinue => 'Gotowe, kontynuuj';

  @override
  String get hmsActionRetrySolved => 'Naprawione, ponów';

  @override
  String get hmsActionDone => 'Gotowe';

  @override
  String get hmsActionRetry => 'Ponów';

  @override
  String get hmsActionResumePlain => 'Wznów';

  @override
  String get hmsActionConfirm => 'Potwierdź';

  @override
  String get hmsActionAbort => 'Przerwij';

  @override
  String get hmsActionOk => 'OK';

  @override
  String get hmsActionRecheck => 'Sprawdź';

  @override
  String get hmsActionTurnOffFireAlarm => 'Wyłącz alarm';

  @override
  String get hmsActionStopDrying => 'Zatrzymaj suszenie';

  @override
  String get hmsActionDisablePurification => 'Wyłącz oczyszczanie';

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
  String inventoryTotalConsumed(String weight) {
    return 'zużyto $weight';
  }

  @override
  String inventoryConsumedSinceReset(String weight) {
    return 'Zużyte od resetu: $weight';
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
  String get inventorySectionPrinterPresets => 'Presety wg modelu drukarki';

  @override
  String get inventoryPrinterPresetsHint =>
      'Wybór tutaj wygrywa z presetem szpuli.';

  @override
  String get inventoryPrinterPresetDefault => 'Jak na szpuli';

  @override
  String inventoryPrinterPresetNozzle(String model, String diameter) {
    return '$model · dysza $diameter';
  }

  @override
  String get inventoryPrinterPresetsLoadFailed =>
      'Nie odczytano — zapis ich nie ruszy.';

  @override
  String get inventoryPrinterPresetsSaveFailed =>
      'Szpula zapisana, presety wg modelu — nie.';

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
  String inventoryFieldRange(int min, int max) {
    return 'Podaj wartość od $min do $max';
  }

  @override
  String get inventoryFieldNegative => 'Podaj wartość 0 lub większą';

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
      'Wyzerować licznik zużytego filamentu? Kolejne wydruki znów będą liczone od zera — pozostała waga zostaje bez zmian.';

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
  String get inventoryUsageReset => 'Wyzerowano licznik';

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
  String get inventoryFromSlot => 'Dodaj do magazynu';

  @override
  String get inventoryFromSlotHint =>
      'Zapisz szpulę z czipem, którą drukarka widzi w tym slocie';

  @override
  String get inventoryFromSlotDone => 'Szpula dodana i przypisana do slotu';

  @override
  String get inventoryFromSlotNoTag =>
      'Drukarka nie widzi już w tym slocie szpuli z czipem';

  @override
  String get inventoryFromSlotOffline =>
      'Drukarka nie jest połączona, więc nie powie, co jest w slocie';

  @override
  String get inventoryFromSlotUnsupported =>
      'Ta wersja serwera nie potrafi dodać szpuli prosto ze slotu';

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
  String get inventoryBulkResetBody =>
      'Ich liczniki zużytego filamentu wrócą do zera. Pozostałe wagi zostają bez zmian.';

  @override
  String inventoryBulkDone(int count) {
    return 'Zaktualizowano: $count';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return 'Udało się: $ok, błędów: $failed';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return 'Udało się: $ok, już tak było: $skipped';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return 'Udało się: $ok, już tak było: $skipped, błędów: $failed';
  }

  @override
  String get inventoryBulkEdit => 'Edytuj pola';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count szpul',
      one: 'szpuli',
    );
    return 'Edycja $_temp0';
  }

  @override
  String get inventoryBulkEditHint =>
      'Zmieniają się tylko pola, które wypełnisz. Reszta zostaje bez zmian.';

  @override
  String get inventoryBulkEditUnchanged => 'Bez zmian';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count szpul',
      one: 'szpuli',
    );
    return 'Zastosuj do $_temp0';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'szpul',
      few: 'szpule',
      one: 'szpulę',
    );
    return 'Zmienić $_temp0?';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: '$fields pól',
      few: '$fields pola',
      one: 'Jedno pole',
    );
    return '$_temp0 zostanie nadpisane w każdej wybranej szpuli.';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      'Ten serwer jest za stary na edycję masową. Zaktualizuj bambuddy albo edytuj szpule pojedynczo.';

  @override
  String get inventoryApply => 'Zastosuj';

  @override
  String get inventoryLabelsTitle => 'Drukuj etykiety szpul';

  @override
  String get inventoryLabelsPrint => 'Drukuj etykiety';

  @override
  String get inventoryLabelsPrintAll => 'Drukuj etykiety wszystkich';

  @override
  String get inventoryClimateTitle => 'Warunki przechowywania';

  @override
  String get inventoryClimateTitleAlerting =>
      'Warunki przechowywania: poza zakresem alertu';

  @override
  String get inventoryClimateSource =>
      'Serwer odczytuje je z Home Assistant. Czujniki przypisuje się do miejsca w interfejsie webowym Bambuddy.';

  @override
  String get inventoryClimateNoReading => 'brak odczytu';

  @override
  String inventoryClimateReading(String name, String value) {
    return '$name: $value';
  }

  @override
  String inventoryClimateReadingAlerting(String name, String value) {
    return '$name: $value, poza zakresem alertu';
  }

  @override
  String inventoryClimateReadingStale(String name, String value) {
    return '$name: $value, czujnik nieosiągalny';
  }

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
  String get inventoryLabelsStartTitle => 'Pierwsza wolna etykieta';

  @override
  String get inventoryLabelsStartHint =>
      'Dotknij pola, w którym ma się wydrukować pierwsza etykieta — wcześniejsze zostaną puste, więc napoczęty arkusz da się dokończyć zamiast zaczynać nowy.';

  @override
  String inventoryLabelsStartSlot(int position) {
    return 'Pozycja $position';
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
  String get statsEnergyOverTime => 'Energia w czasie';

  @override
  String get statsMostEnergy => 'Najwięcej energii';

  @override
  String statsKwh(String value) {
    return '$value kWh';
  }

  @override
  String get statsByMaterialTitle => 'Wg materiału';

  @override
  String get statsSuccessByMaterial => 'Skuteczność wg materiału';

  @override
  String get statsColorDistribution => 'Rozkład kolorów';

  @override
  String get statsColorShareHint => 'Udział zużytego filamentu, wagowo';

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
  String get aboutSourceBody => 'Pełne źródła są dostępne na GitHubie.';

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
  String get fmAddToQueue => 'Dodaj do kolejki';

  @override
  String get fmAddedToQueue => 'Dodano do kolejki';

  @override
  String get fmGroupAsVariants => 'Zgrupuj jako warianty';

  @override
  String get fmQueueAsVariants => 'Dodaj do kolejki jako jedno zadanie';

  @override
  String get fmUngroupVariants => 'Rozgrupuj warianty';

  @override
  String fmVariantsGrouped(int count) {
    return 'Zgrupowano $count plików jako warianty';
  }

  @override
  String get fmVariantsUngrouped => 'Rozgrupowano warianty';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count wariantów';
  }

  @override
  String get fmVariantsGone => 'Ta grupa już nie istnieje';

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
  String get fmTags => 'Tagi';

  @override
  String get fmTagsFilterTitle => 'Filtruj po tagach';

  @override
  String get fmTagsFilterHint =>
      'Tagi przeszukują całą bibliotekę — bieżący folder nie ma znaczenia.';

  @override
  String get fmTagsManage => 'Zarządzaj tagami';

  @override
  String get fmTagsEmpty => 'Nie ma jeszcze tagów';

  @override
  String get fmTagsNone => 'Bez tagów';

  @override
  String get fmTagsApply => 'Zastosuj';

  @override
  String get fmTagNew => 'Nowy tag';

  @override
  String get fmTagName => 'Nazwa tagu';

  @override
  String get fmTagRename => 'Zmień nazwę tagu';

  @override
  String get fmTagDelete => 'Usuń tag';

  @override
  String fmTagDeleteConfirm(String name) {
    return 'Usunąć tag „$name\"? Pliki zostają — tracą tylko tę etykietę.';
  }

  @override
  String get fmTagCreated => 'Tag utworzony';

  @override
  String get fmTagDeleted => 'Tag usunięty';

  @override
  String get fmTagExists => 'Tag o tej nazwie już istnieje';

  @override
  String get fmTagsSaved => 'Tagi zapisane';

  @override
  String fmTagsPartial(int count, int total) {
    return 'Zmieniono $count z $total plików — pozostałych nie możesz edytować';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pliku',
      many: 'plików',
      few: 'pliki',
      one: 'plik',
    );
    return 'Otaguj $count $_temp0';
  }

  @override
  String get fmTagsAdd => 'Dodaj';

  @override
  String get fmTagsRemove => 'Usuń';

  @override
  String get fmTagsReplace => 'Zastąp';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pliku',
      many: 'plikach',
      few: 'plikach',
      one: 'pliku',
    );
    return 'Zastąpić wszystkie tagi na $count $_temp0 wybranymi?';
  }

  @override
  String get fmTagsPickSome => 'Wybierz przynajmniej jeden tag';

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
  String get projectTargetSets => 'Docelowa liczba kompletów';

  @override
  String get projectTargetSetsHint =>
      'Ile razy ma zostać wydrukowany każdy plik projektu';

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
  String get projectStatSets => 'Pełne komplety';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done z $target';
  }

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
  String get sliceAutoOrient => 'Automatyczna orientacja';

  @override
  String get sliceAutoOrientHint =>
      'Obraca obiekty na najlepszą stronę do druku.';

  @override
  String get sliceAutoArrange => 'Automatyczne rozmieszczenie';

  @override
  String get sliceAutoArrangeHint => 'Rozkłada obiekty na stole od nowa.';

  @override
  String sliceDesignedFor(String printer) {
    return 'Plik jest pod $printer';
  }

  @override
  String get sliceUseDesignedPrinter => 'Przełącz';

  @override
  String get sliceAsDesigned => 'Użyj ustawień z pliku';

  @override
  String get sliceAsDesignedHint =>
      'Ustawienia projektanta zamiast profili powyżej.';

  @override
  String get sliceAsDesignedInactive => 'Nieużywane — decyduje plik';

  @override
  String get sliceFilamentUnused => 'Nieużywany na tej płycie';

  @override
  String get processSettingsTitle => 'Ustawienia procesu';

  @override
  String get sliceProcessSettingsNeedsProcess =>
      'Najpierw wybierz preset procesu';

  @override
  String get sliceProcessSettingsUnchanged => 'Preset bez zmian';

  @override
  String sliceProcessSettingsChanged(int count) {
    return 'Zmienione: $count';
  }

  @override
  String get processSettingsModeSimple => 'Proste';

  @override
  String get processSettingsModeAdvanced => 'Zaawansowane';

  @override
  String get processSettingsModeExpert => 'Eksperckie';

  @override
  String get processSettingsSearchHint => 'Szukaj ustawień';

  @override
  String get processSettingsNoMatches =>
      'Żadne ustawienie nie pasuje do zapytania.';

  @override
  String get processSettingsRevert => 'Przywróć wartość z presetu';

  @override
  String processSettingsRevertAll(int count) {
    return 'Przywróć $count';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return 'Slicer przyjmuje $range';
  }

  @override
  String get processSettingsDisabledHint =>
      'Przy obecnych ustawieniach slicer to pomija.';

  @override
  String get processSettingsUnavailable =>
      'Ten serwer nie potrafi podać ustawień procesu dla wybranego presetu.';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      'Pokazujemy wartości domyślne slicera: kontener slicera jest starszy niż ta funkcja i nie potrafi podać wartości presetu. Zaktualizuj jego obraz, żeby je zobaczyć. Wszystko, czego nie zmienisz, nadal bierze się z presetu.';

  @override
  String get processSettingsDefaultsNotConfigured =>
      'Pokazujemy wartości domyślne slicera: żaden kontener slicera nie jest skonfigurowany, więc nie da się odczytać wartości presetu. Wszystko, czego nie zmienisz, nadal bierze się z presetu.';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      'Pokazujemy wartości domyślne slicera: kontener slicera nie odpowiedział, więc nie da się odczytać wartości presetu. Wszystko, czego nie zmienisz, nadal bierze się z presetu.';

  @override
  String get processSettingsDefaultsUnavailable =>
      'Pokazujemy wartości domyślne slicera: nie udało się odczytać własnych wartości wybranego presetu. Wszystko, czego nie zmienisz, nadal bierze się z presetu.';

  @override
  String get processSettingsFilamentDefault =>
      'Domyślny (filament danego obszaru)';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot: $name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return 'Slot $slot — ten plik nie ma takiego slotu';
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
  String get sliceExternalFallback =>
      'Zapisano w bibliotece serwera — folder tego pliku nie mógł go przyjąć.';

  @override
  String get sliceExternalReadonly => 'Ten folder jest tylko do odczytu.';

  @override
  String get sliceExternalNoPath => 'Ten folder nie ma ustawionej ścieżki.';

  @override
  String get sliceExternalUnreachable =>
      'Ścieżka tego folderu jest teraz nieosiągalna.';

  @override
  String get sliceExternalNotWritable =>
      'Serwer nie ma prawa zapisu do tego folderu.';

  @override
  String get sliceExternalInvalidName =>
      'Ten folder nie przyjąłby nazwy tego pliku.';

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
  String get plateClearNeedsOnline =>
      'Ten serwer zwalnia płytę tylko przy podłączonej drukarce. Zaktualizuj bambuddy, aby robić to na wyłączonej.';

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
  String get pfmUp => 'Folder wyżej';

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
  String get pfmPrinterUnavailable =>
      'Drukarka nie odpowiedziała, więc nie udało się wylistować jej plików';

  @override
  String get pfmDownloadTooLarge =>
      'Wybór jest za duży, żeby serwer spakował go w paczkę';

  @override
  String get pfmDownloadNoServerSpace =>
      'Serwer nie ma miejsca na przygotowanie tego pobrania';

  @override
  String get pfmDownloadTookTooLong =>
      'Przygotowanie pobrania trwało zbyt długo i serwer je przerwał';

  @override
  String get pfmPreparingOnServer => 'Przygotowywanie na serwerze…';

  @override
  String get pfmDownloading => 'Pobieranie…';

  @override
  String get pfmDownloadCancelled => 'Pobieranie anulowane';

  @override
  String get pfmDownloadPrepareFailed =>
      'Serwer nie zdołał przygotować tego pobierania';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plików',
      few: '$count pliki',
      one: '$count plik',
    );
    return 'Pominięto $_temp0, których nie udało się odczytać z drukarki';
  }

  @override
  String get pfmDownloadSaved => 'Zapisano plik';

  @override
  String get pfmDownloadNotSaved =>
      'Nie udało się zapisać pliku we wskazanym miejscu';

  @override
  String get pfmDownload => 'Pobierz';

  @override
  String get pfmDelete => 'Usuń';

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
  String get wearPlateNeedsOnline => 'Ten serwer wymaga drukarki online';

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
  String get wearSetupPhoneTitle => 'Ustaw z telefonu';

  @override
  String get wearSetupPhoneBody =>
      'Otwórz Bambuddy na sparowanym telefonie — zegarek sam pobierze z niego serwer i logowanie.';

  @override
  String get wearSetupPhoneCheck => 'Sprawdź ponownie';

  @override
  String get wearSetupPhoneEmpty => 'Telefon jeszcze nic nie przysłał.';

  @override
  String get wearSetupManual => 'Wpisz ręcznie';

  @override
  String get wearSetupDemo => 'Demo';

  @override
  String get wearSetupTapToType => 'Dotknij, aby wpisać';

  @override
  String get wearSettingsTitle => 'Ustawienia';

  @override
  String get wearFromPhone => 'Z telefonu';

  @override
  String get wearFromPhoneUse => 'Użyj tego serwera';

  @override
  String get wearFromPhoneLater => 'Nie teraz';

  @override
  String get wearAuthNone => 'Bez logowania';

  @override
  String get wearFromPhoneWaiting => 'Telefon proponuje inny serwer.';

  @override
  String get wearCurrentServer => 'Obecny serwer';

  @override
  String get wearOk => 'OK';

  @override
  String get commonOn => 'Wł.';

  @override
  String get commonOff => 'Wył.';

  @override
  String get commonAuto => 'Auto';

  @override
  String get queueEdit => 'Edytuj';

  @override
  String get queueEditTitle => 'Edytuj pozycję kolejki';

  @override
  String get queueEditSave => 'Zapisz';

  @override
  String get queueEditSaved => 'Zaktualizowano pozycję kolejki';

  @override
  String get queueCreateTitle => 'Drukuj';

  @override
  String get queueCreateSubmit => 'Drukuj';

  @override
  String get queueCreateAdded => 'Dodano do kolejki';

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
  String get queueEditPlate => 'Płyta';

  @override
  String queueEditPlateSelected(int plate) {
    return 'Płyta $plate';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return 'Płyta $plate · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return 'To zadanie drukuje płytę $plate';
  }

  @override
  String get queuePlatePickTitle => 'Która płyta?';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count obiektu',
      many: '$count obiektów',
      few: '$count obiekty',
      one: '1 obiekt',
      zero: 'Brak obiektów',
    );
    return '$_temp0';
  }

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
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

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
  String get queueEditGcodeInjection => 'Wstrzyknij G-code auto-druku';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return 'Brak G-code dla modelu $model — nic nie zostanie wstrzyknięte.';
  }

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

  @override
  String get queueEditNozzleRack => 'Magazyn dysz';

  @override
  String get queueEditNozzleRackDesc =>
      'Wybierz, z której dyszy w magazynie drukuje każdy filament. Bez wyboru pasująca pozycja zostanie dobrana przy starcie wydruku.';

  @override
  String queueEditRackGroupLabel(String slots, String nozzle) {
    return 'Filament $slots · $nozzle';
  }

  @override
  String get queueEditRackAuto => 'Automatycznie';

  @override
  String queueEditRackPosition(int position, String nozzle) {
    return 'Pozycja $position · $nozzle';
  }

  @override
  String queueEditRackPositionTaken(int position, String nozzle) {
    return 'Pozycja $position · $nozzle — już wybrana';
  }

  @override
  String queueEditRackPositionUnfit(int position, String nozzle) {
    return 'Pozycja $position · $nozzle — nie pasuje';
  }

  @override
  String get queueEditRackEmpty => 'pusta';

  @override
  String get queueEditRackPickStale =>
      'Wybrana pozycja już nie pasuje do tego filamentu — wybierz inną, inaczej wydruk zostanie odrzucony przy starcie.';

  @override
  String queueEditRackNoFit(String nozzle) {
    return 'Żadna pozycja w magazynie nie ma dyszy $nozzle — włóż taką albo drukarka wybierze sama.';
  }

  @override
  String get nozzleFlowStandard => 'Standardowa';

  @override
  String get nozzleFlowHigh => 'Wysoki przepływ';

  @override
  String get bugReportMenu => 'Zgłoś błąd lub pomysł';

  @override
  String get bugReportTitle => 'Zgłoś błąd lub pomysł';

  @override
  String get bugReportIntroHeader => 'Jak to działa';

  @override
  String get bugReportStepRecord => 'Włącz nagrywanie';

  @override
  String get bugReportStepReproduce => 'Odtwórz problem';

  @override
  String get bugReportStepFinish => 'Wróć tutaj i zakończ';

  @override
  String get bugReportLogScreens => 'Otwierane ekrany i naciskane przyciski';

  @override
  String get bugReportLogRequests => 'Zapytania do serwera i jego odpowiedzi';

  @override
  String get bugReportLogService =>
      'Podgląd na żywo i to, które powiadomienia usługa w tle wystawiła, a które pominęła';

  @override
  String get bugReportLogErrors =>
      'Błędy i awarie, także te, których nie widzisz';

  @override
  String get bugReportLogSetup =>
      'Wersja aplikacji i serwera, Twój telefon, Twój język';

  @override
  String get bugReportLogNoKey => 'Klucz API ani hasło';

  @override
  String get bugReportLogNoTyping => 'Tekst, który wpisujesz';

  @override
  String get bugReportLogNoAddress =>
      'Adres serwera — tylko http albo https, nazwa albo IP, i port';

  @override
  String get bugReportLogNoData =>
      'Numery seryjne drukarek ani nazwy Twoich plików, modeli i szpul';

  @override
  String get bugReportReviewFirst => 'Wszystko czytasz, zanim opuści telefon.';

  @override
  String get bugReportPrivacyHeader => 'Co trafia do logu';

  @override
  String get bugReportStart => 'Rozpocznij nagrywanie';

  @override
  String get bugReportRecordingHeader => 'Nagrywanie trwa';

  @override
  String get bugReportRecordingBody =>
      'Wróć do aplikacji i odtwórz problem. Pasek nagrywania zostaje z Tobą — przesuń go albo zwiń, jeśli zasłania. Oznacz nim moment awarii i zakończ nagrywanie.';

  @override
  String get bugReportMark => 'Oznacz moment';

  @override
  String get bugReportMarked => 'Moment oznaczony';

  @override
  String get bugReportStop => 'Zakończ nagrywanie';

  @override
  String get bugReportStopShort => 'Zakończ';

  @override
  String get bugReportBannerLabel => 'Nagrywanie';

  @override
  String get bugReportBarMove => 'Przesuń pasek nagrywania';

  @override
  String get bugReportBarCollapse => 'Zwiń pasek nagrywania';

  @override
  String get bugReportBarExpand => 'Rozwiń pasek nagrywania';

  @override
  String get bugReportReviewHeader => 'Przejrzyj przed wysłaniem';

  @override
  String get bugReportReviewBody =>
      'To wszystko, co zostało nagrane. Przejrzyj to — poniżej wybierasz, czy log zostaje w telefonie, czy idzie jako publiczne zgłoszenie.';

  @override
  String bugReportSummary(int records, int errors, int warnings) {
    return '$records rekordów · $errors błędów · $warnings ostrzeżeń';
  }

  @override
  String bugReportMarkers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count oznaczonych momentów',
      few: '$count oznaczone momenty',
      one: '1 oznaczony moment',
    );
    return '$_temp0';
  }

  @override
  String get bugReportTruncated =>
      'Sesja była długa — najstarsze rekordy zostały odrzucone.';

  @override
  String get bugReportEmpty => 'Nic nie zostało nagrane.';

  @override
  String get bugReportShowRaw => 'Pokaż surowy log';

  @override
  String get bugReportHideRaw => 'Ukryj surowy log';

  @override
  String bugReportRawClipped(int kb) {
    return 'Pierwsze $kb kB nie są tu pokazane. Zapisany plik zawiera całą sesję.';
  }

  @override
  String get bugReportSave => 'Zapisz do pliku';

  @override
  String get bugReportSaveShort => 'Zapisz';

  @override
  String get bugReportSaved => 'Log zapisany do pliku';

  @override
  String get bugReportSaveFailed => 'Nie udało się zapisać loga.';

  @override
  String get bugReportDiscard => 'Odrzuć';

  @override
  String get bugReportDiscardQuestion => 'Odrzucić to nagranie?';

  @override
  String get bugReportDiscardBody => 'Log zostanie usunięty z telefonu.';

  @override
  String get bugReportDiscardBodyQueued =>
      'Log zostanie usunięty z telefonu, a zakolejkowana wysyłka anulowana.';

  @override
  String bugReportLimit(int minutes) {
    return 'Nagrywanie zatrzyma się samo po $minutes min.';
  }

  @override
  String bugReportLimitReached(int minutes) {
    return 'Nagrywanie zakończone — minął limit $minutes min.';
  }

  @override
  String bugReportSizeLimitReached(int megabytes) {
    return 'Nagrywanie zakończone — log osiągnął limit $megabytes MB.';
  }

  @override
  String get bugReportShow => 'Pokaż';

  @override
  String get bugReportRecoveredHeader => 'Nagranie przetrwało awarię';

  @override
  String get bugReportRecoveredBody =>
      'Aplikacja zamknęła się w trakcie nagrywania. To, co zdążyła zapisać, jest nadal w telefonie — obejrzyj albo wyrzuć.';

  @override
  String get bugReportDestinationHeader => 'Co się stanie z tym logiem';

  @override
  String get bugReportDestinationFile => 'Zapisz do pliku';

  @override
  String get bugReportDestinationIssue => 'Zgłoś na GitHubie';

  @override
  String get bugReportDestinationFileBody =>
      'Log zapisze się tam, gdzie wskażesz, i zostanie w telefonie. Sam decydujesz, czy gdziekolwiek go wyślesz.';

  @override
  String get bugReportDestinationIssueBody =>
      'Log i Twój opis trafią jako publiczne zgłoszenie na GitHuba — każdy będzie mógł je przeczytać i zostaną tam na zawsze. Przejrzyj najpierw log poniżej.';

  @override
  String get bugReportDescriptionLabel => 'Co poszło nie tak?';

  @override
  String get bugReportDescriptionHint =>
      'Co robiłeś, czego się spodziewałeś, co stało się zamiast tego.';

  @override
  String get bugReportDescriptionRequired =>
      'Napisz, co poszło nie tak — log bez opisu jest prawie bezużyteczny.';

  @override
  String get bugReportSend => 'Zgłoś';

  @override
  String get bugReportSending => 'Wysyłanie…';

  @override
  String bugReportSendWaiting(String clock) {
    return 'Wysyłka za $clock';
  }

  @override
  String get bugReportSendWaitingBody =>
      'Relay rozkłada zgłoszenia w czasie. Możesz zamknąć ten ekran — wyśle się samo.';

  @override
  String get bugReportSent => 'Zgłoszenie wysłane';

  @override
  String get bugReportSentBody =>
      'Dzięki. Zgłoszenie jest otwarte, a log do niego dołączony.';

  @override
  String get bugReportOpenIssue => 'Otwórz zgłoszenie';

  @override
  String get bugReportDone => 'Gotowe';

  @override
  String get bugReportSendFailedNotYet =>
      'Relay w tej chwili nie przyjmuje zgłoszeń. Spróbuj później albo zapisz log do pliku.';

  @override
  String get bugReportSendFailedRefused =>
      'Relay odmówił przyjęcia tego zgłoszenia. Zapisz log do pliku i dołącz go sam.';

  @override
  String get bugReportSendFailedDuplicate => 'To już zostało zgłoszone.';

  @override
  String get bugReportSendFailedUnreachable =>
      'Nie udało się połączyć z relayem. Sprawdź połączenie albo zapisz log do pliku.';

  @override
  String get bugReportSendFailedRejected =>
      'Relay odrzucił to zgłoszenie. Zapisz log do pliku i dołącz go sam.';

  @override
  String get bugReportSendFailedDemo =>
      'Tryb demo nie publikuje zgłoszeń. Zapisz log do pliku.';

  @override
  String get bugReportKindQuestion => 'Co zgłaszasz?';

  @override
  String get bugReportKindBug => 'Błąd';

  @override
  String get bugReportKindChange => 'Zmianę';

  @override
  String get bugReportKindFeature => 'Funkcję';

  @override
  String get bugReportChangeHeader => 'Prośba o zmianę';

  @override
  String get bugReportChangeBody => 'Coś działa, ale nie tak, jak powinno.';

  @override
  String get bugReportChangeLabel => 'Co powinno się zmienić?';

  @override
  String get bugReportChangeHint =>
      'Co robi teraz, a co powinno robić zamiast tego.';

  @override
  String get bugReportFeatureHeader => 'Propozycja funkcji';

  @override
  String get bugReportFeatureBody => 'Czegoś aplikacja jeszcze nie potrafi.';

  @override
  String get bugReportFeatureLabel => 'Czego brakuje?';

  @override
  String get bugReportFeatureHint =>
      'Co chcesz zrobić i dlaczego aplikacja na to nie pozwala.';

  @override
  String get bugReportRequestPrivacyHeader => 'Co zostanie wysłane';

  @override
  String get bugReportRequestWhatYouWrite => 'To, co napiszesz';

  @override
  String get bugReportRequestVersions => 'Wersja aplikacji i serwera';

  @override
  String get bugReportRequestNoLog => 'Żadnego loga, żadnego nagrania';

  @override
  String get bugReportRequestNoData => 'Nic o Twoich drukarkach ani telefonie';

  @override
  String get bugReportRequestPublic =>
      'Powstaje publiczne zgłoszenie na GitHubie — każdy może je przeczytać i zostaje na stałe.';

  @override
  String get bugReportRequestRequired =>
      'Napisz, o co prosisz — z pustego zgłoszenia nic nie wynika.';

  @override
  String get bugReportRequestSentBody => 'Dzięki. Zgłoszenie jest otwarte.';

  @override
  String get bugReportCancelSend => 'Anuluj wysyłanie';

  @override
  String get bugReportRequestFailedNotYet =>
      'Relay w tej chwili nie przyjmuje zgłoszeń. Spróbuj później.';

  @override
  String get bugReportRequestFailedRefused =>
      'Relay odmówił przyjęcia tego zgłoszenia. Możesz otworzyć je samodzielnie na GitHubie.';

  @override
  String get bugReportRequestFailedUnreachable =>
      'Nie udało się połączyć z relayem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get bugReportRequestFailedDemo => 'Tryb demo nie publikuje zgłoszeń.';

  @override
  String get bugReportRequestNotPrepared =>
      'Aplikacja nie zdołała przygotować zgłoszenia. Nic nie wysłano — spróbuj ponownie.';

  @override
  String get usersTitle => 'Użytkownicy';

  @override
  String get usersMenu => 'Użytkownicy';

  @override
  String get usersEmpty => 'Na tym serwerze nie ma kont.';

  @override
  String get usersYou => 'ty';

  @override
  String get usersRoleAdmin => 'Administrator';

  @override
  String get usersRoleUser => 'Użytkownik';

  @override
  String get usersInactive => 'Nieaktywne';

  @override
  String get usersEmailLabel => 'E-mail';

  @override
  String get usersEmailNone => 'brak';

  @override
  String get usersGroupsLabel => 'Grupy';

  @override
  String get usersNoGroups => 'brak';

  @override
  String get usersPermissionsLabel => 'Uprawnienia';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uprawnień',
      many: '$count uprawnień',
      few: '$count uprawnienia',
      one: '1 uprawnienie',
      zero: 'brak',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => 'serwer ich nie podał';

  @override
  String get usersAuthSourceLabel => 'Logowanie';

  @override
  String get usersAuthSourceLocal => 'Konto lokalne';

  @override
  String get usersCreatedLabel => 'Utworzone';

  @override
  String get usersOwnedTitle => 'UTWORZONE PRZEZ TO KONTO';

  @override
  String get usersOwnedArchives => 'Wydruki';

  @override
  String get usersOwnedQueue => 'Kolejka';

  @override
  String get usersOwnedLibrary => 'Pliki';

  @override
  String get usersOwnedFailed =>
      'Nie udało się odczytać, co należy do tego konta.';

  @override
  String get usersCreate => 'Dodaj konto';

  @override
  String get usersCreateTitle => 'Nowe konto';

  @override
  String get usersEdit => 'Edytuj';

  @override
  String get usersEditTitle => 'Edycja konta';

  @override
  String get usersDelete => 'Usuń';

  @override
  String get usersSave => 'Zapisz';

  @override
  String get usersSaved => 'Zapisano konto';

  @override
  String get usersSaveFailed => 'Nie udało się zapisać konta.';

  @override
  String get usersDeleted => 'Konto usunięte';

  @override
  String get usersFieldUsername => 'Nazwa użytkownika';

  @override
  String get usersFieldEmail => 'E-mail (opcjonalnie)';

  @override
  String get usersFieldEmailRequired => 'E-mail';

  @override
  String get usersFieldPassword => 'Hasło';

  @override
  String get usersFieldNewPassword => 'Nowe hasło';

  @override
  String get usersFieldConfirmPassword => 'Powtórz hasło';

  @override
  String get usersFieldActive => 'Aktywne';

  @override
  String get usersFieldGroups => 'Grupy';

  @override
  String get usersGroupSystem => '(wbudowana)';

  @override
  String get usersFieldRequired => 'Uzupełnij to pole';

  @override
  String get usersPasswordsDoNotMatch => 'Hasła się różnią.';

  @override
  String get usersGroupsAdminHint =>
      'Administratorem czyni konto członkostwo w grupie Administrators.';

  @override
  String get usersActiveHint => 'Nieaktywne konto nie zaloguje się.';

  @override
  String get usersEmailAdvancedHint =>
      'Ten serwer wysyła hasło mailem, więc potrzebuje adresu.';

  @override
  String get usersPasswordMailed =>
      'Serwer sam ustala hasło i wysyła je na ten adres. Nikt go nie zobaczy — Ty też nie.';

  @override
  String get usersNoSmtpWarning =>
      'Serwer poczty nie jest skonfigurowany, więc ta wiadomość nie dojdzie — konto powstanie z hasłem, którego nikt nie zna.';

  @override
  String get usersLdapPasswordNote =>
      'To konto loguje się przez katalog (LDAP). Hasło jest po jego stronie i nie ustawisz go stąd.';

  @override
  String get usersPasswordKeepHint => 'Zostaw puste, żeby nie zmieniać hasła.';

  @override
  String get usersPasswordRulesHint =>
      'Co najmniej 8 znaków, w tym wielka i mała litera, cyfra i znak specjalny.';

  @override
  String get usersPasswordTooShort => 'Co najmniej 8 znaków.';

  @override
  String get usersPasswordNoUppercase => 'Dodaj wielką literę.';

  @override
  String get usersPasswordNoLowercase => 'Dodaj małą literę.';

  @override
  String get usersPasswordNoDigit => 'Dodaj cyfrę.';

  @override
  String get usersPasswordNoSpecial => 'Dodaj znak specjalny.';

  @override
  String usersDeleteTitle(String username) {
    return 'Usunąć $username?';
  }

  @override
  String get usersDeleteBody =>
      'Konto, jego klucze API i stan logowania znikają. Tego nie da się cofnąć.';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'To konto utworzyło $count rzeczy',
      many: 'To konto utworzyło $count rzeczy',
      few: 'To konto utworzyło $count rzeczy',
      one: 'To konto utworzyło 1 rzecz',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => 'Usuń je razem z kontem';

  @override
  String get usersDeleteItemsTooHint =>
      'Wydruki, pozycje w kolejce i pliki znikną razem z kontem.';

  @override
  String get usersDeleteItemsKeepHint =>
      'Wydruki, pozycje w kolejce i pliki zostaną, bez właściciela.';

  @override
  String get usersDeleteConfirm => 'Usuń';

  @override
  String get usersErrLastAdmin =>
      'To ostatni administrator — serwer musi mieć jednego.';

  @override
  String get usersErrLastAdminDelete =>
      'Nie można usunąć ostatniego administratora — nie zostałby nikt do zarządzania serwerem.';

  @override
  String get usersErrLastAdminDeactivate =>
      'Nie można wyłączyć ostatniego administratora — nie zostałby nikt do zarządzania serwerem.';

  @override
  String get usersErrLastAdminRole =>
      'Nie można odebrać roli ostatniemu administratorowi — nie zostałby nikt do zarządzania serwerem.';

  @override
  String get usersErrSelfDelete =>
      'Nie usuniesz konta, na którym jesteś zalogowany.';

  @override
  String get usersErrUsernameTaken => 'Ta nazwa jest już zajęta.';

  @override
  String get usersErrEmailTaken =>
      'Ten e-mail jest już przypisany do innego konta.';

  @override
  String get usersErrLdapPassword =>
      'Hasła konta z katalogu (LDAP) nie ustawisz tutaj.';

  @override
  String get usersErrEmailRequired =>
      'Ten serwer wymaga adresu e-mail dla nowego konta.';

  @override
  String get usersErrPasswordRequired =>
      'Ten serwer wymaga hasła dla nowego konta.';

  @override
  String get usersErrGroupsInvalid =>
      'Którejś z grup już nie ma — otwórz formularz jeszcze raz.';

  @override
  String get groupsTitle => 'Grupy';

  @override
  String get groupsMenu => 'Grupy';

  @override
  String get groupsEmpty => 'Na tym serwerze nie ma grup.';

  @override
  String get groupsNoDescription => 'Bez opisu';

  @override
  String get groupsSystemPill => 'Wbudowana';

  @override
  String get groupsSystemNote =>
      'Wbudowanej grupy nie zmienisz z nazwy ani z uprawnień — zmienić można tylko to, kto do niej należy.';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count konta',
      many: '$count kont',
      few: '$count konta',
      one: '1 konto',
      zero: 'brak kont',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uprawnienia',
      many: '$count uprawnień',
      few: '$count uprawnienia',
      one: '1 uprawnienie',
      zero: 'brak uprawnień',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => 'CZŁONKOWIE';

  @override
  String get groupsNoMembers => 'Nikt nie należy do tej grupy.';

  @override
  String get groupsAddMember => 'Dodaj konto';

  @override
  String groupsAddMemberTitle(String group) {
    return 'Dodaj do: $group';
  }

  @override
  String get groupsEveryoneIsIn => 'Wszystkie konta są już w tej grupie.';

  @override
  String get groupsRemoveMember => 'Usuń z grupy';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return 'Usunąć $username z grupy $group?';
  }

  @override
  String get groupsRemoveMemberBody =>
      'Konto zostaje i traci to, co dawała mu ta grupa.';

  @override
  String get groupsCreate => 'Nowa grupa';

  @override
  String get groupsCreateTitle => 'Nowa grupa';

  @override
  String get groupsEditTitle => 'Edycja grupy';

  @override
  String get groupsDelete => 'Usuń grupę';

  @override
  String get groupsSaved => 'Zapisano grupę';

  @override
  String get groupsDeleted => 'Grupa usunięta';

  @override
  String groupsDeleteQuestion(String group) {
    return 'Usunąć grupę $group?';
  }

  @override
  String get groupsDeleteBody =>
      'Uprawnienia, które dawała, znikają razem z nią.';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Należy do niej $count konta i zostają — tracą tylko to, co dawała ta grupa.',
      many:
          'Należy do niej $count kont i zostają — tracą tylko to, co dawała ta grupa.',
      few:
          'Należą do niej $count konta i zostają — tracą tylko to, co dawała ta grupa.',
      one:
          'Należy do niej 1 konto i zostaje — traci tylko to, co dawała ta grupa.',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => 'Nazwa';

  @override
  String get groupsFieldDescription => 'Do czego służy';

  @override
  String get groupsSystemFormNote =>
      'Grupa wbudowana: nazwę i uprawnienia ustala serwer. Stąd zmienisz tylko opis.';

  @override
  String get groupsPermissionsHeader => 'UPRAWNIENIA';

  @override
  String groupsPermissionsSelected(int count) {
    return 'zaznaczono $count';
  }

  @override
  String get groupsAdvancedPermissions => 'Administracja serwerem';

  @override
  String get groupsAdvancedHint =>
      'Użytkownicy, klucze API, ustawienia, kopie zapasowe — to, na co sama apka nie ma ekranów.';

  @override
  String get adminMenu => 'Administracja';

  @override
  String get adminTitle => 'Administracja';

  @override
  String adminSignedInAs(String username) {
    return 'Zalogowany jako $username';
  }

  @override
  String get adminUsersSubtitle => 'Kto ma konto i co każdemu wolno';

  @override
  String get adminGroupsSubtitle => 'Zestawy uprawnień i kto je ma';

  @override
  String get adminApiKeysSubtitle =>
      'Dostęp dla wszystkiego, co nie jest tą apką';

  @override
  String get apiKeysTitle => 'Klucze API';

  @override
  String get apiKeysEmpty => 'Nie wydano żadnego klucza.';

  @override
  String get apiKeysCreate => 'Nowy klucz';

  @override
  String get apiKeysCreateTitle => 'Nowy klucz API';

  @override
  String get apiKeysEditTitle => 'Edycja klucza';

  @override
  String get apiKeysSaved => 'Zapisano klucz';

  @override
  String get apiKeysRevoke => 'Odwołaj';

  @override
  String get apiKeysRevoked => 'Klucz odwołany';

  @override
  String apiKeysRevokeQuestion(String name) {
    return 'Odwołać klucz $name?';
  }

  @override
  String get apiKeysRevokeBody =>
      'Wszystko, co go używa, przestanie działać natychmiast. Tego nie da się cofnąć — trzeba będzie wydać nowy klucz.';

  @override
  String apiKeysLastUsed(String date) {
    return 'użyty $date';
  }

  @override
  String get apiKeysNeverUsed => 'nieużywany';

  @override
  String get apiKeysDisabled => 'Wyłączony';

  @override
  String get apiKeysExpired => 'Wygasł';

  @override
  String apiKeysExpiresOn(String date) {
    return 'do $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count drukarki',
      many: '$count drukarek',
      few: '$count drukarki',
      one: '1 drukarka',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => 'Bez właściciela';

  @override
  String get apiKeysFieldName => 'Nazwa';

  @override
  String get apiKeysFieldNameHint =>
      'Co go trzyma — „Home Assistant”, „SpoolBuddy”.';

  @override
  String get apiKeysFieldEnabled => 'Aktywny';

  @override
  String get apiKeysFieldEnabledHint =>
      'Wyłączenie zatrzymuje klucz bez kasowania go.';

  @override
  String get apiKeysScopesHeader => 'CO MU WOLNO';

  @override
  String get apiKeysScopesHint =>
      'Klucz nigdy nie zarządza kontami, grupami, kluczami ani ustawieniami — serwer odmawia tego każdemu kluczowi.';

  @override
  String get apiKeysPrintersHeader => 'DRUKARKI';

  @override
  String get apiKeysAllPrinters => 'Wszystkie drukarki';

  @override
  String get apiKeysAllPrintersHint =>
      'Wyłącz, żeby wskazać, których drukarek klucz dotyczy.';

  @override
  String get apiKeysExpiryHeader => 'WAŻNOŚĆ';

  @override
  String get apiKeysNoExpiry => 'Bezterminowy';

  @override
  String get apiKeysExpiryHint =>
      'Dotknij, aby wybrać datę, po której klucz przestanie działać.';

  @override
  String get apiKeysExpiryClear => 'Bezterminowy';

  @override
  String get apiKeysCreatedTitle => 'Klucz utworzony';

  @override
  String get apiKeysCreatedWarning =>
      'Skopiuj go teraz. Serwer trzyma tylko skrót — to ostatni moment, kiedy można go pokazać.';

  @override
  String get apiKeysCopy => 'Kopiuj';

  @override
  String get apiKeysCopied => 'Skopiowano klucz';

  @override
  String get apiKeysCreatedDone => 'Gotowe';

  @override
  String get apiKeyScopeRead => 'Odczyt stanu';

  @override
  String get apiKeyScopeReadHint =>
      'Drukarki, kolejka, archiwum, pliki, statystyki — tylko odczyt.';

  @override
  String get apiKeyScopeQueue => 'Kolejka';

  @override
  String get apiKeyScopeControl => 'Sterowanie drukarkami';

  @override
  String get apiKeyScopeControlHint =>
      'Pauza, stop, temperatury, AMS, gniazdka.';

  @override
  String get apiKeyScopeLibrary => 'Pliki';

  @override
  String get apiKeyScopeInventory => 'Filamenty';

  @override
  String get apiKeyScopeMaintenance => 'Konserwacja';

  @override
  String get apiKeyScopeArchives => 'Archiwum';

  @override
  String get apiKeyScopeProjects => 'Projekty';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint =>
      'Czyta chmurę w imieniu konta, które wydaje klucz. Wymaga włączonego logowania po stronie serwera.';

  @override
  String get apiKeyScopeEnergy => 'Cena energii';

  @override
  String get apiKeyScopeEnergyHint =>
      'Jedyne ustawienie, które klucz może zapisać — do taryfy dynamicznej.';

  @override
  String get printLogTitle => 'Log wydruków';

  @override
  String get printLogSearchHint => 'Szukaj przebiegów';

  @override
  String get printLogEmpty => 'Brak zapisanych przebiegów';

  @override
  String get printLogNoMatches => 'Żaden przebieg nie pasuje do filtrów';

  @override
  String get printLogLoadFailed => 'Nie udało się wczytać logu wydruków';

  @override
  String get printLogFilters => 'Filtry';

  @override
  String get printLogFilterPrinter => 'Drukarka';

  @override
  String get printLogFilterUser => 'Użytkownik';

  @override
  String get printLogFilterStatus => 'Status';

  @override
  String get printLogFilterDates => 'Zakres dat';

  @override
  String get printLogAnyPrinter => 'Dowolna drukarka';

  @override
  String get printLogAnyUser => 'Dowolny';

  @override
  String get printLogAnyStatus => 'Dowolny status';

  @override
  String get printLogNoUser => 'Bez użytkownika';

  @override
  String get printLogOrphan => 'Archiwum usunięte';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded z $total';
  }

  @override
  String get printLogLoadMore => 'Wczytaj więcej';

  @override
  String get printLogSort => 'Sortuj według';

  @override
  String get printLogSortDate => 'Data';

  @override
  String get printLogSortName => 'Nazwa';

  @override
  String get printLogSortPrinter => 'Drukarka';

  @override
  String get printLogSortUser => 'Użytkownik';

  @override
  String get printLogSortStatus => 'Status';

  @override
  String get printLogSortDuration => 'Czas trwania';

  @override
  String get printLogSortFilament => 'Zużycie filamentu';

  @override
  String get printLogSortCost => 'Koszt';

  @override
  String get printLogSortEnergy => 'Energia';

  @override
  String get printLogSortDirection => 'Kierunek';

  @override
  String get printLogSortDescending => 'Malejąco';

  @override
  String get printLogSortAscending => 'Rosnąco';

  @override
  String get printLogStatusCompleted => 'Ukończony';

  @override
  String get printLogStatusFailed => 'Nieudany';

  @override
  String get printLogStatusStopped => 'Zatrzymany';

  @override
  String get printLogStatusCancelled => 'Anulowany';

  @override
  String get printLogStatusSkipped => 'Pominięty';

  @override
  String get printLogStatusAborted => 'Przerwany';

  @override
  String printLogEnergy(String value) {
    return '$value kWh';
  }

  @override
  String get printLogClassifyTitle => 'Sklasyfikuj przebieg';

  @override
  String get printLogDetailStarted => 'Rozpoczęto';

  @override
  String get printLogDetailFinished => 'Zakończono';

  @override
  String get printLogDetailDuration => 'Czas trwania';

  @override
  String get printLogDetailFilament => 'Filament';

  @override
  String get printLogDetailCost => 'Koszt';

  @override
  String get printLogDetailEnergy => 'Energia';

  @override
  String get printLogFailureCause => 'Przyczyna niepowodzenia';

  @override
  String get printLogNoClassification => 'Bez klasyfikacji';

  @override
  String get printLogStatusLabel => 'Status';

  @override
  String get printLogCountsAsFailure =>
      'Liczy się jako niepowodzenie — ten przebieg i jego przyczyna trafiają do analizy awarii.';

  @override
  String get printLogNotCountedAsFailure =>
      'Nie liczy się jako niepowodzenie, więc przyczyna nie trafi do analizy awarii.';

  @override
  String printLogStatusOneWay(String status) {
    return 'Ten serwer nie potrafi zapisać z powrotem „$status”. Po zmianie nie da się tam wrócić.';
  }

  @override
  String get printLogSave => 'Zapisz';

  @override
  String get printLogSaveFailed => 'Nie udało się zapisać klasyfikacji';

  @override
  String get printLogDelete => 'Usuń przebieg';

  @override
  String get printLogDeleteTitle => 'Usunąć ten przebieg?';

  @override
  String get printLogDeleteBody =>
      'Zniknie z logu, a jego filament, koszt i czas znikną ze statystyk. Archiwum, do którego wskazuje, zostaje.';

  @override
  String get printLogDeleteFailed => 'Nie udało się usunąć przebiegu';

  @override
  String get printLogClear => 'Wyczyść log wydruków';

  @override
  String get printLogClearTitle => 'Wyczyścić cały log wydruków?';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zniknie wszystkie $count przebiegów',
      many: 'Zniknie wszystkie $count przebiegów',
      few: 'Znikną wszystkie $count przebiegi',
      one: 'Zniknie jedyny przebieg w logu',
    );
    return '$_temp0 — wszystkich użytkowników, nie tylko Twoje — a ich filament, koszt i czas znikną ze statystyk. Archiwum i kolejka zostają nietknięte. Tego nie da się cofnąć.';
  }

  @override
  String get printLogClearBodyFiltered =>
      'Zniknie każdy przebieg w logu — wszystkich użytkowników, nie tylko Twoje, i włączony filtr tego nie zawęża — a ich filament, koszt i czas znikną ze statystyk. Archiwum i kolejka zostają nietknięte. Tego nie da się cofnąć.';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Usunięto $count przebiegów',
      many: 'Usunięto $count przebiegów',
      few: 'Usunięto $count przebiegi',
      one: 'Usunięto $count przebieg',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed => 'Nie udało się wyczyścić logu wydruków';

  @override
  String get failureReasonAdhesion => 'Brak przyczepności do stołu';

  @override
  String get failureReasonSpaghetti => 'Spaghetti / oderwany wydruk';

  @override
  String get failureReasonLayerShift => 'Przesunięcie warstw';

  @override
  String get failureReasonCloggedNozzle => 'Zapchana dysza';

  @override
  String get failureReasonFilamentRunout => 'Koniec filamentu';

  @override
  String get failureReasonWarping => 'Odkształcenie (warping)';

  @override
  String get failureReasonStringing => 'Nitkowanie';

  @override
  String get failureReasonUnderExtrusion => 'Niedomiar ekstruzji';

  @override
  String get failureReasonPowerFailure => 'Zanik zasilania';

  @override
  String get failureReasonUserCancelled => 'Anulowany przez użytkownika';

  @override
  String get failureReasonOther => 'Inna';

  @override
  String get failureReasonUnknown => 'Nieznana';
}
