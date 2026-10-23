# Single-printer controller — design decisions (issue #54)

What the controller is, what it shows and the rules it keeps. The research it
rests on, including the maintainer's first decisions, is
[single-printer-controller-research.md](single-printer-controller-research.md);
this file is what was decided while designing the screens, on 2026-10-16.
Wall mode ([tv-flavor.md](tv-flavor.md) §13) is the sibling this borrows its
mechanics from.

## 1. Rules that hold everywhere

1. **One printer.** The controller is opened for one printer and everything on
   it is scoped to that printer: the fault count, the fault view, the alert,
   the screen-saver wake and any other event or notification. Another printer's
   fault never wakes the screen or opens a dialog. Filter by `printerId` in the
   provider, not in the widget (`controllerPrinterProvider` and
   `controllerErrorsProvider`, both families keyed by printer id), and test that a
   fault on printer B leaves printer A's controller alone
   (`controller_alert_test.dart`).
2. **Landscape only**, about 780–890 × 360–410 dp; height is the constraint, so
   every tab fits without scrolling. Entered from a "Controller" item in the
   dashboard's menu, through a printer picker, pushed over the dashboard (never
   `go`, [tv-flavor.md](tv-flavor.md) §13.2).
3. **Risky actions confirm** through `confirmDialog` (stop, and anything that
   cannot be undone). No lock, no PIN.
4. **A control that cannot be used says why**: a lock on the control, and a
   visible line where the reason is not obvious. Nothing is simply missing.
5. **No product name** of the device this was modelled on appears in the app.
6. Words are the printing words: *Extrude* and *Retract*, never push and pull.

## 2. Screens

