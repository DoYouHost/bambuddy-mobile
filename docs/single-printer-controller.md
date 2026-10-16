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
   provider, not in the widget, and test that a fault on printer B leaves
   printer A's controller alone.
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
| Settings | the controller's own settings (§4) |

### Size and layout

- **One scale for the whole body.** Every tab is laid out in a box no smaller
  than the phone design (`controllerBodySize`, 800×360) and scaled uniformly to
  fill the screen (`ScaleToFit`). Nothing inside scales on its own; a card that
  sized its own content made the same chip 44 in one card and 56 in the next.
- Presets, −/+ and actions (Load/Unload/Dry, Home) are one height
  (`controllerButtonHeight`, 56). The Move tab's jogs — the pad, Z, Extrude
  and Retract — share one height of their own, sized so the pad fills the
  axes card; the pad, Z and the extruder's buttons stretch to their cards'
  width.
- Each card has its title at its top (`ControllerCard`), never a caption
  glued to a control.
- Heat: a heater shows its reading and whether it is heating, at target or
  cooling; the target is on the button that changes it ("Target 220°").
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
panels. It is dim.

- While it is up, everything under it is inactive. The first touch only wakes the
  screen and goes nowhere else.
- Waking restarts the idle timer. With no touch before it runs out the saver
  returns, also over an open fault dialog.
- A fault that **pauses the print** wakes the screen and opens the fault dialog
  (Retry, Ignore, Stop print; Stop goes through `confirmDialog`). Closing the
  dialog leaves the print paused and the fault in the chip.
- A fault already reported when the controller opens raises nothing: the chip
  shows it. A fault that is a warning first and pauses the print later opens
  the dialog when it pauses.
- It is not a screen lock: it protects the panel, not the printer.

## 4. Settings

| Setting | Meaning |
|---|---|
| Start after | idle time before the saver: 1, 2, 5, 10 or 15 minutes, or *Never* |
| Brightness | how bright the saver is, 10–100% |
| Wake on warnings | whether a fault that does **not** pause the print also wakes the screen; faults that pause it always do |
| Keep screen awake | holds the screen on while the controller is open |
| Live camera | on: stream; off: file preview |

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
