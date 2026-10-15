# Single-printer controller — reference research for issue #54

Researched 2026-10-16 for [issue #54](https://github.com/DoYouHost/bambuddy-mobile/issues/54).
Everything here comes from BIGTREETECH's public pages, the official screenshots
and the UI string table (`Translation/en-GB.yml`) they publish in their own
repository. On request the `en-US.img` language pack and the firmware
the v1.0.8.0 firmware `.bin` were also downloaded and inspected, to the
depth described in §3. Nothing from them is copied into this repo.

## 1. Summary

- The device the issue refers to (BIGTREETECH, "BTT" below) is a 5" 800×480 ESP32-S3 touch screen that talks to Bambu printers
  directly (LAN mode or Bambu Cloud). It is a **closed-source product**.
- The `bigtreetech/PandaTouch` GitHub repository is public but **has no licence
  and no source code**: it holds firmware binaries, language packs, a hardware
  manual, CAD for the dock, and release notes with screenshots.
- BIGTREETECH has said in writing that it will not publish the source
  (issue #351). The published string table already lists every screen and
  control, so the full feature scope is known without touching the binaries (§4a).
- Our app already implements most of what the BTT screen does, through the
  bambuddy server. What is missing is a **single-printer landscape layout**,
  not new API (§6).
- The BTT screen is 5" at 800×480 px (about 686×411 dp). A phone in
  landscape is wider and a little shorter, so height is the layout constraint (§7).

## 2. What the BTT screen is

| | |
|---|---|
| Hardware | ESP32-S3R8, 8 MB PSRAM, 16 MB flash, 5" IPS 800×480, 2.4 GHz Wi-Fi, USB drive (FAT32), I²C for a temperature/humidity sensor (BTT's own sensor kit), internal battery (~30 min) |
| Printers | P1P, P1S, X1C, X1E, A1, A1 mini (limited by the Bambu firmware version, per the wiki) |
| Connection | LAN mode (IP + serial + access code), or Bambu Cloud account (2FA must be off, login expires about every three months) |
| Languages | Language packs as `.img` files (en-GB/US/ZA, cs, de, es, fr, it, ja, ru, zh-CN) |
| Update | Over Wi-Fi from the device's own web UI, with a `.bin` + a language `.img` |
| Accessories | BTT's smart power module (shutdown after print, power usage) |

Multi-printer features: up to 10 groups, each with a leader printer; group
printing from a USB drive only, with a delay between members.

## 3. Licence and source availability

| Item | State |
|---|---|
| `bigtreetech/PandaTouch` | Public, `license: null` (GitHub reports no licence file). No licence means all rights reserved by default. |
| Its contents | Firmware `.bin` / `.img` releases, `Recovery_tool` zip, `Translation/*.yml` (UI strings, open for community translation), `3D/` (dock STEP/STL), manual PDF, release notes with screenshots. **No firmware source.** |
| `bigtreetech/PandaTouch_IDF`, `PandaTouch_PlatformIO` | Public "base framework" for building your own firmware on the hardware. Also `license: null`. |
| Stated position | Issue #351 (2025-10-31, answered by `bigtreetech`): the full source "represents years worth of R&D" and will not be released; the base frameworks are the offer instead. |
| Third-party code in it | Issue #39 (answered by the maintainer `looxonline`, who also answers #3): built on ESP-IDF (Apache 2.0), "no other GPL libraries", FTP stack written from scratch. |

**Unpacking the firmware.** Done once, on request, for the `en-US.img` language
pack only (kept in the session scratchpad, not in the repo). Result: it is not
a standard archive (`7z` refuses it); it opens with two
numbers followed by what looks like raw pixel data. That fits BTT's own description in
`Translation/README.md`: translators submit the `.yml` and BTT "generates an
IMG file" from it with an online tool, i.e. the pack is the string table
rendered into bitmaps. So it carries **no feature the `.yml` does not already
list**, and reading it further would mean decoding an undocumented bitmap
format to get at their artwork, which we neither need nor should reuse.
I stopped there.

The v1.0.8.0 firmware `.bin` was then opened too, on request,
and only as far as its structure and its readable strings: a standard
uncompressed ESP-IDF application image for the ESP32-S3 (v1.0.8, built 2026-07-03), five segments, about 0.9 MB of read-only data and
1.4 MB of code. No disassembly, no decompilation, no extraction of bitmaps.
What it adds is in §4b.

Two cautions that still apply:

- BIGTREETECH has explicitly refused to release the source, and the repo has no
  licence, so nothing in it (strings, bitmaps, layout) is reusable as ours.
  The `.yml` was read to list *what the device can do*; none of its wording is
  copied here or should be copied into the app.
- This is an engineering judgement, not legal advice. I did not read BTT's terms
  of sale or any EULA that may ship with the device.

**What this means for "reproduce the look and functions".**
Functions are not protected; a copied interface can be. The practical line:
same *kinds* of screens and controls (a printer list, a filament view, a file
browser are generic), own layout, own icons, own colours, own wording. Do not
copy their artwork (the mascot, the AMS spool drawing, the icon set) and
do not use the product's name or BIGTREETECH branding in the app, the store
listing or the in-app copy. Naming it in this issue and in internal docs is
fine; it is how we refer to the thing we compare against.

## 4. UI inventory (from official screenshots and the wiki)

Source for every item: the v1.0.8.0 release notes
(`Firmware/1.0.8.0/images/*.png`, 800×480) and the wiki page. Where neither
shows a screen, it is listed in §5.

**Frame.** Dark grey theme, red accent for the active item.

- *Left rail*, five icons, top to bottom: Home, Temperature/Axis (sliders icon),
  Files, Settings, Printers/Groups (tree icon). The active one is red.
- *Top bar*: three red numeric badges at the left (the wiki says the corner
  shows the number of printers that sent HMS notifications; what three numbers
  mean is not documented), the printer or group name centred (a group shows
  "group / leader"), and status icons at the right (cloud, connection arrows,
  Wi-Fi). Tapping the bar opens the HMS notification centre.

**Home — printer cards** (card list, scrolls vertically; v1.0.8.0 added a table
"list mode" as an alternative). Each card:
printer number and name, current file name, progress bar with percent, layer
`x/y`, time left, nozzle / bed / chamber temperatures with icons, and a status
pill ("Finished", or Pause + Stop while printing). A finished job offers a
quick reprint.

**Printers/Groups — list mode.** Table: No., Device Name, Status/Task
(Idle, or `72% | -12m` with a bar), Actions & Connection (Edit, Delete, three
status icons). A round "+" button adds a printer or group; a second round
button switches the view. The selected row has a red outline.

**Temperature/Axis / Filament / power module** — three tabs on one screen.
- *Filament tab*: a strip on top with the external spool and each AMS unit
  (an arrow marks the selected one), the filament type under each slot, a large
  spool drawing of the selected unit with a pencil on each slot to edit it,
  a humidity readout (with a drying button), a load/unload action at the
  bottom right. The external spool has its own view.
- *Temperature/Axis tab*: **no official screenshot found.** The changelog says
  moving an axis during a print shows a "not allowed" prompt, and that the
  sensor-kit reading is shown here.

**Files** — tabs per source: the printer's SD card, the USB drive, Print
history (last 12). Header: Name, current path, Date, Size sort controls.
Thumbnail grid (file name + date under each) or list; a column of buttons at
the right: scroll up, scroll down, list/thumbnail toggle, refresh. Starting a
print opens an options dialog: bed levelling, flow calibration (not on P1),
timelapse, use AMS, auto power-off, reset usage (the last two only with a
power module). Only `.3mf` files sliced on plate 1 are recognised (the 2024 manual
limits the listing to the root directory; the wiki later describes folder
browsing), and the home-screen thumbnails need a Bambu Studio `.3mf` ≤ 20 MB.

**Print screensaver** (v1.0.8.0): black screen, huge percent in red, layer
`x/y`, time left and the file name in grey. It exists "to help prevent
accidental operation while a print is running"; the device stays awake while a
job runs.

**Other.** HMS notification centre with a QR code to Bambu's troubleshooting
page and per-alert dismissal; skip objects; filament drying (X1 and P1S); an
on-screen keyboard; brightness; screen saver; Wi-Fi and printer setup screens.

## 4a. Full feature scope (from the string table)

`Translation/en-GB.yml` (1262 lines; 808 of them are Bambu HMS fault
texts) lists every label the UI can show. Grouped by what the user can do:

**Settings.** Language; firmware version and the OTA update guide; auto-sleep
(1, 2, 3, 5, 10, 15, 60 min or "Always On"); *Read Only Mode*; *Wake at Print
Start*; *Stay Awake While Printing*; backlight brightness; restart; factory
reset; Wi-Fi scan and connect. **Choosing "Always On" asks "This operation will
cause damage to the screen. Do you want to continue?"** — the vendor itself
warns about burn-in, which supports the screen saver decision (§7).

**Printers.** Add by scan or by hand (model, name, IP, access code, serial;
optional filament colour/material and nozzle diameter/material); edit; delete
only while disconnected; a connection-status line for each (connecting,
connected, failed); card view or list view; a cap on the number of printers.
Groups with a leader and followers, "sync" state, a cap on groups, group
names. Cloud mode: login by phone or e-mail with a 6-digit code, region
(China/Global), converting printers to cloud mode.

**Printing.** Start-print dialog with a pre-flight reminder (sliced for this
printer, filament matches the AMS) and options: bed levelling, flow calibration,
timelapse, use AMS or spool holder. Upload progress states (transmitting,
waiting, printing, failed) and "abort the current and subsequent uploads".
Print phases shown (heatbed preheating, cleaning the nozzle tip, auto bed
levelling, preparing). Pause, resume and stop, each behind a confirmation
("once you stop a print, you cannot resume it"); pause all and stop all for a
group; reprint (on one printer only, in a group). Skip objects with a count of
the selected ones. Print history (time, weight; cloud mode only). Default
directory on the printer; "enhanced thumbnail display" that trades speed for
previews.

**Temperature/Axis.** Fan switches (part, aux, chamber) ON/OFF; print speed
(Silent, Standard, Sport, Ludicrous); extruder; temperature inputs with a stated
ceiling ("Not higher than N°C"). The axis jog labels are not in the table, so
they are icons.

**Filament.** Spool holder and AMS view; edit a slot (type, colour, minimum and
maximum temperature); read-only note for Bambu RFID filament and a re-read
action; *load* and *unload* as a guided sequence (heat the nozzle, push new
filament in, grab, purge the old, cut, pull back) with a Retry / Done step at the
end and a hint for each failure (not fed, not pulled, clogged, runout, AMS
overload); material warnings (TPU not supported by the AMS, CF/GF brittle, PVA
needs drying); humidity readout; AMS drying with duration and temperature, and a
separate four-step heatbed-drying wizard (prepare, place the spool, choose type
and temperature, start) that is not offered on A1/A1 mini.

**Files.** Printer SD card, USB drive and print history as tabs; name, date
and size sort; thumbnails; "no SD card" and "no USB" messages.

**Faults.** A notification centre with the HMS list, "ignore all", a QR code to
the troubleshooting page, and a prompt for the faults that need an answer
(Retry, Abort, Ignore, Done).

**Power module.** Bind and unbind; voltage, current, power and
energy readout; auto power-off with a countdown and a hotend-below-50 °C
check; "USB 1 follows printer light"; reset usage; power off a whole group.

**Onboarding.** Language pick, Wi-Fi, a step-by-step guide to finding the
printer's IP, access code and serial, a QR code to the online manual.

**Compatibility.** When the printer's firmware requires Bambu authorisation the
device drops to *Read Only Mode* and says how to regain control (LAN-only
developer mode or rolling back).

Ideas worth carrying over, because our server API already allows them: the
guided load/unload sequence with a failure hint per step, per-fault answer
buttons, confirmation wording that names the consequence ("cannot be
resumed"), a *read only* state with a reason, and a pre-flight reminder on
start.

## 4b. What the firmware image adds

About 8,100 readable strings; the UI ones are the `.yml` keys already covered
in §4a. The new information is how the device talks to a printer:

- It is an MQTT client of the printer (local broker in LAN mode,
  `us.mqtt.bambulab.com` / `cn.mqtt.bambulab.com` in cloud mode) plus an FTPS
  client for uploading files. Message fields seen: `pushall`, `project_file`,
  `gcode_line`, `ledctrl` / `led_node`, `chamber_light`, `print_speed`,
  `ams_control`, `ams_change_filament`, `ams_filament_setting`, `ams_get_rfid`,
  `ams_filament_drying`, `skip_objects`.
- Temperatures and fans go out as plain G-code: `M104 S%d` (nozzle),
  `M140 S%d` (bed), `M106 P%ld S%d` (fan). Jogging is `G0 X0 Y%d F3000` and
  `G0 Z%d F3000`, extrude and retract are `G1 %s F150` / `G1 %s F9000`.
- The device also serves a small web page for Wi-Fi and firmware upload.
- The text the firmware ships for a Bambu fault is the printer's own HMS table.

None of that changes the plan. Our app does not speak to the printer at all;
it calls the bambuddy server, which already exposes the same operations as
REST routes (§6). The strings confirm the feature list and add no screen that
the `.yml` and the screenshots had not shown. The screen layout is not in the
strings: it lives in compiled drawing code, and reading it would be
disassembly, which this research does not do.

## 5. Gaps

- No official screenshot of the Temperature/Axis tab. The string table says
  what it contains (§4a) but not how it is laid out or what the jog pad looks
  like.
- No screenshot of the Settings screens or the notification centre.
- Nothing says how a card looks for an offline or errored printer.

If layout of these matters, the next step is a third-party video review of the
device, not the firmware. A gap is not a requirement: the controls we already
have are the better reference for what a single-printer panel needs.

## 6. Mapping to the app

What exists today (route constants in [endpoints.dart](../lib/core/api/endpoints.dart),
actions in [controls_providers.dart](../lib/features/dashboard/controls_providers.dart)):

| BTT screen | In the app |
|---|---|
| Pause / resume / stop | `printPause` / `printResume` / `printStop` |
| Chamber light, speed profile | `chamberLight`, `printSpeed` |
| Nozzle / bed / chamber target | `nozzleTemperature`, `bedTemperature`, `chamberTemperature` (chamber only on models with an active heater, version-gated) |
| Fans | `fanSpeed` (part / aux / chamber) |
| Axis / extruder | the `move` and `extruder` control actions, `bed_jog.dart` |
| AMS view, load/unload, edit slot | AMS slot configuration, `ControlAction.ams` |
| Filament drying | `dry`, AMS drying route |
| HMS list, dismissal | `hmsClear`, `hmsExecuteAction` |
| File browser of the printer | `printerFiles*` routes (needs `PRINTERS_FILES`) |
| Skip objects | skip-objects screen |
| Multi-printer list | dashboard / wall mode |
| Print screensaver | not built — would be new, wall mode already holds the screen on (`FLAG_KEEP_SCREEN_ON`) |

No equivalent, and none wanted (the server owns it): Wi-Fi and printer setup,
cloud-mode login, firmware OTA, USB drive, power-module binding (the server's
smart plugs cover power), groups and group printing (the queue covers it).

## 7. Decisions

Decided by the maintainer on 2026-10-16:

1. **Accidental touch.** Risky actions (stop, and any other that cannot be
   undone) ask for confirmation through `confirmDialog`. No lock or PIN.
   Wall mode is read-only by design (D13 in [tv-flavor.md](tv-flavor.md)), so
   this is a new rule, not an extension of it.
2. **Screen saver.** Wanted, because fixed elements left on for hours burn in
   on OLED panels, which is what an old phone has. It should move or dim the
   content rather than only blank it, and wake on touch.
3. **Entry point.** A "Controller" action in the dashboard's menu, next to
   wall mode, opening a popup to pick the printer to control. Pushed on top of
   the dashboard, never `go`, for the reason in tv-flavor.md §13.2.
4. **Size.** Landscape only, as wall mode is. The BTT screen is 5" at 800×480 px,
   about 187 ppi, which is roughly 686×411 dp in Flutter terms. A phone in
   landscape is typically wider and a little shorter (about 780–890 × 360–410
   dp), so the height is the constraint.
5. **Name.** Nothing in the app, the store listing or the in-app copy says
   the product's name or refers to it (§3).
6. **Permissions.** Every control honours the gates in
   [providers.md](providers.md): one the key or user may not use is hidden or
   disabled. Which of the two, per control, is decided at implementation.

## 8. Sources

- [bigtreetech/PandaTouch](https://github.com/bigtreetech/PandaTouch) — repo, releases, release notes v1.0.8.0
- [Issue #351 — open source request](https://github.com/bigtreetech/PandaTouch/issues/351), [#39](https://github.com/bigtreetech/PandaTouch/issues/39), [#3](https://github.com/bigtreetech/PandaTouch/issues/3)
- [bigtreetech/PandaTouch_IDF](https://github.com/bigtreetech/PandaTouch_IDF), [PandaTouch_PlatformIO](https://github.com/bigtreetech/PandaTouch_PlatformIO)
- [Translation/en-GB.yml](https://github.com/bigtreetech/PandaTouch/blob/master/Translation/en-GB.yml) and its [README](https://github.com/bigtreetech/PandaTouch/blob/master/Translation/README.md)
- [Release v1.0.8.0](https://github.com/bigtreetech/PandaTouch/releases/tag/release%2Fv1.0.8.0) — the `.bin` and `.img` files inspected
- [BIGTREETECH wiki — product page](https://global.bttwiki.com/PandaTouch.html)
