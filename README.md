# BambuBuddy Mobile

Natywna aplikacja mobilna (Flutter, Android) dla [bambuddy](https://github.com/maziggy/bambuddy) — self-hosted, bezchmurowego menedżera drukarek Bambu Lab.

**Status: w budowie — milestone M1** (konfiguracja serwera, auth, dashboard z listą drukarek przez REST polling). Mapa drogowa M0–M7 w [docs/plans/02-plan-implementacji.md](docs/plans/02-plan-implementacji.md).

## Zgodność z serwerem

Tworzono i testowano pod **bambuddy v0.2.4.6** (API `/api/v1`). API serwera jest młode i ruchliwe — nowsze wersje powinny działać, ale bez gwarancji; parsowanie jest defensywne (nieznane pola są ignorowane, brakujące nie wywalają aplikacji).

## Funkcje (M1)

- Konfiguracja serwera: URL + automatyczna detekcja trybu uwierzytelniania (`GET /api/v1/auth/status`)
- Trzy tryby auth: wyłączony / login+hasło (JWT) / klucz API (`X-API-Key`) — **rekomendowane klucze API**: nie wygasają i są scope'owane
- Poświadczenia w Android Keystore (`flutter_secure_storage`); hasło zapamiętywane tylko za zgodą
- Dashboard: lista drukarek ze stanem, postępem, temperaturami i warstwą, odświeżana co 5 s + pull-to-refresh
- Czytelne stany błędów: serwer nieosiągalny (baner, ostatnie dane zostają), wygaśnięcie sesji → powrót do konfiguracji

## Build

Wymagany [Flutter](https://docs.flutter.dev/get-started/install) (stable) i Android SDK. Setup środowiska na Fedorze: [docs/plans/03-srodowisko-fedora.md](docs/plans/03-srodowisko-fedora.md).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run            # na podłączonym urządzeniu
flutter build apk      # release (niepodpisany do czasu M7)
```

Testy i lint:

```sh
flutter analyze
flutter test
```

Checklista testów manualnych przed tagiem: [MANUAL_TESTING.md](MANUAL_TESTING.md).

> **Uwaga (HTTP po LAN):** aplikacja zezwala na cleartext HTTP (`usesCleartextTraffic`), bo self-hosted serwery w domowym LAN-ie zwykle nie mają TLS. Dla dostępu zdalnego użyj HTTPS przez reverse proxy.

## Dokumentacja projektowa

- [docs/plans/01-analiza-wykonalnosci.md](docs/plans/01-analiza-wykonalnosci.md) — analiza wykonalności, API bambuddy, wybór stacku
- [docs/plans/02-plan-implementacji.md](docs/plans/02-plan-implementacji.md) — architektura, pakiety, milestone'y M0–M7, ryzyka
- [docs/plans/03-srodowisko-fedora.md](docs/plans/03-srodowisko-fedora.md) — środowisko deweloperskie na Fedorze

## Licencja

[AGPL-3.0](LICENSE) — spójnie z bambuddy. Aplikacja nie zawiera kodu z innych projektów; architektonicznie inspirowana m.in. [Mobileraker](https://github.com/Clon1998/mobileraker) (bez kopiowania kodu) i [BamPocket](https://github.com/clabeuhtegrite/bambuddy-pocket).