A top bar (exit, printer name and model with a switcher, the tabs, a fault chip
that opens the fault view, the printer's state) over one tab at a time.

| Tab | Content |
|---|---|
| Overview | camera or file preview, job progress, pause/resume and stop, skip objects, temperature readings, speed profile, chamber light, smart plug |
| Heat | nozzle(s), bed and chamber targets with −/+ and a typed value, the three fans |
| Move | X/Y pad, Z, extrude and retract, step and length, home. Locked while a print is running |
| Filament | AMS units, slots with their remaining amount, edit, load and unload, dry |
| Files | the server's library (folders, files, six sorts), an inline search, upload into the open folder, and a file dialog that prints it on this printer or deletes it (§7) |
| Settings | the controller's own settings (§4) |

### Size and layout

- **Designed for a phone in landscape.** The target is an ordinary smartphone
  held sideways, about 890–915 × 410 dp (the reporter's Redmi 9T Pro is
  891×411 dp); after the top bar the body is about 860×345 dp. A layout is
  checked against that. The touch panel whose look the controller borrows is
  800×360, and that size is only the floor the body is laid out in
  (`controllerBodySize`), never the screen to design for.
- **One scale for the whole body.** Every tab is laid out in a box no smaller
  than `controllerBodySize` and scaled uniformly to fill the screen
  (`ScaleToFit`). Nothing inside scales on its own; a card that
  sized its own content made the same chip 44 in one card and 56 in the next.
- **No text is scaled to fit, anywhere.** Equal things are one size: a
  `FittedBox` around a label made each one a size of its own, so where text did
  not fit the layout gives way instead — the Overview tiles drop the target at
  four readings, the tabs scroll, the saver's box grows with the system font,
  the keypad takes the body's scale. `controller_text_size_test.dart` scans for
  a `FittedBox` outside `scale_to_fit.dart` and the keypad, and measures the
  Overview and Heat texts with the app's real fonts (`loadAppFonts`) in every
  language: the test font is as wide as it is tall and would show overflows
  that are not there.
- Presets, −/+ and actions (Load/Unload/Dry, Home) are one height
  (`controllerButtonHeight`, 56). The Move tab's jogs have no height of their
  own: every one fills its cell. The pad is a three-by-three grid over its
  section, and Z (up/down) and Extrude/Retract split their column between two
  buttons, so the two pairs are the same height wherever nothing else sits in
  the column (on two nozzles the extruder's choice takes a row).
- Each card has its title at its top (`ControllerCard`), never a caption
  glued to a control.
- Heat: a heater is a ring that fills toward its target with the current
  temperature in the middle. The ring takes the room its card has and the
  reading grows with it (28% of the ring's size, never scaled by the system
  font); nothing else on the card is scaled to fit. The target is only the bare
  number on the button between − and + ("220", "Off" when none). There is no
  heating/at-target/cooling label; the ring's colour says it.
- Move: two cards. Axes (X/Y and Z) with the step and Home under them, and the
  extruder with its own length presets.
- Filament: a tap chooses a slot (the one feeding the print until then); Load,
  Unload and Dry sit under the slots and act on it, through the card's own
  commands. The pencil on a slot opens the card's slot sheet (spool,
  configuration).

The fault view (reached from the chip, not a tab) lists the printer's HMS
faults with Retry, Ignore and Dismiss and a link to the troubleshooting page.

### Camera and preview

With "Live camera" on, the Overview shows the stream. With it off, it shows the
cover of the file being printed (`GET /printers/{id}/cover`, extracted from the
`.3mf`), marked as a file preview. A file without a cover shows an image icon
and "No preview".

### Move

The rules are the printer card's movement sheet's: steps of 1, 10 and 50 mm for
the pad and Z, lengths of 5, 10 and 25 mm for extrude and retract, and the Z
direction from `bedJogDistance` — where it cannot be known the buttons give way
to a note, never a guess. Home is the full auto-home only (`G28`): the server
ignores the `axes` argument (`routes/printers.py`, `home-axes`), so there is no
per-axis home to offer.

### Dual-nozzle printers (H2D, X2D)

- Overview shows four readings (Nozzle 1, Nozzle 2, bed, chamber); the active
  nozzle is outlined.
- Heat shows two nozzle cards. "Activate" is locked while printing, as the
  dashboard's nozzle sheet already does (`enabled: !widget.printing`).
- Move carries a Nozzle 1 / Nozzle 2 switch above Extrude and Retract.
  `POST /printers/{id}/extruder-jog` has no nozzle parameter: the server sends
  `G1 E…` to whichever extruder is active, so the switch is `select-extruder`
  (index 0 = right, 1 = left) followed by the jog.
- Chamber has a heater and an airduct switch on the models that have them
  (`supportsChamberHeater`, `supportsAirduct`).

### Filament lock

Load and unload are off while the printer is actively printing and on when it
is paused (the filament-runout case): `status.isPrinting && !status.isPaused`
for the whole printer, as in `printer_card_details.dart`. The server checks
nothing here; the lock is ours. Whether the firmware would take a load into the
idle hotend mid-print on a dual-nozzle printer is **not confirmed**, so the lock
stays on for both kinds.

## 3. Screen saver

A bouncing box, like the old DVD logo: it travels the whole screen and turns at
the edges, and its hue changes on every wall hit (a corner hit changes it by
both). Nothing keeps a fixed position or colour, which is the point on OLED
panels. It is dim. The colour stays between green and violet: red, amber and
yellow mean a fault in this app, and a saver passing through them looked like
a printer asking for attention.

- While it is up, everything under it is inactive. The first touch only wakes the
  screen and goes nowhere else.
- Waking restarts the idle timer. With no touch before it runs out the saver
  returns, also over an open fault dialog.
- A fault that **pauses the print** wakes the screen and opens the fault dialog
  (Retry, Ignore, Stop print; Stop goes through `confirmDialog`). Closing the
  dialog leaves the print paused and the fault in the chip. The app does not
  rely on a server flag for "this fault paused the print"; it infers it: the printer is
  `paused` and lists at least one displayable fault (`_onFaults` in
  `controller_saver.dart`, run when either changes). Each fault code raises the
  alert once; a fault that clears and comes back is new again.
- A fault that has already paused the print when the controller opens raises
  nothing: the chip shows it. A fault that is a warning, whether it arrives
  before the controller opens or after, opens the dialog when it pauses the
  print.
- A printer that drops off the network lists no faults; that is not its faults
  clearing, so one already answered does not raise the alert again when the
  printer comes back. The fault view never opens twice for one printer, from
  the chip and from the alert alike.
- It is not a screen lock: it protects the panel, not the printer.

## 4. Settings

| Setting | Meaning |
|---|---|
| Start after | idle time before the saver: 1, 2, 5, 10 or 15 minutes, or *Never* |
| Brightness | the screen's backlight while the saver is up, 10–100%: this window's own brightness, not the system setting, given back on wake and on leaving |
| Wake on warnings | whether a fault that does **not** pause the print also wakes the screen; faults that pause it always do |
| Screen always on | holds the screen on while the controller is open; the saver still runs |
| Live camera | on: stream; off: file preview |

The saver needs *Screen always on*: without it the phone's own timeout turns
the screen off, so the saver's settings are locked, the switch's line says the
saver is off, and the idle timer does not run.

Stored per device, like the wall-mode settings. Choosing *Never* raises a popup
that warns the screen may burn in and asks the user to confirm the risk; the
choice is stored only once confirmed. The list of times (1, 2, 5, 10, 15) is
provisional.

## 5. Server facts this relies on

Checked in the server reference (commit `219d8a4a8`, 2026-10-09; it may lag the
live server):

- `ams/load` and `ams/unload` do no print-state check.
- `extruder-jog` takes only a distance, no nozzle.
- `select-extruder`: `extruder` 0 = right, 1 = left.
- `cover` serves the active print's cover.

## 6. Build order

Milestone 1 — foundation and Overview: settings storage, entry and shell,
Overview. Milestone 2 — Heat, Move and Filament. Milestone 3 — faults, the
alert, the screen saver and the Settings tab. Each stage is one commit; each
milestone ends with a review.

## 7. Files tab

The Files tab browses the server's library and prints a file on the controller's
printer. The working plan is local (`docs/plans/` is gitignored), so what stays
open lives here. Built: the model-compatibility guard (`gcode_compat.dart`), the
shared create service (`queue_create_service.dart`), the tab and its listing
(`controller_files.dart`), the file dialog (`controller_file_dialog.dart`), the print
screen (`controller_print.dart`) with its "More options" dialog and the cost center
(`controller_print_more.dart`, `queue_cost_center_state.dart`).

- **File dialog.** A tap on a file opens a dialog scaled like the body (the scale is
  read before `showDialog`, under the body, because the route is not): thumbnail,
  name, size, sliced-for model, print time, grams, created date, a close icon, and two
  buttons. Print closes the dialog with a choice and the tab then pushes
  `openControllerPrint`; it is disabled, with the reason on the dialog, for a printer
  missing from the roster, a file that is not sliced, or a model the printer cannot
  take (`filePrintBlock`, in that order). Delete (through `confirmDialog`) is absent
  for an external file and for a file in an external, read-only or unwritable
  folder (`mayDeleteLibraryFile`).
- **Search.** A header button expands into a field in place of the path card (a
  dialog is inset by the keyboard and is left with about 100 dp). It applies on the
  keyboard's search action, never per key: the first search fetches the whole library.
  The applied query is a chip on the path card, cleared by a tap. A refresh or a
  folder change drops the query, as in the library screen.
- **Upload.** Picks one file and sends it into the open folder. Off, with the reason
  as the tooltip, for an external, read-only or unwritable folder. While a file is
  picked or sent the whole header and the grid answer nothing, and the path card
  carries a determinate bar; this is also what guards against a second upload. Done:
  refresh, invalidate `libraryStatsProvider`, toast. A tab left mid-upload does not
  stop the request: a success still refreshes the listing (while the controller is
  open) and invalidates the stats, without a toast; a failure writes only the log
  record.

Open points:

- **Toasts.** The Files tab and the print screen both use the screen's snackbar. Decide
  whether the controller wants a mechanism of its own before a third surface copies it.
- **Demo backend.** The library listing and delete are there; the upload route answers
  501 (as it does for the library screen), so the demo cannot show an upload end to end
  (`lib/core/demo/demo_backend.dart`).
- **Contract tests.** A library file queued from the controller sends the same fields
  as the print form, plus the new options of the More dialog; cover `cost_center_id`,
  the preheat fields and `confirm_outcome` against a docker server on `daily` and
  `latest` (`test/contract/`).
- **Chamber target stepper.** It moves in steps of 5 °C from "filament default"; 0 is
  not selectable and the maximum takes 12 taps. Revisit if it proves slow on a device.
- **Shared provider.** `fileManagerProvider` is shared with `FileManagerScreen`, which
  the dashboard can push beneath the controller; both would then share folder and
  search state. Theoretical, noted.
- **USB-stick uploads** depend on the phone's document provider and are not verified.
- **Compatibility guard** is deliberately stricter than the server for named printers;
  an unlisted-but-working model combination is blocked. Unknown models stay compatible.
- **Device check.** Nothing here was checked on a phone: the maintainer should try the
  file dialog, a search, an upload, and Print on a billing server, a multi-plate file,
  a dual-nozzle printer and a manual filament mapping.
