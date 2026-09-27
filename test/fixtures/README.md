# API fixtures

> **TODO: replace with JSON captured from a live server.**
>
> These files are hand-written — reconstructed from the Pydantic schemas in the
> bambuddy v0.2.4.6 source (`backend/app/schemas/printer.py`,
> `backend/app/api/routes/{auth,printers}.py`), because the session that
> created them had no live server to talk to. The plan (§5) asks for fixtures
> from a REAL server — they are the tripwire for a moving API.
>
> How to replace them:
> ```sh
> curl -s http://SERVER:8000/api/v1/printers | jq . > printers_list.json
> curl -s http://SERVER:8000/api/v1/printers/1/status | jq . > printer_status_printing.json
> curl -s http://SERVER:8000/api/v1/auth/status | jq . > auth_status_enabled.json
> ```

The `_unknown_*` fields in these files are deliberate — they test that the
parsers tolerate unknown keys (a new server field must not crash the app).

## Captured from a live server

`queue_list.json` — a `GET /api/v1/queue/` response (2026-07-29), 11 records
picked out of 163 to cover shapes we would not have invented ourselves: an item
from a library file, a schedule, a deleted archive, no AMS mapping, a non-ASCII
name, an external spool (254/255), an error carrying the printer's message, a
multi-colour `filament_color`, a position > 1. **The records are unmodified** —
that is the point of the fixture: if the server changes a field's type, the
tests on it fail.

`queue_list_tristate.json` — **not captured.** The same `GET /api/v1/queue/`
response, but in the bambuddy 1.2.5+ shape, where `bed_levelling`, `flow_cali`
and `nozzle_offset_cali` are `"off"` / `"on"` / `"auto"` instead of booleans.
The structure is taken from `queue_list.json` (our server is older and will not
send this form), and the values of the three calibration fields from records a
tester on Discord sent from a 1.x server.
Kept separate so the captured file stays untouched: `queue_list.json` is the
evidence of what the server really sends, and it has to stay as it is.

### `captured/` — **outside the repo, recreated locally**

Snapshots of a live server taken by
[`tool/capture_fixtures.sh`](../../tool/capture_fixtures.sh) — one file per
endpoint the app draws a screen from: printers and status, archive and stats,
spools, smart plugs, maintenance, projects, library, queue. Lists are trimmed to
8 records. They are checked by [`test/data/captured_contract_test.dart`](../data/captured_contract_test.dart)
— through the repositories, not the models, because the tolerant list parsing
(the part that quietly drops a broken record) lives in the repositories.

**This directory is in `.gitignore`.** It used to be tracked, and that was a
mistake: `smart_plugs.json` carried `ha_entity_id: "switch.szafa_biuro"`, and
Home Assistant entities are named by their owner — that one string says which
room the printer stands in. Beyond secrets there are also project and print
names and `created_by_username`, i.e. the identity of the server's owner. The
scrubber masks secrets, not identity, so snapshots stay local.

What [`tool/scrub_fixtures.py`](../../tool/scrub_fixtures.py) does — even though
the files do not go into the repo, because a snapshot still ends up in bug
reports and screenshots: IP addresses become `192.0.2.x` (the RFC 5737
documentation range), Bambu serials become dummies of the same length (the
shape stays parseable — hence a dummy, not `[REDACTED]`), and fields whose
**name** says "private" become `[REDACTED]`. That last list is kept in parity
with the log redactor (`LogRedactor` in the `app_report_client` package, plus
`_secretKey` in `lib/core/diagnostics/report_config.dart`): a fixture must not
be held to a lower standard than the log.

File, project and printer names **stay** — without them a record stops being
readable, and they are what makes these files a capture rather than one more
invented shape. That is exactly why the snapshot does not go into the repo.

Without a snapshot, `captured_contract_test` and one test in `http_probe_test`
**skip with a message** naming the command — they do not pass silently on an
empty set. A green run that checked nothing is worse than a skip.

How to refresh:

```sh
printf '%s' 'bb_yourkey' > ~/.bambuddy-fixture-key && chmod 600 ~/.bambuddy-fixture-key
tool/capture_fixtures.sh https://your.server
```

**Do it with a printer connected.** When it is offline the server returns a
status without `ams`, with `state:"unknown"`, and the snapshot is thinner than
the one it overwrites — learned the hard way. The script skips a file on a
non-200 (`continue`), so a single failure leaves the **old** file with no trace
in the output; after a run, check `git status` to see that what should have
changed did.

## `printer_status_hms.json` — the one captured file IN the repo

It lives **outside** `captured/` and is tracked, because it is
**irreproducible**. It holds the three HMS errors that printer was reporting at
the time: one code outside the catalog and two sharing a shortened code with
different meanings. The rule "do not show a code we cannot name" in
[`hms_catalog_assets_test.dart`](../core/notifications/hms_catalog_assets_test.dart)
stands on it.

HMS errors are **transient**: they belong to a print job, and that printer
stopped reporting them the moment it reconnected. A later snapshot has one error
instead of three and the whole scenario evaporates — confirmed by a refresh that
broke those tests. Since nobody can reproduce this payload, moving it to
gitignore would remove that protection for everyone but one machine.

Hence: frozen, with the older field set (from before 1.2.5.1) — nothing in that
test reads fields added in 1.2.5.1 — and run through the scrubber like any other
snapshot. **Do not refresh it.** `captured/printer_status.json` keeps watch over
the current shape.
