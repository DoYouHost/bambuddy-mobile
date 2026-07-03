# Przegląd kodu — znaleziska (2026-07-03)

Przegląd całego `lib/` + strony natywnej Androida pod kątem bugów, wydajności i refactoru.
Wykonany pięcioma równoległymi agentami (core API/WS/auth · tło FGS/powiadomienia/widget ·
warstwa danych/modele · UI dashboard/kolejka/archiwum/pliki · UI inventory/projekty/reszta + Android).
`flutter analyze`: **czysty** (0 problemów). Świadome decyzje projektowe z pamięci projektu
(merge statusu bez zerowania, priming pierwszej ramki, filtr HMS, quirki serwera itd.)
zostały wykluczone z przeglądu i NIE figurują tu jako błędy.

Stan: **kompletny** (sekcje 1–5). Sekcja 4 wykonana ręcznie po tym, jak agent padł na
limicie tokenów — każde znalezisko zweryfikowane bezpośrednio w kodzie.

Legenda: **[H]** high / **[M]** medium / **[L]** low · kategorie: bug / perf / refactor.

---

## 1. Core: API / WebSocket / auth

### 1.1 [H][bug] ✅ NAPRAWIONE — Brak single-flight dla cichego re-loginu — równoległe `POST /auth/login`
`lib/core/auth/auth_service.dart:145-157` (+ `api_client.dart:88-104`, `providers.dart:129,193-194`, `ws_providers.dart:73`)

`AuthInterceptor.onError`, `WsClient._handleConnectError` i `ProactiveTokenRefresher._fire`
wołają to samo `silentReLogin` bez żadnej koordynacji. `PrintersRepository.fetchAll`
(`printers_repository.dart:62-70`) robi N równoległych `fetchStatus` przez `Future.wait`,
więc wygaśnięcie JWT = N jednoczesnych 401 + odrzucony handshake WS → ~6 równoległych
loginów. Jeśli serwer unieważnia poprzedni JWT przy nowym loginie, ponowiony request
dostaje drugie 401 (`alreadyRetried`) → `AuthException` → dashboard wyrzuca usera na `/setup`.

**Fix:** memoizacja jednego in-flight `Future<String?>` w `AuthService` (wszyscy równolegli
wołający dostają tę samą przyszłość; czyszczenie po zakończeniu).

### 1.2 [M][bug] ✅ NAPRAWIONE — Heartbeat pisze do potencjalnie zamkniętego sinka bez zabezpieczenia
`lib/core/api/ws_client.dart:322-328`

```dart
_heartbeat = Timer.periodic(
  heartbeatInterval,
  (_) => _conn?.send(jsonEncode({'type': 'ping'})),
);
```
Okno: zdalne zamknięcie socketa, `onDone` jeszcze niedostarczone → `_conn` niezerowe,
ping trafia w zamknięty sink → `StateError` ucieka z callbacku timera (uncaught, bez recovery).

**Fix:** try/catch wokół send i/lub wysyłka tylko gdy `_state == connected`.

### 1.3 [M][perf] ✅ NAPRAWIONE (razem z 2.2 + 2.3) — Publikacja widgetu przy każdej ramce WS i każdym ticku pollingu
`lib/features/dashboard/ws_providers.dart:141-150` (wywołania w :105 i :191)

`_publishWidget()` odpala się na każdą ramkę `printer_status` i każdy poll — przy aktywnym
druku wielu drukarek to wiele rund platform-channel na sekundę + próba pobrania okładki.

**Fix:** debounce/coalescing (max raz na kilka sekund), analogicznie do
`_scheduleQueueMaintenanceRefresh`. (Patrz też 2.3 — ta sama klasa problemu w izolacie tła.)

### 1.4 [M][bug] ✅ NAPRAWIONE (razem z 4.9) — Klasyfikacja błędu auth WS po substringu `toString()` — kolizja z portem
`lib/core/api/ws_client.dart:361-368`

```dart
final s = error.toString().toLowerCase();
return s.contains('401') || s.contains('403') || ...
```
Serwer na porcie zawierającym `401`/`403` (np. `host:8403`): zwykły `SocketException`
zawiera adres z portem → fałszywy „auth error" → przy każdej czkawce sieci klient
unieważnia token WS i przepala jednorazowy cichy re-login zamiast zwykłego backoffu.

**Fix:** zakotwiczyć dopasowanie (typ `WebSocketException` / prefiks statusu), nie goły substring.

### 1.5 [L][bug] ✅ NAPRAWIONE — Połknięcie WSZYSTKICH błędów mintu tokenu WS zlewa 404 z awarią przejściową
`lib/core/api/ws_client.dart:227-231` (+ `ws_token.dart:42-46`)

`WsTokenService.token()` celowo zwraca `null` tylko na 404, a resztę rzuca — ale catch-all
w `ws_client` spłaszcza przejściowy 500/błąd sieci do fallbacku header-only. Na nowym
serwerze (wymagany `?token=`) → 401 → uruchamia się (błędne) lekarstwo re-login zamiast
backoff-i-ponowny-mint. Samonaprawialne, ale marnuje jednorazowy re-login.

**Fix:** fallback header-only tylko przy zwróconym `null` (404); resztę błędów puścić w normalny retry.

### 1.6 [L][bug] ✅ NAPRAWIONE — `wsConnectionStateProvider` bez seedu — spóźniony subskrybent nie widzi `connected`
`lib/features/dashboard/ws_providers.dart:212-216` (konsument: `dashboard/providers.dart:72-74`)

