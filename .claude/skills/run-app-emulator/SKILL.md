---
name: run-app-emulator
description: Launch the bambuddy-mobile Flutter app on an Android emulator so that hot reload (r) and hot restart (R) work from a background session. Use when asked to run/start the app, verify a UI change live, or take a screenshot on the emulator.
---

# Run the app on an emulator with working hot reload / hot restart

The catch: when `flutter run` is started as a background task, the harness binds
its **stdin to `/dev/null`**. The Dart tool reads `r`/`R`/`q` keystrokes from
stdin, so with `/dev/null` you can never trigger a hot reload or restart — the
only way to pick up a code change is to kill and relaunch (full rebuild, ~1 min).

The fix is to give `flutter run` a **named pipe (FIFO)** as stdin. Then `printf`
into that FIFO to send the interactive commands.

## Prerequisites

- Emulator online: `adb devices` should list the target (e.g. `emulator-5554`
  for the local AVD, or `192.168.2.208:5555` for the shared headless GPU
  emulator — `just emu-connect` connects the latter).
- Flavors are mandatory: every `flutter run` **must** pass `--flavor mobile`
  (or `--flavor wear --target lib/wear/main_wear.dart` for the watch).

## Launch (do this once)

Set a scratch dir and create the FIFO, then launch in the background with the
FIFO as stdin:

```bash
SCRATCH=<your-scratchpad-dir>
mkfifo "$SCRATCH/flutter_stdin"          # ignore error if it already exists
# Hold the FIFO open read-write on fd 3 so flutter doesn't see EOF and detach.
exec 3<>"$SCRATCH/flutter_stdin"
flutter run -d emulator-5554 --flavor mobile <&3 2>&1 | tee "$SCRATCH/flutter_run.log"
```

Run that command with `run_in_background: true`. Wait for the log line
`A Dart VM Service on ... is available at:` before sending commands (a Monitor
`until grep -q "is available at:" ...` loop is a clean way to wait).

## Drive it

```bash
printf 'r' > "$SCRATCH/flutter_stdin"    # hot reload  🔥
printf 'R' > "$SCRATCH/flutter_stdin"    # hot restart (rebuilds widget tree)
printf 'q' > "$SCRATCH/flutter_stdin"    # quit the app + flutter run
```

After sending, tail the log to confirm:
- reload → `Reloaded N libraries in ...`
- restart → `Restarted application in ...`

`Reloaded 0 libraries` right after a fresh launch is normal — the launch already
compiled current source, so there was nothing new to sync.

## Verify visually

```bash
adb -s emulator-5554 shell screencap -p /sdcard/s.png
adb -s emulator-5554 pull /sdcard/s.png "$SCRATCH/s.png"
```

Then Read the PNG. Look at the screenshot — a blank frame means launch failed.
Prefer navigating via semantics (`uiautomator dump` → tap the node center by
its content-desc label) over blind coordinates; see the ui-automation memory.

## Gotchas

- **Don't** launch `flutter run` as a plain background task and then try to
  `printf` into `/proc/<pid>/fd/0` — that fd is `/dev/null`, writes go nowhere.
- Hot **reload** (`r`) preserves state but skips changes to `main()`, global
  state, enums, or anything needing a fresh widget tree. When in doubt use hot
  **restart** (`R`).
- Changes to native code, `pubspec.yaml`, or assets need a full relaunch, not
  reload/restart.
