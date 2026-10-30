# Inventory — slot numbering, the two backends, assigning and scanning

The Filaments tab (`/inventory`, the fifth bottom-bar branch) is the spool shelf:
create, edit and filter spools, assign one to an AMS slot, scan its QR code. The
feature set follows the web's inventory page; this file holds the parts the
contract does not show. The gate for each newer spool field is in
[server-gates.md](server-gates.md), the shape of the generic server traps in
[server-contract-traps.md](server-contract-traps.md).

## Slot numbering lives in one file

`lib/core/ams/slot_addressing.dart` owns every conversion between the three
numberings a slot answers to, and the holder table sits in its header. Call it;
**never write `* 4 +`, `254 +`, `1 - trayId` or a bare 254/255 for a slot.** Every
hand-written conversion was an inversion somebody had to get right from memory, and
the one that was skipped was a bug.

- Routes with ids in the path (`/slots/{ams}/{tray}/configure`, the RFID re-read,
  the inventory assignment) take **local** ids: a unit and a slot within it.
- The firmware, `tray_now`, every `ams_mapping` and `POST /ams/load` use one
  **global** number. An external holder gets a third numbering on top: Ext-L is
  local 255/0, global 254, extruder 1 (left); Ext-R is 255/1, 255, extruder 0.
  The extruder column is inverted on purpose and was verified on a live dual-nozzle
  printer.
- An **AMS-HT** is numbered from 128, one tray each, so its global id is its unit
  id, not `unit * 4 + slot` (that put it at 512). It mirrors
  `print_scheduler.py::_build_loaded_filaments`; `ams_mapping` and `tray_now` are
  wrong for an HT owner without it.

Two behaviours came from unifying the callers, and each looks like a bug to
someone who has not met the history. Do not "restore" them:

- `amsLoadTrayId` takes **local** ids like every other slot route (`amsId: 255,
  trayId: 0` becomes 254). It answers null where the server's `ams_load` has no
  encoding (AMS-HT), and the caller hides the action.
- `PrinterStatus.activeTray` skips a tray that reports no id. Reading it as `-1`
  collided with the neighbouring unit's slot 3.

The inventory routes use a fourth shape: **both** external spools carry
`ams_id = 255` and only `tray_id` tells them apart (0 = left, 1 = right, checked
against live assignments of a dual-nozzle machine). This is not the MQTT `vt_tray`
254/255 of the dashboard, which is why `SpoolAssignment.extruder` goes through
`extruderForExternalSide`. Keying the extruder on `ams_id` put both spools on "left".
The UI shows the extruder, never "AMS255".

## Two backends behind one interface

`SpoolInventorySource` has two implementations: `NativeInventorySource`
(`/inventory/*`) and `SpoolmanInventorySource` (`/spoolman/inventory/*`, a drop-in
for the same screens). Which one runs is **the server's decision**, asked once per
server by `detectInventoryBackend` (`inventoryBackendProvider`); there is no app
setting. Spoolman wins when `GET /spoolman/status` says `enabled` with a url — the
web's rule. `connected` is ignored on purpose: an unreachable Spoolman is still the
inventory the user keeps, and falling back would show an empty or stale built-in
table and send writes to it. A 403 or 404 from the status route settles on native;
a body of another shape, or a transport error, is thrown so the caller asks again
rather than settle on a backend it never heard. A server older than 0.2.4 has
no `/spoolman/inventory/*` (the slot ledger answers 404), and keeps the built-in
inventory even with Spoolman on.

`Spool`, `SpoolAssignment` and `SpoolUsageEntry` are hand-written, defensive
models with a factory per backend (`fromNative`, `fromSpoolman`). There is no
WebSocket feed for the shelf: it is fetched on entry and by pull-to-refresh, and
filtered on the client.

### How Spoolman mode binds a spool

From the bambuddy and Spoolman source:

- A spool **without RFID** is bound by `POST /spoolman/inventory/slot-assignments`
  (what the web's Assign sends, `inventory:update`). The tag route
  `POST /spoolman/spools/{id}/link` needs `filaments:update`, and the app has no
  Link action.
- An **RFID spool** is created or linked by the AMS sync (`sync_ams_tray`), keyed on
  the Spoolman spool's `extra.tag`, and the same sync upserts the slot row. Usage is
  charged to the tag first and to the slot row as the fallback.
- The web reads the slot row first and, on any RFID tray, disables Assign and hides
  Unassign (`isBambuLabSpool`).

**One deliberate deviation.** For an RFID tag that no spool carries (auto-add off)
the app keeps the picker enabled, where the web disables Assign and offers Link.
Usage then falls back to the slot row, so assigning works. `_SlotRef.lockedByTag`
(`printer_card_details.dart`) is the single line that would give strict parity;
ask before changing it.

A test trap from the same area: an absence assertion (`findsNothing`) in a lazily
built slot sheet passes vacuously until the list is scrolled — `scrollSheetDown`
first. It was caught only because a mutation survived.

## Contract traps in the spool form

- **`SpoolCreate.rgba` is `^[0-9A-Fa-f]{8}$`**: eight hex digits, no `#`. The colour
  picker and `/inventory/colors` give `#RRGGBB`, which is a 422. `normalizeRgba`
  strips the `#` and appends `FF` to six digits; every write goes through it.
- Other limits (`schemas/spool.py`): `low_stock_threshold_pct` 1..99 (clamp it),
  `material` 1..50, `category` at most 50, `storage_location` at most 255,
  `material_number` at most 64. A create body may be a subset: the server defaults
  the rest.
- Print names in a spool's usage history are URL-encoded (`%20`) **and stay so** —
  that is the file's name on the server. Do not decode them.

### Blanking a field

`SpoolDraft` null means "leave it", so a form that must remove a value calls
`draft.clearing(before)` (`before` is the spool being edited, or the one a sheet
just created for a retry). The draft then carries `clears`, and each backend has its
own dialect:

| Backend | How a blanked field reaches the server |
|---|---|
| Built-in | an explicit `null` clears every nullable field except `last_scale_weight`; `""` leaves empty strings or is a 422 on numeric fields |
| Spoolman | `subtype`, `note` and the slicer preset clear on `""`; `storage_location`, `color_name` and `last_dried_at` on `null`; **brand, price and every other field are silently kept** |

`toSpoolmanJson` drops a clear Spoolman cannot do rather than send it, because it
is silently ignored. The form says so: in Spoolman mode a brand or price field the
user emptied shows `inventorySpoolmanCannotClear` under it (`_spoolmanKeeps`).
`clearing` takes `except` for fields the user could not see: an empty draft field
there means "never offered", not "deleted". The contract test is
`test/contract/spool_clear_contract_test.dart` (needs
`BAMBUDDY_CONTRACT_SPOOLMAN_URL`).

## Profile defaults in the spool form

A default holds the slicer preset, the presets per printer model and the K profiles of
one product (brand, material, variant, optionally colour); the server lays it on every
spool it creates, in both inventory modes, whether or not the app knows (server #1326).
The app only reads, saves and manages them. The gate is in [server-gates.md](server-gates.md).

- **A save replaces everything, and the form has no K profile editor.** So the write
  reads the list first and sends back the K profiles of the row with the *same product
  key* — trimmed and case-folded, the server's `match_key`, colour included — never the
  K profiles `resolve` returns, which are the all-colours row with the colour's laid
  over it. Sending `[]` would delete the ones set on the web.
- **Prefill mirrors the web's spool form** (`SpoolFormModal.tsx`): only a fresh create
  asks `resolve`, 300 ms after the typing stops; the default fills only the models and
  the preset the user left empty, gives way to the next product's default when the
  product changes, and never replaces a pick. It does not mark the model rows dirty —
  the server lays the same default on the spool itself, so an untouched section still
  writes nothing.
- **Scope is a select under the switch.** "Only {color}" exists only while a colour is
  typed; a colour cleared after picking it saves for every colour.
- **A failed default save warns and closes the sheet**, like the web. The spool is
  already saved, and keeping the sheet open would make a retry of a restock create the
  spools again.
- **Known deviation:** from an edit or a copy the web saves the spool's own K profiles
  into the default; the app keeps the default's, since it cannot show the spool's.
- **The list is in the server settings hub**, with the other settings that change the
  server for everybody, and its entry shows only once the gate says yes
  (`ProfileDefaultsScreen`). Apply goes to the twin route of the live inventory — the one
  place the two modes differ — and refreshes the shelf when it changed anything; Delete
  asks first. A 403 on Delete can also mean the default holds K profiles of printers the
  session may not see (`delete_profile_default`), and the server's own words are what the
  snack shows. Neither write settles the gate.

## Assigning a spool to a slot: two flows, both stay

1. **From the AMS chip on a printer card.** The slot (printer, unit, tray) is known,
   the user picks only the spool. The sheet shows the slot's label, the spool
   currently assigned with an unassign button, and the shelf (spools not assigned
   elsewhere first, then least remaining weight first). The chip shows the exact remaining grams
   from the shelf, not the printer's percentage.
2. **From the Filaments tab.** The spool is known, the user picks the slot: a printer
   dropdown, then AMS or external, then unit and slot, or the left/right extruder.

Both exist because each is the quicker path from where the user stands. **A spool
sits in exactly one slot**: `InventoryNotifier.assignSpool(draft, {from})` unassigns
the old slot first (Spoolman takes a spool off by its id, so clearing afterwards
would take the new assignment too) and puts the spool back if the new assignment
fails.

## QR scanner

`QrScannerScreen<T>` (`lib/features/common/qr_scanner_screen.dart`) is generic over
the parser `extract: T? Function(String)`; `SpoolScannerScreen` is a thin wrapper.
Entries: the Filaments tab, the slot sheet, and the URL and key fields of the setup
screen.

- A spool's QR is the web URL `https://<host>/inventory?spool=24`. The parser
  (`parseScannedSpoolId`) is lenient on purpose: a bare number, `spool_id`/`id`, or
  the last numeric path segment.
- The server-setup QR is `bambuddy://config?v=1&url=<enc>&key=<enc>` — one code for
  the address **and** the key (`reference/bambuddy/frontend/src/utils/apiKeyQr.ts`,
  parsed in `features/setup/api_key_qr.dart`). A scan fills both fields and re-probes.
- The controller is `autoStart: false` with an explicit `start()` in `initState` and
  **no hand-written lifecycle observer**: a manual start/stop races the permission
  dialog (which sends the app to sleep) and leaves a black preview.
- **A black screen in release only is R8**, not the camera. R8 strips ML Kit classes
  that `mobile_scanner` loads by reflection, and `start()` then throws an NPE inside
  the plugin. The keep rules are in `android/app/proguard-rules.pro` (`com.google.mlkit.**`,
  `mlkit_vision_barcode`, `dev.steenbakker.mobile_scanner.**`; the same file keeps
  `com.dexterous.**` for notification actions). The log shows obfuscated names
  (`q5.c`, `a6.n`) and an `r8-map-id`. **Any new dependency that loads classes
  reflectively needs its own rule**, and per [AGENTS.md](../AGENTS.md) broadening
  keep rules is a security-stop decision for the maintainer.