Broadcast stream deduplikuje i nie odtwarza bieżącej wartości: jeśli `connected` padło przed
pierwszym watch, `valueOrNull == null` → `_wsConnectedNow()` = false → dashboard zostaje
na szybkim pollu 5 s do następnej zmiany stanu.

**Fix:** zasiać strumień bieżącym stanem klienta (`Stream.value(client.state).followedBy(...)`
lub `initialValue`).

### 1.7 [L][perf] ✅ NAPRAWIONE — `ingestPoll` zawsze ustawia `changed = true` — pełna wymiana mapy co 5 s
`lib/features/dashboard/ws_providers.dart:181-188`

Każdy poll tworzy nowe instancje `PrinterStatus` (mergedWith) i nową mapę → wszyscy
konsumenci `printerStatusesProvider` przebudowują się co tick, nawet bez realnej zmiany;
dodatkowo odpala się `_publishWidget`.

**Fix:** value-equality na `PrinterStatus` (lub diff merged vs previous) i podmiana stanu
tylko przy realnej zmianie.

### 1.8 [L][refactor] `routerProvider` nie dispose'uje poprzedniego `GoRouter`
`lib/router.dart:38-41`

Każde „zmień serwer" (profil set→null→set) buduje nowy `GoRouter`, stary z listenerami
wycieka. Rzadkie i małe, ale fix trywialny.

**Fix:** `ref.onDispose(router.dispose)`.

### 1.9 [L][refactor] `WsTokenService` i `CameraTokenService` niemal identyczne, oba bez single-flight mintu
`lib/core/api/ws_token.dart:14-62` vs `camera_token.dart:12-56`

Ta sama struktura cache + TTL 55 min + mint + `invalidate`; równolegli wołający przy
wygasłym cache mintują wielokrotnie.

**Fix:** wspólna baza `CachedTokenService` z in-flight future; specjalizacja endpointu
i zachowania 404.

**Czyste:** `jwt.dart`, `ws_backoff.dart` (full jitter, clamp OK), `credentials_store.dart`,
`server_profile.dart`, `api_exceptions.dart`, `endpoints.dart`; `ProactiveTokenRefresher`
(generation-guard, idempotentny start/stop); maszyna stanów `WsClient`
(suspend/resume/dispose, watchdog vs onDone, add-after-close) poza 1.2; ścieżka retry
`AuthInterceptor` (guard `_retriedFlag`); wiring lifecycle w `dashboard_screen`/`app.dart`
(mounted-checks poprawne).

---

## 2. Tło: FGS / powiadomienia / widget

### 2.1 [H][bug] ✅ NAPRAWIONE (+ 2.10 przy okazji) — `onStart` izolatu FGS bez top-level try/catch — awaria startu = „kłamiące" powiadomienie o monitoringu
`lib/core/notifications/print_monitor_task_handler.dart:61-134`

Wyjątek z `SecureCredentialsStore`/`buildBackgroundApiClient` (keystore na niektórych OEM)
przerywa `onStart` przed `ws.start()` — serwis i notyfikacja „monitoring aktywny" żyją,
ale nic nie jest monitorowane i żaden alert nie przyjdzie.

**Fix:** try/catch wokół całego body; przy porażce notyfikacja stanu zdegradowanego
albo `stopService()`.

### 2.2 [M][bug] ✅ NAPRAWIONE — Publikacje widgetu nieserializowane — stara ramka potrafi nadpisać nowszą (stale cover)
`lib/core/widget/home_widget_publisher.dart:70-99` (wołane z `ws_providers.dart:142-149`
i `print_monitor_task_handler.dart:115-122`)

Publish jest fire-and-forget; w środku `await fetchCover(...)` (sieć). Ramka A wisi na
pobraniu okładki, ramka B kończy publish z świeżym stanem, potem A dopisuje swój stary
`cover_path` i woła `updateWidget` → widget miga wstecz. Na przejściach fg↔bg oba izolaty
piszą ten sam `widget_cover.jpg` bez locka → możliwa porwana bitmapa.

**Fix:** serializacja per-izolat (drop-if-in-flight lub queue-latest); zapis okładki do
pliku tymczasowego + atomiczny rename.

### 2.3 [M][perf] ✅ NAPRAWIONE — Pełny republish widgetu (9× `saveWidgetData` + natywny broadcast) na każdą ramkę, bez change-detection
`ws_providers.dart:97-110` / `print_monitor_task_handler.dart:110-123`

Ongoing-notyfikacja jest dławiona przez `_OngoingKey`, widget nie — jitter temperatur
co sekundę przez wielogodzinny druk = zbędny drenaż baterii w obu izolatach.

**Fix:** mały „widget key" (id, status_key, progress, minuta ETA, warstwy, cover_url)
i skip gdy bez zmian — lustrzane do `_OngoingKey`. (Łącznie z 1.3 = jeden wspólny fix.)

### 2.4 [M][refactor] `showOngoing`/`clearOngoing` + kanał `ongoing_print` to martwy kod w produkcji
`lib/core/notifications/notification_service.dart:57-135`

Jedyny produkcyjny `PrintMonitor` (izolat tła) używa `_FgsNotificationService`
(`updateService`); izolat UI w ogóle nie buduje `PrintMonitor`. Kanał `ongoing_print`
jest tworzony i widoczny w ustawieniach Androida, ale nigdy nie niesie powiadomienia.

**Fix:** usunąć `showOngoing`/`clearOngoing`/`_ongoingId`/`_ongoingChannelId` z
`LocalNotificationService` (zostawić w interfejsie abstrakcyjnym).

