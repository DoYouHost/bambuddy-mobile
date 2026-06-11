# Checklista testów manualnych

Odhaczana na fizycznym telefonie przeciw żywemu serwerowi bambuddy
**przed każdym tagiem**. Testy automatyczne pokrywają czysto-dartowy
rdzeń — to tutaj jest substytut testów integracyjnych (decyzja §5 planu).

## M1 — konfiguracja + dashboard

### Setup, serwer z WYŁĄCZONYM auth
- [ ] Podanie samego `host:port` (bez `http://`) działa — schemat doklejany
- [ ] „Testuj połączenie" od razu zapisuje profil i pokazuje dashboard
- [ ] Zły adres → czytelny błąd „serwer nieosiągalny", nie crash
- [ ] Adres z końcowym `/` działa

### Setup, serwer z WŁĄCZONYM auth
- [ ] Sonda wykrywa auth i pokazuje wybór metody (klucz API domyślnie)
- [ ] Poprawny klucz API → dashboard; w logach serwera żądania mają `X-API-Key`
- [ ] Klucz z samym scope `can_read_status` wystarcza
- [ ] Unieważniony/błędny klucz → czytelny błąd, klucz NIE zapisany
- [ ] Login+hasło bez „zapamiętaj" → dashboard
- [ ] Złe hasło → czytelny błąd, formularz nie czyści URL-a
- [ ] Konto z 2FA → komunikat o braku obsługi i wskazanie kluczy API
- [ ] Świeży serwer (`requires_setup`) → komunikat o dokończeniu w przeglądarce

### Dashboard
- [ ] Lista drukarek z nazwą, stanem, postępem, temperaturami, warstwą
- [ ] Dane odświeżają się same co ~5 s (zmień coś na drukarce/w webUI)
- [ ] Pull-to-refresh działa
- [ ] Zatrzymanie serwera w trakcie → baner „serwer nieosiągalny",
      ostatnie dane ZOSTAJĄ widoczne; po starcie serwera baner znika sam
- [ ] Toggle Wi-Fi w telefonie → jak wyżej, bez crasha
- [ ] Serwer niedostępny przy starcie aplikacji → ekran błędu z „Spróbuj
      ponownie", przycisk działa
- [ ] (JWT, bez „zapamiętaj") unieważnij token po stronie serwera →
      snackbar o wygaśnięciu sesji + powrót do konfiguracji
- [ ] (JWT, z „zapamiętaj") unieważnij token → aplikacja cicho loguje się
      ponownie, dashboard działa dalej
- [ ] (API key) usuń klucz na serwerze → powrót do konfiguracji, nie crash
- [ ] Drukarka odłączona od prądu → karta „status niedostępny", reszta
      listy żyje
- [ ] Obrót ekranu na obu ekranach nie gubi stanu formularza/listy
- [ ] „Zmień serwer" → dialog potwierdzenia → powrót do konfiguracji;
      po ponownym wejściu poświadczenia są wyczyszczone
- [ ] Aplikacja w tle 10 min → powrót → dane odświeżają się, nie crash
