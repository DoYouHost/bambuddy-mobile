# Plan implementacji: BambuBuddy Mobile (Flutter, Android)

Założenia: solo deweloper, doświadczony ogólnie, **zero doświadczenia w Dart/Flutter**, praca po godzinach (~5–8 h/tydz.). Cel v1: Android; struktura kodu przenośna na iOS. Licencja: AGPL-3.0.

## Podsumowanie decyzji

| Decyzja | Wybór |
|---|---|
| State management | **Riverpod** (`flutter_riverpod`, ręczne providery, bez codegenu w v1) |
| HTTP | **dio** |
| WebSocket | **web_socket_channel** + własny menedżer reconnect |
| Modele | **Pisane ręcznie** dla używanego podzbioru + `json_serializable` (NIE openapi-generator) |
| MJPEG | **flutter_mjpeg**; plan B: własny dekoder ~100 linii |
| Poświadczenia | **flutter_secure_storage** (Android Keystore) |
| Routing | **go_router** |
| Powiadomienia | **flutter_local_notifications** (foreground) + **unifiedpush** → ntfy (tło) |
| IDE | **VS Code + rozszerzenie Flutter**; Android Studio tylko jako menedżer SDK/emulatora |
| Testy | `flutter_test` + **mocktail** + **http_mock_adapter**, testy na fixture'ach |
| Pominięte w v1 | `freezed`, `riverpod_generator`, testy integracyjne/golden, isolates |

## 1. Architektura

### Riverpod — dlaczego (dla początkującego)

- vs **Bloc**: Bloc wymusza pary klas event/state per feature — ciężki boilerplate zaciemniający naukę. W Riverpodzie „strumień statusów drukarek z WebSocketa" to dosłownie jeden `StreamProvider`.
- vs samo `setState`/Provider: za słabe do współdzielenia stanu WS między ekranami.
- Bonus: **Mobileraker używa Riverpodu** — można czytać jego kod jako wzorzec (tylko czytać! licencja zakazuje kopiowania).
- Ograniczenie na v1: tylko ręczne providery (`Provider`, `NotifierProvider`, `StreamProvider`, `FutureProvider`) — jeden codegen (`json_serializable`) wystarczy magii na start.

### Warstwy (zależności wyłącznie w dół)

```
UI (ekrany/widgety) → Providery (Riverpod) → Repozytoria → Klienci API (dio/WS)
```

- **Warstwa API** (`core/api/`): surowe HTTP + WS; zna URL-e, nagłówki, tokeny; rzuca typowane wyjątki (`ApiException`, `AuthException`, `NetworkException`).
- **Repozytoria** (`data/`): jedno na domenę (printers, queue, archive, auth); łączą REST + WS, ukrywają źródło danych. **To jest szew przenośności na iOS — czysty Dart, zero importów Fluttera.**
- **Providery**: eksponują stan repozytoriów do UI.
- **UI**: głupie widgety, tylko `ref.watch(...)`.

### Struktura katalogów

```
lib/
  main.dart
  app.dart                      # MaterialApp.router, motyw
  core/
    api/
      api_client.dart           # dio + interceptor auth
      ws_client.dart            # maszyna stanów WebSocketa
      endpoints.dart            # WSZYSTKIE ścieżki /api/v1 w jednym pliku
      api_exceptions.dart
    auth/
      auth_service.dart         # login, odświeżanie JWT, ws-token, stream-token
      credentials_store.dart    # wrapper na flutter_secure_storage
    models/                     # ręczne DTO + json_serializable
      printer.dart
      printer_status.dart       # w tym pod-modele AMS
      queue_item.dart
      archive_entry.dart
      ws_message.dart           # koperta: {"type": ..., payload}
    settings/
      server_profile.dart       # url + tryb auth + etykieta
      settings_repository.dart
  data/
    printers_repository.dart
    queue_repository.dart
    archive_repository.dart
  features/
    setup/  dashboard/  printer_detail/  queue/  archive/  notifications/  settings/
    # każdy feature: providers.dart, <nazwa>_screen.dart, widgets/
  router.dart
test/
  fixtures/                     # przechwycone PRAWDZIWE JSON-y: statusy, ramki WS
docs/
  openapi-snapshot.json         # snapshot kontraktu serwera + wersja serwera
```