### 2.5 [L/M][bug] ✅ NAPRAWIONE — `WidgetCoverCache.reset()` nigdy niewołane — reprint tego samego pliku może pokazać starą miniaturę
`lib/core/widget/widget_cover_cache.dart:30,71-76`

Cache short-circuituje po identycznym `cover_url`; jeśli serwer wystawia stabilny URL
okładki „bieżącego druku", reprint dostaje starą bitmapę.

**Fix:** wołać `reset()` przy końcu druku / zniknięciu okładki, albo kluczować cache
po treści, nie po URL.

### 2.6 [L/M][perf/refactor] `buildBackgroundApiClient(prefs)` budowane 2× przy starcie (+ trzeci `AuthService` w `_setUpTokenRefresh`)
`print_monitor_task_handler.dart:79,155`

Każde wejście w tło konstruuje wielokrotnie Dio + interceptory + odczyt keystore.

**Fix:** jeden uwierzytelniony `ApiClient` w `onStart`, przekazywany do cover-tokenu,
repo maintenance i token refreshera.

### 2.7 [L][bug] Listener WS: `_monitor?.update(...)` bez guardu (publish jest zabezpieczony, update nie)
`print_monitor_task_handler.dart:110-112`

Throw z `update` (l10n / `updateService`) = uncaught zone error + utrata przetwarzania
zboczy tej ramki.

**Fix:** try/catch (swallow-and-continue), spójnie z guardem publisha.

### 2.8 [L][bug] `onDestroy` nie kasuje offline-timerów `PrintMonitor` (brak `dispose()`)
`print_monitor_task_handler.dart:207-214`

Przeważnie łagodne (izolat i tak umiera), ale przy ewentualnym reuse handlera wiszący
15-sekundowy timer offline mógłby odpalić po stopie serwisu.

**Fix:** `PrintMonitor.dispose()` kasujący `_memo[*].offlineTimer`, wołany z `onDestroy`.

### 2.9 [L][bug] Wyścig „Oznacz wykonane" (izolat callbacku) vs `MaintenanceMonitor._notified` (izolat FGS)
`background_api.dart:77-83` vs `maintenance_monitor.dart:61-68`

Callback usuwa id z `maintenance_notified_due_ids` na dysku, ale monitor w FGS trzyma
własny zbiór w pamięci i przy następnym `check()` (30 min) może go z powrotem dopisać,
jeśli serwer jeszcze nie pokazuje `is_due=false`. Samonaprawialne; skutek = możliwy
zgubiony re-alert.

**Fix:** `check()` powinien najpierw przeładować zbiór z dysku (merge), albo callback
powinien sygnalizować żywemu monitorowi usunięcie id.

### 2.10 [L][bug] Null profile w `onStart` → goły `return` zostawia działający pusty serwis
`print_monitor_task_handler.dart:62-67`

Edge case (profil wyczyszczony w tle): FGS + notyfikacja żyją bezczynnie aż UI wróci
i zatrzyma serwis.

**Fix:** `FlutterForegroundTask.stopService()` w tej gałęzi zamiast `return`.

**Czyste:** ograniczony wzrost stanu dedupu (`hmsLastSeen` przycinane grace'em,
`milestonesSent` ≤3, zbiory low-filament/humidity z histerezą, czyszczenie `_statuses`/`_memo`);
detektory zboczy zgodne z testami (priming OK); generation-guardy WsClient i
ProactiveTokenRefresher; handlery akcji powiadomień w `background_api.dart` w pełni
error-swallowed i odbudowują stan od zera (bezpieczne przy martwym procesie).

---

## 3. Warstwa danych i modele

### 3.1 [H][bug] ✅ NAPRAWIONE — Generowane parsery list rzucają na nie-obiektowym elemencie (`e as Map<String, dynamic>`)
`project.g.dart:36,129`, `maintenance.g.dart:20`, `library_folder.g.dart:22`

Ręczne parsery wszędzie robią `if (item is! Map<String, dynamic>) continue;` — generowane
casty nie. Skutki: w `ProjectsRepository.get()` (`projects_repository.dart:54-61`)
`TypeError` NIE jest łapany przez `on DioException` → ucieka poza kontrakt mapowania
wyjątków i wywala ekran detalu projektu. W `listFolders()`/`fetchOverview()` (zewnętrzny
per-item try/catch) jeden zły liść cicho kasuje CAŁY rekord rodzica — dla folderów całe
poddrzewo (parsowanie rekurencyjne).

**Fix:** guardy `is! Map` w custom `fromJson` albo `@JsonKey(fromJson:)` z tolerancyjnymi
konwerterami (wzorzec z `printer_status.dart`).

### 3.2 [H][bug] ✅ NAPRAWIONE — Generowane `DateTime.parse(... as String)` na nullable polach dat — sprzeczne z projektową tolerancją
`archive.g.dart:22-24`, `library_file.g.dart:20-22`, `queue_item.g.dart:32-40`, `trash_file.g.dart:16-21`

Call-site'y owijają każdy element listy w `try { } on Object { continue; }`
(`archive_repository.dart:43-47`, `queue_repository.dart:38-42`,
`library_repository.dart:40-44,65-69,274-278`) — więc jeden zepsuty/nietypowy timestamp
nie nulluje pola, tylko **cicho usuwa cały wpis** archiwum/pliku/pozycji kolejki/kosza,
bez żadnego błędu dla usera.

**Fix:** `DateTime.tryParse` + tolerancja typów (wzorzec `maintenance.dart`:
`lastPerformedAt`/`performedAtDate`).

