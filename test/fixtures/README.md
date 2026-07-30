# Fixture'y API

> **TODO: zastąpić przechwyconymi JSON-ami z żywego serwera.**
>
> Te pliki są autorskie — odtworzone ze schematów Pydantic w kodzie
> źródłowym bambuddy v0.2.4.6 (`backend/app/schemas/printer.py`,
> `backend/app/api/routes/{auth,printers}.py`), bo sesja, w której
> powstały, nie miała dostępu do żywego serwera. Plan (§5) wymaga
> fixture'ów z PRAWDZIWEGO serwera — to jest tripwire na ruchliwość API.
>
> Jak podmienić:
> ```sh
> curl -s http://SERWER:8000/api/v1/printers | jq . > printers_list.json
> curl -s http://SERWER:8000/api/v1/printers/1/status | jq . > printer_status_printing.json
> curl -s http://SERWER:8000/api/v1/auth/status | jq . > auth_status_enabled.json
> ```

Pola `_unknown_*` w plikach są celowe — testują tolerancję parserów na
nieznane klucze (nowe pola serwera nie mogą wywalać aplikacji).

## Przechwycone z żywego serwera

`queue_list.json` — odpowiedź `GET /api/v1/queue/` (2026-07-29), 11 rekordów
wybranych z 163 tak, by pokryć kształty, których nie wymyśliliśmy sami:
pozycja z pliku biblioteki, harmonogram, usunięte archiwum, brak mapowania AMS,
nazwa nie-ASCII, szpula zewnętrzna (254/255), błąd z komunikatem drukarki,
wielokolorowy `filament_color`, pozycja > 1. **Rekordy są niezmienione** — to
jest sens fixture'a: jeśli serwer zmieni typ pola, testy na nim padną.

`queue_list_tristate.json` — **nie jest przechwycone.** Ta sama odpowiedź
`GET /api/v1/queue/`, ale w kształcie bambuddy 1.2.5+, gdzie `bed_levelling`,
`flow_cali` i `nozzle_offset_cali` to `"off"` / `"on"` / `"auto"` zamiast
booleanów. Struktura wzięta z `queue_list.json` (nasz serwer jest starszy i tej
postaci nie wyśle), a wartości trzech pól kalibracji — z rekordów, które podesłał
tester z Discorda na serwerze 1.x; to jego zgłoszenie opisuje
[`docs/plans/07-queue-cali-enum.md`](../../docs/plans/07-queue-cali-enum.md).
Trzymane osobno, żeby nie ruszać przechwyconego pliku: `queue_list.json` jest
dowodem na to, co serwer naprawdę wysyła, i ma zostać niezmieniony.

### `captured/` — **poza repo, odtwarzasz u siebie**

Zrzuty z żywego serwera przez
[`tool/capture_fixtures.sh`](../../tool/capture_fixtures.sh) — po jednym pliku na
endpoint, z którego apka rysuje ekran: drukarki i status, archiwum i statystyki,
szpule, gniazdka, konserwacja, projekty, biblioteka, kolejka. Listy przycięte do
8 rekordów. Sprawdza je [`test/data/captured_contract_test.dart`](../data/captured_contract_test.dart)
— przez repozytoria, nie przez modele, bo tolerancyjne parsowanie listy (to,
które po cichu wyrzuca zepsuty rekord) siedzi właśnie w repozytoriach.

**Ten katalog jest w `.gitignore`.** Był kiedyś śledzony i to był błąd:
`smart_plugs.json` niósł `ha_entity_id: "switch.szafa_biuro"`, a encje Home
Assistant nazywa ich właściciel — ten jeden string mówi, w którym pokoju stoi
drukarka. Poza sekretami zostają też nazwy projektów, wydruków i
`created_by_username`, czyli tożsamość właściciela serwera. Scrubber maskuje
sekrety, nie tożsamość, więc zrzuty zostają lokalnie.

Co robi [`tool/scrub_fixtures.py`](../../tool/scrub_fixtures.py) — mimo że pliki
nie idą do repo, bo zrzut i tak trafia do zgłoszeń i na zrzuty ekranu: adresy IP
na `192.0.2.x` (zakres dokumentacyjny z RFC 5737), seriale Bambu na atrapy o tej
samej długości (kształt zostaje parsowalny — dlatego atrapa, nie `[REDACTED]`),
a pola, których **nazwa** mówi „prywatne", na `[REDACTED]`. Ta ostatnia lista
jest trzymana w parytecie z `LogRedactor._secretKey`: fixture nie może być
trzymany do niższego standardu niż log.

Nazwy plików, projektów i drukarek **zostają** — bez nich rekord przestaje być
czytelny, a to one czynią z tych plików przechwycenie, a nie kolejny wymyślony
kształt. Właśnie dlatego zrzut nie jedzie do repo.

Bez zrzutu `captured_contract_test` i jeden test w `http_probe_test` **pomijają
się z komunikatem** nazywającym komendę — nie przechodzą po cichu na pustym
zbiorze. Zielony przebieg, który nic nie sprawdził, jest gorszy niż skip.

Jak odświeżyć:

```sh
printf '%s' 'bb_twójklucz' > ~/.bambuddy-fixture-key && chmod 600 ~/.bambuddy-fixture-key
tool/capture_fixtures.sh https://twój.serwer
```

**Rób to z podłączoną drukarką.** Przy offline serwer oddaje status bez `ams`,
ze `state:"unknown"`, i zrzut jest chudszy od tego, który nadpisuje — sprawdzone
na własnej skórze. Skrypt pomija plik przy nie-200 (`continue`), więc pojedyncze
niepowodzenie zostawia **stary** plik bez śladu w wyniku; po przebiegu warto
zerknąć na `git status`, czy zmieniło się to, co miało.

## `printer_status_hms.json` — jedyny przechwycony plik W repo

Leży **poza** `captured/` i jest śledzony, bo jest **nieodtwarzalny**. Trzyma trzy
błędy HMS, jakie ta drukarka wtedy raportowała: jeden kod poza katalogiem i dwa
dzielące skrócony kod przy różnym znaczeniu. Na tym stoi
[`hms_catalog_assets_test.dart`](../core/notifications/hms_catalog_assets_test.dart),
czyli reguła „nie pokazuj kodu, którego nie umiemy nazwać" — dziewięć testów.

Błędy HMS są **ulotne**: należą do zadania druku i ta drukarka przestała je
zgłaszać w chwili ponownego połączenia. Późniejszy zrzut ma jeden błąd zamiast
trzech i cały scenariusz paruje — sprawdzone przez odświeżenie, które wywaliło
te dziewięć testów. Skoro nikt nie odtworzy tego payloadu, wyrzucenie go do
gitignore skasowałoby tę ochronę dla wszystkich poza jedną maszyną.

Dlatego: zamrożony, ze starszym zestawem pól (sprzed 1.2.5.1) — nic w tym teście
nie czyta pól dodanych w 1.2.5.1 — i przepuszczony przez scrubber jak każdy inny
zrzut. **Nie odświeżaj go.** Aktualnego kształtu pilnuje `captured/printer_status.json`.
