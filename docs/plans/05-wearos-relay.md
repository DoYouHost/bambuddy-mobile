# Plan: przekaźnik komend/statusu Wear OS przez telefon (Data Layer)

Cel: zegarek przestaje trzymać własne połączenie sieciowe do serwera bambuddy. Zamiast tego wymienia status i komendy z **telefonem** przez Wear Data Layer (który przy telefonie blisko jedzie po moście Bluetooth/BLE — tanio bateryjnie), a telefon jest przekaźnikiem do serwera. Ścieżka REST na zegarku zostaje jako **fallback** (hybryda).

Kontekst wyjściowy (stan po v0.8.0, gałąź scalona do `master`): działa **standalone** apka Wear (osobny entry point `lib/wear/`, reużywa `core/`+`data/`, polling REST co 5 s) oraz **handoff konfiguracji** telefon→zegarek przez `updateApplicationContext` (`lib/core/watch/watch_config_sync.dart`). Ten plan **odwraca** model transportu danych: z „zegarek sam po WiFi" na „zegarek pyta telefon".

## Podsumowanie decyzji

| Decyzja | Wybór |
|---|---|
| Transport zegarek↔telefon | **Wear Data Layer `MessageClient`** (NIE gołe BLE/GATT) — most sam używa BT/BLE przy telefonie blisko |
| Kanał komend/statusu | `sendMessage` (RPC żądanie→odpowiedź), ścieżki wg `path` |
| Kanał konfiguracji | bez zmian — `updateApplicationContext` (latched), już zrobione |
| Odbiornik na telefonie | **natywny `WearableListenerService` (Kotlin)** budzony na żądanie + most do isolate/repo |
| Źródło statusu na telefonie | **żywy stan WS z FGS** gdy dostępny; inaczej świeży REST |
| Model na zegarku | **hybryda**: relay-first, fallback na REST wprost gdy telefon nieosiągalny |
| Poświadczenia na zegarku | **żadne** w trybie relay (trzyma je telefon); przy fallbacku REST — jak dziś |
| Standalone | świadomie **poświęcony** w trybie relay (zegarek bez telefonu = tryb fallback lub brak danych) |

## Dlaczego nie „gołe BLE"

Na Wear OS nie implementuje się własnego GATT między zegarkiem a telefonem. Data Layer już daje parowanie, reconnect i transport, i **oportunistycznie korzysta z Bluetooth/BLE, gdy telefon jest blisko** (a przełącza na WiFi/chmurę gdy daleko). Pluginy BLE na Wear są kruche. Wniosek: „wymiana po BLE" = `MessageClient` do telefonu. Mamy już `watch_connectivity` z `sendMessage`/`messageStream` — prymityw jest na miejscu, to rozszerzenie, nie przepiska.

## Architektura

```
Zegarek (lib/wear)                        Telefon (bambuddy)
  UI akcja / otwarcie ekranu                WearableListenerService (Kotlin, budzony)
      |  MessageClient (BT/BLE)                 |  -> odczyt żywego stanu WS (FGS) LUB REST
      |  {path:/cmd, action, printerId}  --->   |  -> PrinterCommandsRepository / status
      |  <--- {path:/reply, ok, status/err}     |
      v                                         v
  render (bez sieci na zegarku)             serwer bambuddy (REST/WS)
```

### Protokół wiadomości (szkic)

Ścieżki `MessageClient`:

- `/bambuddy/req` — żądanie z zegarka. Body (JSON w bajtach):
  - `{ "id": <uuid>, "action": "getFleet" }` — lista drukarek + status.
  - `{ "id", "action": "getStatus", "printerId": N }`
  - `{ "id", "action": "pause"|"resume"|"stop"|"clearPlate", "printerId": N }`
  - `{ "id", "action": "startNext", "printerId": N }`
- `/bambuddy/res` — odpowiedź z telefonu. Body:
  - `{ "id": <ten sam>, "ok": true, "data": {...} }` lub `{ "ok": false, "error": "<krótko>" }`.

`id` koreluje żądanie z odpowiedzią (jeden most, wiele w locie). Timeout po stronie zegarka (np. 4 s) → uznaj telefon za nieosiągalny → fallback REST.

Kształt `data` dla statusu = ten sam JSON co REST (`PrinterStatus.fromJson` reużyty na zegarku bez zmian). Dla fleet — lista `{printer, status}`.

## Zmiany po stronie zegarka (`lib/wear`)

1. **`WearTransport`** (nowy) — abstrakcja: `getFleet()`, `getStatus(id)`, `pause/resume/stop/clearPlate/startNext`. Dwie implementacje:
   - `RelayTransport` — wysyła `MessageClient`, czeka na odpowiedź po `id`, mapuje `data` na modele (`PrinterStatus`, `PrinterWithStatus`).
   - `RestTransport` — dzisiejsze repozytoria (`PrintersRepository`, `PrinterCommandsRepository`, `QueueRepository`).