### 3.3 [M][bug] `slicer_repository.dart:87` — `as num?` może rzucić `TypeError` poza kontraktem wyjątków
```dart
final id = (res.data?['job_id'] as num?)?.toInt();
```
Null jest obsłużony (`ApiException(malformedResponse)`), ale nienumeryczny `job_id`
(np. string) rzuca surowy `TypeError`, który nie jest `DioException` → ucieka z
`on DioException catch`.

**Fix:** tolerancyjny helper `_toIntOrNull` zamiast gołego casta.

### 3.4 [L][bug] `archive_repository.dart:141-142` — strict `is int` na `deleted`
Serwer serializujący licznik jako float (`5.0`) → metoda raportuje „0 usuniętych" mimo
udanego purge. Wszędzie indziej używane są tolerancyjne helpery.

**Fix:** tolerancyjna koercja int.

### 3.5 [refactor] Wszechobecna duplikacja `try/on DioException/mapDioException` + pętli parsowania list
Kształt try/catch skopiowany w ~17 repozytoriach (80+ wystąpień); pętla
„skip non-map, catch-and-continue per item" niezależnie reimplementowana w
`archive_repository.dart:40-48,70-78`, `library_repository.dart:37-46,62-71,270-281`,
`maintenance_repository.dart:84-95`, `makerworld_repository.dart:74-84`,
`printers_repository.dart:32-41`, `queue_repository.dart:35-44`,
`smart_plugs_repository.dart:38-47`, `inventory_source.dart:63-77`,
`projects_repository.dart:423-437`.

**Fix:** wspólne `guard(...)` + `parseJsonList<T>(...)` — centralizuje też naprawy 3.1–3.3.

### 3.6 [refactor] Zduplikowane helpery koercji `_int`/`_toInt`, `_double`/`_toDouble`, `_str`/`_pickString`
`archive_slim.dart:80-96`, `archive_stats.dart:92-117`, `archive_purge.dart:36-46`,
`failure_analysis.dart:85-103`, `inventory.dart:458-469`, `inventory_reference.dart:109-125`,
`swatch_code.dart:133-136`, `ams_history.dart:77-81`, `makerworld.dart:29-48` —
z niespójnym defaultowaniem (`?? 0` vs `null`).

**Fix:** jeden `lib/core/models/json_utils.dart`.

### 3.7 [refactor] Martwe endpointy w `endpoints.dart`
Nigdzie nieużywane: `firmwareLatest` (:284), `inventorySpoolKProfiles` (:254-255),
`projectsImport` (:426, zastąpione przez `projectsImportFile`), `cameraSnapshot` (:44-45),
`libraryFileDownload` (:318-319). (Uwaga: `inventorySpoolKProfiles` może czekać na
odłożoną zakładkę PA Profile — decyzja usera.)

### 3.8 [perf] Zero użyć `CancelToken` w całej warstwie danych
Np. `ArchiveRepository.search` (`archive_repository.dart:55-59`) — search-as-you-type
nie anuluje zastąpionych żądań; marnowane pasmo + okno wyścigu, w którym stara odpowiedź
ląduje po świeższej.

**Czyste:** `printer_status.dart` (wzorcowy defensywny parser + `mergedWith`);
`inventory.dart`/`inventory_reference.dart`; spójny wzorzec „auth bubble-up, reszta →
null" we wszystkich repo danych per-drukarka; paginacja `stats_repository.fetchSlim`
poprawnie ograniczona. Zweryfikowany NIE-problem: `Endpoints.projectAttachment` —
serwer zawsze zwraca wygenerowany `uuid4().hex + rozszerzenie z allow-listy`, nie surową
nazwę uploadu (sprawdzone w `reference/bambuddy/backend/app/api/routes/projects.py:906-917`).

---

## 4. UI: Dashboard / Kolejka / Archiwum / Pliki / Kamera

### 4.1 [M][bug] ✅ NAPRAWIONE — Wyszukiwarka archiwum bez guardu generacji — spóźniona odpowiedź nadpisuje świeższą
`lib/features/archive/archive_providers.dart:82-92`

`search()` nie sprawdza po `await`, czy zapytanie jest wciąż aktualne (brak licznika
generacji / `CancelToken` — patrz 3.8). Scenariusz: wpisz „benchy" (wolny `/archives/search`),
skasuj do pustego (szybki `/archives/` kończy się pierwszy) → wynik „benchy" ląduje PO
pełnej liście i zostaje na ekranie, choć pole wyszukiwania jest puste. Debounce 300 ms
w ekranie zmniejsza, ale nie eliminuje okna.

**Fix:** licznik generacji w notifierze (wzorzec `DashboardNotifier._generation`) —
odrzucać wynik, gdy `state.query` w międzyczasie się zmienił.

### 4.2 [M][bug] ✅ NAPRAWIONE (razem z 4.6) — Menedżer plików: gettery `_l10n`/`_messenger` czytają `context` po `await` — bez żadnego mounted-checku
`lib/features/files/file_manager_screen.dart:43-44` (użycia po await: :380-383, :394-399,
:412-417, :428-433, :442-449, :461-466, :479-485, :491-496, :501-505, :519-526, :560-572)

Wszystkie akcje mutujące (create/rename/delete/move/upload/print/addToQueue) wołają po
`await` `_snack(_l10n...)`, a oba gettery robią `AppLocalizations.of(context)` /
`ScaffoldMessenger.of(context)` na żywo. Zburzenie ekranu w trakcie dialogu/żądania
(np. redirect zmiany serwera) → „Looking up a deactivated widget's ancestor is unsafe".
Ta sama klasa co 5.5/5.6; w tym pliku wzorzec jest systemowy (kilkanaście miejsc).

