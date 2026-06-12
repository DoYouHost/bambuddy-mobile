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
  String get ctrlFanPart => 'Wentylator części';

  @override
  String get ctrlFanAux => 'Wentylator pomocniczy';

  @override
  String get ctrlFanChamber => 'Wentylator komory';

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
  String get statusUnavailable => 'status niedostępny';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

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
}
