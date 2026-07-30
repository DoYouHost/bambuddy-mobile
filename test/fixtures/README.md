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

### `captured/`

Zrzuty z tego samego serwera (2026-07-29), zrobione przez
[`tool/capture_fixtures.sh`](../../tool/capture_fixtures.sh) — po jednym pliku na
endpoint, z którego apka rysuje ekran: drukarki i status, archiwum i statystyki,
szpule, gniazdka, konserwacja, projekty, biblioteka, kolejka. Listy przycięte do
8 rekordów. Sprawdza je [`test/data/captured_contract_test.dart`](../data/captured_contract_test.dart)
— przez repozytoria, nie przez modele, bo tolerancyjne parsowanie listy (to,
które po cichu wyrzuca zepsuty rekord) siedzi właśnie w repozytoriach.

Czego w nich nie ma: adresy IP zamienione na `192.0.2.x` (zakres
dokumentacyjny z RFC 5737), seriale Bambu na atrapy o tej samej długości —
robi to [`tool/scrub_fixtures.py`](../../tool/scrub_fixtures.py), którym można
też przelecieć zrzut zrobiony ręcznie. Jedno i drugie jest maskowane w logu
diagnostycznym, więc w publicznym repo nie może być inaczej.

Nazwy plików, projektów i drukarek **zostają** — bez nich rekord przestaje być
czytelny, a to one czynią z tych plików przechwycenie, a nie kolejny wymyślony
kształt. Jeśli kiedyś zrzut zrobi ktoś inny, to jego decyzja, nie automat.

Jak odświeżyć:

```sh
printf '%s' 'bb_twójklucz' > ~/.bambuddy-fixture-key && chmod 600 ~/.bambuddy-fixture-key
tool/capture_fixtures.sh https://twój.serwer
```