**Fix:** złapać `l10n`+`messenger` do lokalnych PRZED pierwszym await (jak robi to
archive_screen) albo `if (!mounted) return;` po każdym await.

### 4.3 [M][perf] ✅ NAPRAWIONE (razem z 5.7) — Miniatury list bez `cacheWidth` — pełna dekompresja do kafelków 52–72 dp
`lib/features/common/print_thumbnail.dart:57`, `lib/features/files/library_thumbnail.dart:53`,
`lib/features/dashboard/widgets/printer_card_panels.dart:416` (`_CoverThumbnail`)

Archiwum stronicuje po 50 pozycji, każda z `Image.network` bez `cacheWidth/cacheHeight` —
bitmapy dekodowane w pełnej rozdzielczości renderu serwera do kafelka ~56 dp. Skok RAM
i jank przy szybkim scrollu. Ta sama klasa co 5.7 (makerworld/projekty).

**Fix:** `cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round()` we
wszystkich trzech wspólnych widgetach miniatur (naprawia od razu kolejkę, archiwum,
pliki i kartę drukarki).

### 4.4 [L/M][perf] ✅ NAPRAWIONE — Timer odświeżania kolejki (10 s) tyka zawsze na pierwszym planie — także gdy karta Kolejka nie jest widoczna
`lib/features/queue/queue_screen.dart:57-63` (+ `root_scaffold.dart:25-37`)

`StatefulShellRoute` trzyma odwiedzone gałęzie zamontowane, więc po pierwszym wejściu
w Kolejkę jej `Timer.periodic` chodzi do końca życia apki na foregroundzie (pauza tylko
w tle). Równolegle: poll dashboardu (5 s), gniazdek (5 s) i pełny fetch kolejki (10 s).
Dodatkowo badge w `RootScaffold` i tak watchuje `queueProvider` globalnie.

**Fix:** gate'ować timer widocznością gałęzi (`navigationShell.currentIndex` /
`ModalRoute.isCurrent`/`TickerMode`), a badge zostawić na rzadszym odświeżaniu.

### 4.5 [L/M][bug] ✅ NAPRAWIONE (nie zweryfikowane na żywo) — Niespójne kluczowanie globalnego indeksu AMS: pozycja listy vs `unit.id`
`lib/features/queue/queue_mapping_sheet.dart:63-66` vs
`lib/features/dashboard/widgets/printer_card_details.dart:402,433-439`

