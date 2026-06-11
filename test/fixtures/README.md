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