2. **Wybór transportu (hybryda):** przy każdym żądaniu sprawdź `isReachable`/wynik pierwszego `getFleet` z krótkim timeoutem; osiągalny telefon → relay, inaczej → REST. Zapamiętaj ostatni tryb, ze świeżym pingiem.
3. **`wearFleetProvider`** przełączony z bezpośredniego `printersRepositoryProvider` na `WearTransport`. Reszta UI (ekrany, `wear_actions`) bez zmian — działają na tej abstrakcji.
4. Status „na otwarcie ekranu" zamiast pollingu co 5 s w trybie relay (bateria): odśwież przy wejściu + pull-to-refresh/rotacja; opcjonalnie lekki poll tylko gdy druk aktywny.

## Zmiany po stronie telefonu

1. **`WearableListenerService` (Kotlin)** w `android/app/src/main/.../BambuddyWearListener.kt`, zadeklarowany w manifeście z filtrem `com.google.android.gms.wearable.MESSAGE_RECEIVED` i ścieżką `/bambuddy/req`. Android **budzi go na żądanie** (działa nawet gdy apka zamknięta).
2. **Odpowiadanie:** service musi wykonać REST/odczyt i odesłać `MessageClient`. Opcje realizacji logiki Dart:
   - Najprościej na start: **wymóg, że apka/FGS żyje** — listener przekazuje do isolate przez port; jeśli nic nie żyje, odpowiada „phone-unavailable" i zegarek robi fallback.
   - Docelowo: listener **startuje krótki Flutter engine / background isolate** (jak print monitor), robi REST i odsyła. Reużyj wzorca z [[print-monitor-task-handler]] (FGS isolate) — ten sam mechanizm rebuildu profilu/creds/klienta.
3. **Źródło statusu:** gdy FGS z żywym `WsClient` działa (druk w toku / monitoring włączony) → odpowiadaj **z pamięci, bez dobijania do serwera** (natychmiast, zero ruchu). Inaczej → świeży REST przez istniejące repozytoria.
4. **Komendy** → istniejące `PrinterCommandsRepository` / `QueueRepository`. Zero nowej logiki serwerowej.

## Fallback i przypadki brzegowe

- Telefon poza zasięgiem / BT off → zegarek po timeout przechodzi na `RestTransport` (wymaga skonfigurowanego profilu na zegarku — handoff konfiguracji już to zapewnia). Jeśli zegarek nie ma WiFi ani profilu → komunikat „Połącz telefon".
- Wiele drukarek → protokół już to obsługuje (`getFleet`/`printerId`).
- Bezpieczeństwo: komendy sterujące lecą szyfrowanym mostem Google między sparowanymi urządzeniami; serwer i tak autoryzuje po stronie telefonu (istniejący klucz/`can_control_printer`).
- Duplikaty/utrata wiadomości: `MessageClient` nie gwarantuje dostarczenia jak TCP — stąd korelacja po `id` + timeout + retry raz.

## Kroki (kolejność na jutro)

1. **M-R1 — kontrakt:** kod współdzielony `lib/core/watch/wear_rpc.dart` (enum akcji, encode/decode żądania/odpowiedzi, wersjonowanie `v`). Test jednostkowy round-trip (jak `watch_config_codec_test`).
2. **M-R2 — zegarek relay:** `WearTransport` + `RelayTransport` (na `sendMessage`/`messageStream`), przełączenie `wearFleetProvider`, hybryda z timeoutem. Fallback `RestTransport`.
3. **M-R3 — telefon listener:** `WearableListenerService` + manifest; wariant „apka żywa" najpierw (przez port do isolate/UI), odpowiedź z żywego stanu WS lub REST.
4. **M-R4 — telefon on-demand isolate:** budzenie logiki Dart bez żywej apki (reużyj wzorca FGS print-monitor).
5. **M-R5 — weryfikacja na żywo:** para telefon (v≥0.8.x z listenerem) + Galaxy Watch 5 (SM-R910, armeabi-v7a, sparowany przez wireless ADB). Sprawdź: status na otwarcie bez WiFi na zegarku, komendy, fallback po wyłączeniu BT.

## Otwarte pytania

- Czy akceptujemy utratę standalone w trybie relay, czy hybryda ma być domyślna trwale? (na teraz: hybryda).
- Poll „na otwarcie" vs lekki live przy druku — ile odświeżania w trybie relay, by nie budzić telefonu za często.
- Czy warto dorobić `DataClient` (latched) dla „ostatni znany status" pokazywanego natychmiast po otwarciu, zanim przyjdzie świeża odpowiedź.

Powiązane: `lib/core/watch/watch_config_sync.dart`, `lib/wear/wear_providers.dart`, wzorzec FGS isolate w `lib/core/notifications/print_monitor_task_handler.dart`. Pamięć: [[wearos-app]].