Arkusz mapowania liczy `global = u * 4 + tray` z POZYCJI jednostki na liście, ścieżka
inventory tegoż providera używa `a.amsId * 4`, a panel szczegółów karty `unit.id ?? unitIndex`.
Gdy `ams[].id` nie pokrywa się z pozycją (np. pojedynczy AMS o id=1 po odpięciu pierwszego),
mapowanie wskaże złe gniazdo → drukarka odrzuca start („unable to fetch AMS mapping").

**Fix:** ujednolicić na `unit.id ?? index` we wszystkich trzech miejscach; zweryfikować
na żywo na X2D.

### 4.6 [L][bug] ✅ NAPRAWIONE — `_promptName` — `TextEditingController` bez dispose przy każdym dialogu
`lib/features/files/file_manager_screen.dart:580`

Kontroler tworzony per wywołanie (nowy folder / zmiana nazwy), nigdy nie zwalniany —
ta sama klasa co 5.8 (maintenance). Wzorzec poprawny istnieje: `_NotesEditDialog`.

### 4.7 [L][bug] `setQuery` — podwójny fetch indeksu wyszukiwania i cicha porażka
`lib/features/files/file_manager_providers.dart:247-266`

Dwa szybkie zapytania zanim `allFiles` się załaduje → `needsFetch` liczone ze starego
stanu → dwa równoległe `listAllFiles()`. Błąd fetchu tylko zdejmuje spinner
(`searching:false`) — użytkownik dostaje puste wyniki bez informacji o błędzie.

**Fix:** flaga in-flight w notifierze + komunikat/retry przy porażce.

### 4.8 [L][bug] Podwójna injekcja skryptu w podglądzie G-code
`lib/features/gcode/gcode_viewer_screen.dart:93-96,179-181`

`_ready` ustawiane dopiero PO `await runJavaScript`, a `onPageFinished` może odpalić
dwukrotnie (redirect/ponowny load) zanim pierwszy przebieg skończy → `loadArchive(...)`
wywołane 2×. Patch `window.fetch` jest chroniony (`__bbApiKeyPatched`), samo ładowanie nie.

**Fix:** ustawić `_ready = true` (albo osobną flagę `_injecting`) synchronicznie przed await.

### 4.9 [L][bug] ✅ NAPRAWIONE — `error.toString().contains('401')` w kamerze — kolizja z portem w URL
`lib/features/camera/camera_view.dart:77`

Ta sama klasa co 1.4: serwer na porcie zawierającym „401" sprawia, że zwykły błąd sieci
wygląda jak wygaśnięcie tokenu. Skutek złagodzony guardem `_remintedFor` (jeden zbędny
re-mint), ale warto naprawić razem z 1.4.

### 4.10 [L][bug] `RefreshIndicator` kosza kończy się natychmiast
`lib/features/files/trash_screen.dart:61`

`onRefresh: () async => ref.invalidate(libraryTrashProvider)` — invalidate nie czeka na
przeładowanie, spinner znika od razu, lista podmienia się chwilę później.

**Fix:** `onRefresh: () => ref.refresh(libraryTrashProvider.future)`.

### 4.11 [refactor] Zduplikowane pickery drukarki, `_errText` i formatery bajtów
`archive_screen.dart:473-517` vs `file_manager_screen.dart:646-684` (niemal identyczny
`_pickPrinter` + `_errText`); trzecia wariacja w `queue_screen.dart:594-633`;
`_formatBytes` (`archive_screen.dart:888`) vs `formatBytes` (`file_manager_screen.dart:921`)
— dwa formatery bajtów różniące się tylko zaokrągleniem.

**Fix:** wspólny `pickPrinterSheet(...)` + jeden `formatBytes` w `features/common/`.

**Czyste:** reorder kolejki POPRAWNY — nowe API `onReorderItem` (Flutter 3.44) ma już
skorygowany `newIndex` (zweryfikowane w źródłach SDK), offset przypiętych pozycji dobrze
policzony, payload 1..N zgodny z quirkiem serwera; optymistyczne mutacje kolejki/archiwum
(rollback do snapshotu) i `ControlsNotifier`/`SmartPlugsNotifier` (chirurgiczny rollback,
timery sprzątane w onDispose, generation-guardy pollingu) — solidne; Dismissible z
`confirmDismiss`→`onDismissed` w dobrej kolejności; debounce offline karty drukarki z
poprawnym sprzątaniem timera; lifecycle dashboardu (pauza WS/polling/token-refresher w tle)
spójny; `_awaitingPlateClear` słusznie preferuje cache statusu (przeżywa offline);
`_SummaryHeader` i `_ControlsActions` używają `select` (dobra granulacja rebuildów);
arkusz historii AMS (fl_chart) czysty; parser/grupowanie temperatur czyste; CameraView
poprawnie zarządza cyklem życia MJPEG (dispose przez pakiet, jednorazowy re-mint na 401).

---

## 5. UI: Inventory / Projekty / Stats / MakerWorld / reszta + natywny Android

### 5.1 [H][bug] ✅ NAPRAWIONE — `stats_providers.dart:165-187` — flaga `_disposed` zabija odświeżanie w tle po pierwszej zmianie filtra
`ref.onDispose` odpala się przy każdym **recompute** providera (nie tylko przy zniszczeniu),
a `_disposed` nigdy nie wraca na `false`. Po zmianie zakresu dat (build #2 po onDispose
builda #1) każdy wynik `_refreshInBackground` jest po cichu wyrzucany — ekran pokazuje
stary cache aż do pełnego dispose (wyjścia z ekranu).

**Fix:** reset `_disposed = false` na początku `build`, albo build-lokalne `var alive = true`
domknięte w closure.

### 5.2 [M][bug] ✅ NAPRAWIONE — `inventory_form.dart:368-376` — dropdown wagi rdzenia z wartością spoza `items`
`initialValue: _coreWeightCatalogId`, ale `items` budowane tylko z bieżącego katalogu
`cores`. Edycja szpuli, której wpis katalogowy usunięto serwerowo → assertion
„exactly one item with value" (crash sheeta w debug), pusta/zła selekcja w release.

**Fix:** wyzerować id gdy brak w `cores` (lub wstrzyknąć syntetyczny wpis) — jak robi to
`_effectDropdown` (`{..._effectOptions, ?_effectType}`, linia ~402).

### 5.3 [M][bug] ✅ NAPRAWIONE — `project_form_screen.dart:247-254` — dropdown rodzica z listy PRZEFILTROWANEJ statusem
`items` z `projectsListProvider` (filtr statusu), `initialValue: _parentId` — rodzic
zarchiwizowany/ukończony (albo lista jeszcze się ładuje) → ta sama asercja dropdownu
przy otwarciu formularza.

**Fix:** opcje bez filtra, albo fallback `DropdownMenuItem(value: _parentId, ...)` gdy
id nieobecne.

### 5.4 [M][bug] ✅ NAPRAWIONE — `inventory_sheets.dart:147-155,195` — stan dropdownu jednostki AMS przeżywa zmianę drukarki
Skorygowane `value:` działa tylko jako `initialValue` wewnętrznego FormFielda i nie wraca
do `_amsUnit`; `_assign` wysyła stary `_amsUnit`. Wybór jednostki 4 → przełączenie na
drukarkę z jednym AMS → crash asercji w debug; w release żądanie z `ams_id=3`, którego
ta drukarka nie ma.

**Fix:** reset `_amsUnit` w `onChanged` drukarki + `key: ValueKey(_printerId)` na
dropdownach (lub pełny lift value+onChanged).

### 5.5 [M][bug] ✅ NAPRAWIONE — `cloud_account_screen.dart:154-155,177-178` — `BuildContext` po `await` bez mounted w ścieżkach błędów
`on AppApiException catch (e) { _snack(e.localized(_l10n)); }` gdzie `_l10n` czyta
`AppLocalizations.of(context)`. Wyjście z ekranu w trakcie `login()`/`verify()` +
porażka żądania → „Looking up a deactivated widget's ancestor is unsafe".
(`_signOut` w tym samym pliku robi to poprawnie.)

**Fix:** `if (!mounted) return;` na początku obu catch-y.

### 5.6 [M][bug] ✅ NAPRAWIONE — `swatches_screen.dart:38-43` (call-site'y 66, 133-134, 149-154, 174) — guard mounted w `_snack` zneutralizowany
Argumenty typu `_l10n.swatchCreatedSnack(...)` ewaluują `AppLocalizations.of(context)`
ZANIM `_snack` sprawdzi `mounted`; `_openForm`/`_import` wołają też `ref.read` po await
bez guardu. Zamknięcie ekranu przy otwartym sheecie/pickerze → deactivated-context /
„ref after dispose".

**Fix:** złapać `l10n` przed await albo mounted-check na call-site.

### 5.7 [M][perf] ✅ NAPRAWIONE — `makerworld_thumbnail.dart:46-55` — `Image.network` bez `cacheWidth/Height`
Pełnowymiarowe okładki dekodowane do kafelków 48–72 dp; model z dziesiątkami płyt →
skok pamięci + jank. To samo w `project_cover_image.dart:59`.

**Fix:** `cacheWidth: (size * devicePixelRatio).round()`.

### 5.8 [L/M][bug] ✅ NAPRAWIONE — `maintenance_screen.dart:239` — `TextEditingController` per tap „wykonaj", nigdy nie dispose'owany
`_MaintenanceTile` to ConsumerWidget — brak hooka dispose; jeden wyciek na każdy dialog
potwierdzenia. Repo ma już poprawny wzorzec: `_NotesEditDialog`
(`project_detail_screen.dart:449-451`).

**Fix:** mały StatefulWidget-dialog jak `_NotesEditDialog`.

### 5.9 [L/M][bug] `projects_screen.dart:144` — `cacheBust: project.createdAt` nigdy się nie zmienia
Model listy nie ma `updatedAt` (`core/models/project.dart:47`) → po podmianie okładki
z detalu (bust po `updatedAt`) lista pokazuje starą grafikę z cache obrazów do restartu apki.

**Fix:** `updated_at` w odpowiedzi listy, albo `NetworkImage(url).evict()` po
uploadzie/usunięciu okładki.

### 5.10 [L][bug] ✅ NAPRAWIONE — `slice_sheet.dart:149-154,167,198,293` + `makerworld_screen.dart:70-73,123-125` — `setState`/`ref` po await bez mounted
Niekonsekwentne z `_submit` w tym samym pliku (tam guard jest). Zburzenie route'a hosta
przy otwartym sheecie (redirect zmiany serwera) → „setState() called after dispose()".

**Fix:** `if (!mounted) return;` po każdym await.

### 5.11 [L][bug] `inventory_form.dart:118,137 vs 534` — walidator akceptuje ułamki, zapis parsuje int
Walidacja `double.tryParse`, zapis `int.tryParse` dla `labelWeight`/`coreWeight`:
wpisanie „1000.5" przechodzi walidację, ale pole leci jako null i matematyka
`weight_used` jest pomijana.

**Fix:** `double.tryParse(...)?.round()` przy zapisie albo walidacja int.

### 5.12 [L][bug] `project_detail_sections.dart:683-687` (+ `project.dart:461-470`) — edycja BOM nie umie WYCZYŚCIĆ pola
Pusty tekst → null → pole pominięte w PATCH (`'unit_price': ?unitPrice`) → serwer
zachowuje starą wartość. Usunięcie ceny przy edycji = cicho bez zmiany.

**Fix:** przy edycji jawny `null` dla wyczyszczonych pól (sentinel „clear" w `BomItemInput`).

### 5.13 [L][perf] `swatches_screen.dart:268-310` — nie-lazy `ListView(children:)` odbudowuje wszystkie kafelki na każdy znak szukajki
Setki kodów = O(N) konstrukcji widgetów na każde wciśnięcie klawisza.

**Fix:** `ListView.builder` / slivery.

### 5.14 [L][perf] `about_screen.dart:130-131` + `stats_sections.dart:128,195-209`
`FutureBuilder(future: PackageInfo.fromPlatform())` tworzy future na każdy rebuild
(wersja miga na „…"); heatmapa buduje `weeks*7` Containerów eagerly — bez limitu przy
„cały okres" wieloletnim.

**Fix:** future w polu/providerze; heatmapa z oknem (26/52 tyg.) albo wirtualizowana.

### 5.15 [L][perf] `inventory_form.dart:67` — listener na kontrolerze rgba robi `setState` całego 680-liniowego sheeta na każdy znak hexu
(plus to samo w `onChanged` labelWeight/measured).

**Fix:** `ValueListenableBuilder` tylko wokół podglądu swatcha.

### 5.16 [L][build] `android/app/build.gradle.kts:30-37` — release signing bez fallbacku przy braku `key.properties`
Build release na maszynie bez pliku kluczy pada z kryptycznym błędem null-property.

**Fix:** czytelny komunikat / warunkowe podpisywanie debug keyem.

**Czyste:** `spool_scanner_screen.dart` (guard `_handled`, noDuplicates, dispose OK);
providery inventory/projects/maintenance/setup (bez pętli invalidacji, refresh z
`copyWithPrevious`); wzorzec messenger/navigator-przed-await w `_run`/`_OverflowMenu`/
`_confirmPerform`; `stats_computed.dart` (agregacja memoizowana); **natywny Android
czysty** — manifest (FGS dataSync, POST_NOTIFICATIONS, CAMERA, exported jawne, receiver
widgetu z APPWIDGET_UPDATE, WorkManager auto-init usunięty), `BambuddyWidgetProvider`
tylko RemoteViews-safe API + downsample ≤512px (bez TransactionTooLargeException),
PendingIntenty rozróżnione data-URI, deep-link `bambuddy://widget?action=scan` przez
explicit intent + singleTop, proguard-rules kompletne (ML Kit, mobile_scanner,
flutter_local_notifications/Gson).

---

## Proponowana kolejność napraw

**Bugi o realnym wpływie na użytkownika:**
1. ✅ **1.1** single-flight re-loginu (ryzyko wylogowania usera w normalnym scenariuszu wygaśnięcia JWT). — memoizacja `Future<String?>` w `AuthService.silentReLogin`.
2. ✅ **2.1** try/catch w `onStart` FGS (cichy brak alertów = najgorszy tryb awarii funkcji nr 1 apki). — całe ciało w `_startMonitoring` + try/catch → `stopService()`; przy okazji naprawione **2.10** (null profil → `stopService()` zamiast gołego `return`).
3. ✅ **3.1 + 3.2** tolerancyjne parsery w `*.g.dart` (ciche znikanie rekordów z list / crash detalu projektu). — nowy `lib/core/models/json_utils.dart` (`parseJsonList`, `dateTimeFromJson`), spięty przez `@JsonKey(fromJson:)` w `project.dart`/`maintenance.dart`/`library_folder.dart`/`archive.dart`/`library_file.dart`/`queue_item.dart`/`trash_file.dart`, `.g.dart` przegenerowane build_runnerem.
4. ✅ **5.1** flaga `_disposed` w stats_providers (statystyki wiecznie ze starego cache po zmianie filtra). — reset `_disposed = false` na starcie `build()`.
5. ✅ **5.2 + 5.3 + 5.4** dropdowny z wartością spoza `items` (crashe formularzy inventory/projektów). — 5.2: zerowanie `_coreWeightCatalogId` gdy brak w katalogu; 5.3: syntetyczny `DropdownMenuItem` dla odfiltrowanego rodzica; 5.4: korekta `_amsUnit` w `build()` + `key: ValueKey(_printerId)` na `_NumberDropdown`.
6. ✅ **4.1** guard generacji w wyszukiwarce archiwum (stale wyniki). — `_searchGeneration` w `ArchiveNotifier.search()`.

_(`flutter analyze`: czysty; `flutter test`: 314/314 przechodzi — zweryfikowane po każdym z powyższych.)_

**Wydajność / bateria:**
7. ✅ **1.3 + 2.3 + 2.2** wspólny fix publikacji widgetu (change-key + serializacja) — bateria i migotanie. — `WidgetPublishKey` (id/status/progress/ETA-min/warstwy/cover) w `HomeWidgetPublisher.publish`, skip gdy niezmienione, drop-if-in-flight; `WidgetCoverCache.fetch` zapisuje przez tmp-plik + atomowy `rename`.
8. ✅ **4.3 + 5.7** `cacheWidth` we wspólnych widgetach miniatur (RAM/jank we wszystkich listach). — `print_thumbnail.dart`, `library_thumbnail.dart`, `printer_card_panels.dart` (`_CoverThumbnail`), `makerworld_thumbnail.dart`, `project_cover_image.dart`.
9. ✅ **4.4** gate timera kolejki widocznością zakładki — `TickerMode.valuesOf(context).enabled` w `didChangeDependencies` (go_router owija offstage gałęzie `TickerMode(enabled: false)`). ✅ **1.7** value-equality statusów — `==`/`hashCode` na `PrinterStatus`/`AmsUnit`/`AmsTray`/`HmsError` (`package:collection` dla list/map), `ingestPoll` pomija zapis gdy scalony status niezmieniony.

_(`flutter analyze`: czysty; `flutter test`: 314/314 przechodzi.)_

**Higiena `context`/`ref` po await (jedna klasa, jeden przegląd):**
10. ✅ **4.2** (menedżer plików — systemowo), **5.5**, **5.6**, **5.10** + niedispose'owane
    kontrolery dialogów **4.6**/**5.8**. — `if (!mounted) return;` po każdym await w
    file_manager_screen.dart (10 metod mutujących), cloud_account_screen.dart (2 catch),
    swatches_screen.dart (l10n capture + guardy), slice_sheet.dart (4 miejsca) i
    makerworld_screen.dart (2 miejsca); `_promptName`/„wykonaj konserwację" przerobione
    na małe StatefulWidgety (`_PromptNameDialog`, `_PerformConfirmDialog`) analogicznie
    do `_NotesEditDialog`.

_(`flutter analyze`: czysty; `flutter test`: 314/314 przechodzi.)_

**Hartowanie połączeń (tanie):**
11. ✅ **1.2** (try/catch wokół heartbeat send); ✅ **1.4 + 4.9** (klasyfikacja auth-error
    zakotwiczona na `WebSocketException.httpStatusCode` / `HttpException` z flutter_mjpeg,
    zamiast substringu — z testem regresyjnym na kolizję portu); ✅ **1.5** (tylko 404 →
    fallback header-only, reszta błędów mintu → normalny backoff/retry, z testem);
    ✅ **1.6** (seed `wsConnectionStateProvider` bieżącym stanem klienta);
    ✅ **4.5** (ujednolicone na `unit.id ?? index` w queue_mapping_sheet.dart i
    printer_status.dart `activeTray` — **nie zweryfikowane na żywo na X2D**, brak sprzętu
    w tej sesji); ✅ **2.5** (`resetCover` callback → `WidgetCoverCache.reset()` gdy
    drukarka offline / druk się kończy); **2.10** już zrobione przy 2.1.

_(`flutter analyze`: czysty; `flutter test`: 316/316 przechodzi — 2 nowe testy regresyjne
w `ws_client_test.dart` dla 1.4 i 1.5.)_

**Refactory zbiorcze (osobne PR-y):**
12. **3.5/3.6** wspólny `guard()` + `json_utils` (centralizuje też 3.1–3.3),
    **4.11** wspólny picker drukarki/format bajtów, **2.4** martwy kanał `ongoing_print`,
    **1.9** wspólny `CachedTokenService`, **2.6** jeden klient API w izolacie tła,
    **3.7** martwe endpointy, **1.8** dispose routera, **5.16** fallback podpisywania release.