Zasada: wszystko co importuje `package:flutter/` żyje w `features/` lub `app.dart`; reszta to czysty Dart (testowalny na VM Darta, przenośny na iOS bez zmian).

## 2. Pakiety — uzasadnienia

- **dio**: interceptory to kluczowa cecha — jeden `AuthInterceptor` dodaje Bearer/X-API-Key, łapie 401, odświeża JWT i ponawia, zamiast rozsiewać auth po każdym wywołaniu. Plus timeouty, `ResponseType.stream` (przyda się przy własnym dekoderze MJPEG), `http_mock_adapter` w testach.
- **web_socket_channel**: cienki, oficjalny. Logika reconnect/backoff/heartbeat pisana samodzielnie (~150 linii) — **celowo**: to rdzeń niezawodności aplikacji i świetne ćwiczenie ze Streams. Ciężkie wrappery WS walczyłyby z niestandardowym flow odświeżania tokenu po 4401.
- **json_serializable**: codegen tylko do `fromJson/toJson`. **Odrzucamy openapi-generator**: (a) 200+ endpointów → tysiące linii generatu dla ~25 używanych; (b) API bambuddy jest młode i ruchliwe — każdy update serwera wymuszałby regenerację i przegląd kodu, którego się nie rozumie; (c) dartowy output openapi-generatora ma znaną słabą jakość (nullability, oneOf). Zamiast tego: snapshot `openapi.json` w `docs/` jako kontrakt referencyjny + ręczne ~10 klas modeli + parsowanie defensywne.
- **flutter_mjpeg**: działa z URL-em z marszu; tokeny strumienia bambuddy są w query param (`?token=`) — dokładnie przypadek, który obsługuje bez custom headers. Pakiet jest słabo utrzymywany, więc plan B: własny dekoder — dio `ResponseType.stream`, skan granic `boundary=frame`, bajty JPEG do `Image.memory` z `gaplessPlayback: true`. ~100 linii, pisany tylko jeśli flutter_mjpeg pokaże problemy (buforowanie/wycieki) w M3.
- **flutter_secure_storage**: JWT, klucz API, hasło tylko za zgodą użytkownika („zapamiętaj"). URL serwera i metadane profilu → `shared_preferences` (nie są sekretem).
- **go_router**: deklaratywne trasy, gotowość na deep linki (tap w powiadomienie → drukarka X). Płaskie trasy v1: `/setup`, `/`, `/printer/:id`, `/queue`, `/archive`, `/settings`.
- **flutter_local_notifications**: powiadomienia z eventów WS + render payloadów UnifiedPush. Wymaga runtime-permission `POST_NOTIFICATIONS` (Android 13+) i kanałów (M6).
- **unifiedpush** (+ `unifiedpush_ui`): oficjalny pakiet; użytkownik instaluje apkę ntfy jako dystrybutora pusha, a wbudowana integracja ntfy w bambuddy publikuje na temat. **Fallback dokumentowany w aplikacji**: „zainstaluj apkę ntfy i zasubskrybuj temat X" z deep linkiem — fallback wypływa pierwszy, integracja UnifiedPush druga.
- Wsparcie: `shared_preferences`, `flutter_lints`, `mocktail`, `http_mock_adapter`, `package_info_plus`, `url_launcher`.

## 3. Cykl życia WebSocketa (najryzykowniejszy komponent)

Jeden `WsClient` (singleton przez `Provider`) z jednym połączeniem multipleksującym wszystkie drukarki.

### Maszyna stanów

```
disconnected → connecting → connected → (error/close) → waitingRetry → connecting …
                                   ↘ closed4401 → refreshWsToken → connecting
suspended (aplikacja w tle — bez prób reconnect)
```

Dwa strumienie na zewnątrz: `Stream<WsConnectionState>` (baner „Łączenie ponowne…") i `Stream<PrinterStatus>` (sparsowane ramki `printer_status`). `NotifierProvider<Map<int, PrinterStatus>>` składa strumień w najnowszy-stan-per-drukarka; ekrany szczegółów robią `select` swojego wpisu.

### Polityki

- **Backoff**: wykładniczy z pełnym jitterem — `delay = rand(0, min(30s, 1s * 2^attempt))`; licznik resetowany po połączeniu, które przeżyło >30 s. Cap 30 s na zawsze (bez poddawania się — to apka domowego LAN-u, serwer się restartuje).
- **Heartbeat**: `{"type":"ping"}` co 25 s; brak JAKIEJKOLWIEK ramki przez 60 s → wymuś zamknięcie i reconnect (łapie półotwarte TCP przy roamingu Wi-Fi).
- **Lifecycle aplikacji**: `AppLifecycleListener` — przy `paused`/`hidden`: natychmiast zamknij socket, stan `suspended` (bez FGS w Androidzie, zgodnie z decyzją zakresu). Przy `resumed`: (1) najpierw jednorazowy backfill REST (`GET /printers/` + statusy) — inaczej dashboard pokazuje nieświeże dane przez kilka sekund, (2) potem reconnect WS.
- **4401 / wygaśnięcie tokenu**: token WS żyje 60 min. Dwie warstwy: (a) **reaktywna** — kod 4401 → `POST /api/v1/auth/ws-token` (uwierzytelnione bieżącym JWT/kluczem) → reconnect z nowym `?token=`; jeśli sam mint dostaje 401 → eskalacja do re-loginu JWT i ponowienie; (b) **proaktywna** — timer ~50. minuta mintuje świeży token i robi kontrolowany reconnect w bezczynności, żeby strumień nie urywał się w trakcie oglądania wydruku. (a) w M2, (b) w M7.
- **Tryb auth wyłączony**: `ServerProfile.authMode == none` → całkowite pominięcie mintowania, połączenie „gołe". Każda ścieżka dotykająca auth MUSI branchować po enumie `AuthMode {none, jwt, apiKey}`.

## 4. Kamienie milowe (M0–M7)

Nakład w „sesjach" = jeden ~3-godzinny blok wieczorny/weekendowy.

### M0 — Środowisko + hello world (3–5 sesji)
- `flutter doctor` zielony na Fedorze; domyślna apka-licznik na fizycznym telefonie; przejście Dart language tour; repo z LICENSE AGPL-3.0, `flutter_lints`, GitHub Actions (`flutter analyze && flutter test`).
- Ryzyko: yak-shaving toolchaina — timeboxować; emulator może poczekać, fizyczny telefon odblokowuje wszystko.

### M1 — Połączenie + lista drukarek przez REST polling (5–8 sesji)
- Ekran konfiguracji (URL, tryb auth: brak/login/klucz API); `ApiClient` z interceptorem; login JWT; poświadczenia w secure storage; dashboard z listą drukarek (`GET /printers/` + statusy, polling co 5 s przez provider z `Timer`em); pull-to-refresh; stany błędów (serwer nieosiągalny, 401).
- **Dlaczego najpierw polling**: użyteczna apka w kilka tygodni; oddziela naukę „widgety + Riverpod + dio" od „streams + WS"; ścieżka pollingu zostaje na zawsze jako backfill po wznowieniu i fallback przy padzie WS.
- Ryzyko dnia pierwszego: blokada cleartext HTTP (patrz Ryzyka #2); branch auth-disabled/enabled.

### M2 — WebSocket na żywo (4–6 sesji)
- `WsClient` wg §3 (backoff, heartbeat, lifecycle, reaktywne 4401); dashboard aktualizuje się na żywo; baner stanu połączenia; polling zdegradowany do fallbacku. Testy jednostkowe parsera ramek + backoffu na fixture'ach z PRAWDZIWEGO serwera.
- Ryzyko: wycieki subskrypcji (nauka `autoDispose`); realne payloady `printer_status` różne od oczekiwań — **najpierw** przechwycić fixture'y z żywego serwera, parsery pisać pod nie.

### M3 — Szczegóły drukarki + kamera (4–6 sesji)
- Ekran szczegółów (temperatury, postęp, warstwa, ETA, sloty AMS jako kolorowe chipy); podgląd MJPEG przez stream-token; strumień stopowany, gdy ekran niewidoczny (route-aware dispose); endpoint snapshot jako fallback tap-to-refresh.
- Ryzyko: jakość flutter_mjpeg → dekoder zapasowy (§2); token strumienia 60 min → re-mint przy błędzie strumienia.

### M4 — Sterowanie (3–4 sesje)
- Pauza/wznów/stop (stop za dialogiem potwierdzenia!), światło komory, prędkość; optimistic UI z rollbackiem przy błędzie; kontrolki wyłączone przy braku scope'a (obsługa 403 dla `can_control_printer`).
- Ryzyko techniczne najniższe; ryzyko „ups, zatrzymałem 9-godzinny wydruk" najwyższe — **potwierdzenia to deliverable, nie szlif**. Testować na bezczynnej drukarce lub wirtualnej drukarce bambuddy.

### M5 — Kolejka + archiwum (5–7 sesji)
- Kolejka: `ReorderableListView`, swipe-to-delete z potwierdzeniem; archiwum: przeglądanie z wyszukiwaniem i miniaturami, re-print, dodanie do kolejki.
- Ryzyko: największa powierzchnia NOWYCH endpointów → największa ekspozycja na ruchliwość API; miniatury mogą wymagać nagłówków auth (image provider oparty o dio albo parametr `headers` w `Image.network`).

### M6 — Powiadomienia (4–6 sesji)
- (a) Foreground: eventy WS (wydruk skończony/błąd) → `flutter_local_notifications` z kanałami + flow uprawnienia Android 13; (b) tło: ekran ustawień tłumaczący setup ntfy z deep linkiem do instalacji/subskrypcji (**to wypływa pierwsze**), potem rejestracja `unifiedpush` z ntfy jako dystrybutorem; tap w powiadomienie → deep link do drukarki przez go_router.
- Ryzyko: najbardziej androidowy milestone (manifest, kanały, uprawnienia, OEM-owe zabijanie baterii — udokumentować „wyłącz optymalizację baterii dla ntfy"); format payloadu ntfy z bambuddy może wymagać zgadywania — fallback jest siatką bezpieczeństwa.

### M7 — Szlif + release (4–6 sesji)
- ~~Profile wielu serwerów~~ — **ODRZUCONE (świadoma decyzja, 2026-06-22): wspieramy dokładnie jeden serwer.** Proaktywne odnowienie tokenu WS; dark theme; ekran About z notą AGPL + linkiem do źródeł + licencjami zależności (`showLicensePage`); ikona; podpisany build release; metadane przyjazne F-Droid; README z notą zgodności wersji serwera.
- Ryzyko: zarządzanie kluczem podpisu (ZRÓB BACKUP); scope creep — v1 kończy się tutaj.

**Suma: ~32–48 sesji ≈ 4–6 miesięcy po godzinach.** Nauka jest z przodu: M0–M2 będą wolne, M4–M5 szybkie — warto to sobie powiedzieć zawczasu.

## 5. Strategia testów (solo, hobby)

**Zasada: testuj jednostkowo czysto-dartowy rdzeń, UI oglądaj oczami.**

- **Warto (tanio, wysoka wartość)**:
  - parsowanie JSON modeli — fixture'y w `test/fixtures/` przechwycone z PRAWDZIWEGO serwera (`curl`, jednorazowy log ramek WS). To zarazem tripwire na ruchliwość API: update serwera psujący pole zapala test, zanim apka się wywali;
  - parsowanie koperty WS + tolerancja nieznanych typów;
  - kalkulator backoffu + timeout heartbeatu (wstrzyknięty fałszywy zegar);
  - interceptor auth: 401 → refresh → retry; tryb bez auth nie dodaje nagłówków; tryb API-key ustawia `X-API-Key`;
  - repozytoria z `http_mock_adapter` (przypadki brzegowe kodów statusu).
- **Minimalne testy widgetów**: po jednym dla krytycznych — karta drukarki renderuje nazwę/postęp/temperatury z fixture'a; baner błędu przy `disconnected`. Koniec.
- **Pominięte w v1**: testy integracyjne, golden, automatyzacja UI. Substytut: `MANUAL_TESTING.md` — checklista per milestone (połączenie z auth on/off, złe hasło, serwer down, toggle Wi-Fi w trakcie streamu, tło/powrót w trakcie wydruku…), odhaczana przed każdym tagiem.
- **CI**: GitHub Actions — `flutter analyze`, `flutter test`, `flutter build apk --debug`. Ustawić w M0, póki trywialne.

## 6. Kluczowe ryzyka i mitygacje

1. **Ruchliwość API bambuddy (ryzyko nr 1)** — projekt młody, bez gwarancji dyscypliny wersjonowania. Mitygacje: (a) parsowanie defensywne wszędzie — pola nieistotne nullable, nieznane klucze ignorowane, nieznane typy ramek WS logowane i odrzucane, nigdy `!` na danych z serwera; (b) snapshot `openapi.json` w repo + zapis wersji serwera w README („tworzono pod bambuddy vX.Y"); (c) odczyt wersji serwera przy połączeniu i ostrzeżenie przy rozjeździe (nie blokada); (d) fixture'y-jako-kontrakt + mały skrypt `dart run tool/smoke.dart --server=...` odpytujący żywy serwer po jego upgradzie. Rozbudowane feature-detection poza v1 — pin-and-warn wystarczy.
2. **Android blokuje cleartext HTTP**, a self-hosted LAN to zwykle `http://` — bez tego każde żądanie padnie z mylącym błędem pierwszego dnia M1. Mitygacja: `android:usesCleartextTraffic="true"` w manifeście (uzasadnione dla narzędzia LAN) + podpowiedź w apce o HTTPS/reverse-proxy dla dostępu zdalnego. Certyfikaty self-signed: v1 „nieobsługiwane, użyj prawdziwego certu za reverse proxy"; pinning trust-on-first-use po v1.
3. **Tryb auth wyłączony** — łatwo napisać kod zakładający istnienie tokenu (WS `?token=`, stream-tokeny, interceptor). Mitygacja: enum `AuthMode {none, jwt, apiKey}` na `ServerProfile`, każda ścieżka auth po nim branchuje, checklista manualna odpalana w obu trybach. Detekcja przy setupie: nieuwierzytelniony `GET /printers/` — 200 znaczy auth off.
4. **JWT 24 h bez refresh-tokena** — mitygacja: zapamiętany login (opt-in) → cichy re-login przy 401; inaczej łagodne przekierowanie do ekranu logowania (nigdy crash, nigdy martwy dashboard). W UI konfiguracji **rekomendować klucze API** — bez wygasania, scope'owane, projektowane dla klientów.
5. **MJPEG na wolnych/zdalnych łączach** — każda klatka to pełny JPEG. Mitygacje: strumień tylko na widocznym ekranie (deliverable M3); tryb snapshot-polling (1 JPEG / 5 s) jako przełącznik użytkownika; czytelne UI „stream zatrzymany". Bez transkodowania — poza zakresem.
6. **Niezawodność powiadomień w tle** — ntfy/UnifiedPush zależy od przeżycia apki ntfy pod OEM-owym zarządzaniem baterią. Mitygacja: projekt fallback-first (M6) — ścieżka „po prostu użyj apki ntfy" działa zawsze, bo to dobrze przetestowana dostawa ntfy; UnifiedPush jest ulepszeniem, nie fundamentem.
7. **Higiena licencyjna** — apka AGPL-3.0: LICENSE od M0, ekran About z linkiem do źródeł. **BamPocket (AGPL)**: wolno czytać i adaptować z atrybucją. **Mobileraker: tylko inspiracja, zakaz kopiowania kodu** (licencja non-forkable). Wszystkie pakiety z §2 są BSD/MIT/Apache — OK wewnątrz aplikacji AGPL.
8. **Początkujący + po godzinach = ryzyko utraty momentum** — mitygacje wbudowane w kolejność milestone'ów: każdy kończy się czymś osobiście używanym na własnej drukarce; polling-przed-WS i fallback-przed-UnifiedPush istnieją właśnie po to, żeby uniknąć wielotygodniowych bagien bez działającego efektu.

## 7. Plan nauki (wpleciony w milestone'y)

| Faza | Do nauczenia | Kształt materiałów |
|---|---|---|
| M0 | Dart: null safety (`?`, `late`, promocja typów), klasy/konstruktory, `Future`/`async`/`await`. Flutter: drzewo widgetów, `StatelessWidget` vs `StatefulWidget`, hot reload, layout (`Column/Row/Expanded/ListView`) | Oficjalny Dart language tour; codelab „Write your first Flutter app". Streams jeszcze NIE. |
| M1 | Riverpod: `ProviderScope`, `Provider`, `FutureProvider`, `ref.watch` / `AsyncValue.when`. Podstawy dio + interceptory. Workflow `json_serializable` + `build_runner watch`. Nawigacja go_router | Dokumentacja Riverpod (tylko sekcje „providers" + „reading"); oprzeć się pokusie nauki wszystkich 8 typów providerów. |
| M2 | **Dart Streams dogłębnie** (`StreamController`, broadcast, `listen`/cancel, transform) — koncepcyjne serce aplikacji. `NotifierProvider`, `StreamProvider`, `autoDispose`. `AppLifecycleListener` | Milestone, na którym należy ZWOLNIĆ; menedżer WS to masterclass ze streams. |
| M3 | Lifecycle widgetów (`initState`/`dispose`), świadomość trasy, render obrazów, bajty (`Uint8List`) jeśli potrzebny własny dekoder | |
| M4–M5 | Głównie stosowanie znanych wzorców. Nowe: optimistic updates, `ReorderableListView`, dialogi/snackbary, formularze | Szybkie milestone'y — do cieszenia się. |
| M6 | Specyfika Androida: manifest, model uprawnień (runtime `POST_NOTIFICATIONS`), kanały powiadomień, intenty/deep linki | Pierwszy poważny kontakt z `android/`. |
| M7 | Podpisywanie, podstawy R8, theming | |
| Celowo odłożone | freezed, riverpod codegen, isolates, platform channels, animacje poza implicit, CustomPaint | Po v1 albo nigdy. |

## 8. Pliki nośne (kolejność tworzenia)

1. `lib/core/api/api_client.dart` — dio + interceptor auth; wszystko od niego zależy (M1)
2. `lib/core/api/ws_client.dart` — maszyna stanów WS, reconnect/backoff/4401 (M2, najryzykowniejszy komponent)
3. `lib/core/models/printer_status.dart` — centralne DTO parsowane z REST i WS; tu ustala się wzorzec parsowania defensywnego
4. `lib/core/settings/server_profile.dart` — URL + enum `AuthMode`; od niego branchuje każda ścieżka auth
5. `lib/features/dashboard/providers.dart` — miejsce scalenia pollingu REST, strumienia WS i backfillu po wznowieniu w stan UI
