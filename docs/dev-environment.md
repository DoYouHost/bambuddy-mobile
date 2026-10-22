# Development environment

The local setup the project is developed on (Linux, zsh), the traps in it, and how
to run the pieces CI does not. What CI itself checks is in
[AGENTS.md](../AGENTS.md); the recipes are in the [justfile](../justfile) (`just`
lists them). **Read it when a local build fails on the toolchain rather than on the
code.**

## Toolchain

- **Flutter** is a git checkout of a stable tag. `flutter --version` in
  [ci.yml](../.github/workflows/ci.yml) prints the version CI runs; keep the local
  SDK on it. `dart format` output differs between releases, so a local SDK that
  drifts from the runners turns the Format step red on code that looked clean.
- **Android SDK** with the platform and build-tools of the current target SDK, plus
  `cmdline-tools/latest`. Android Studio (the tarball, not the Flatpak) is used as
  SDK and AVD manager; day-to-day editing is VS Code with the Dart and Flutter extensions.
- **The system JDK can be newer than Android supports** (JDK 25 against AGP). Point
  Flutter at the JDK bundled with Studio: `flutter config --jdk-dir <studio>/jbr`.
  A build that dies on the JDK is checked against this setting first.
- **`flutter doctor` reports no Chrome.** Web is not a target (there is no `web/`
  directory); ignore it.

### Compile Kotlin without building an APK

```sh
JBR=<studio>/jbr
cd android && ./gradlew --offline \
  -Dorg.gradle.java.home=$JBR -Porg.gradle.java.installations.paths=$JBR \
  :app:compileMobileDebugKotlin :app:compileWearDebugKotlin
```

Both flags are needed. Without them Gradle's toolchain resolution picks the system
JDK, which on a JRE-only install has no compiler, and fails with
`Toolchain installation ... does not provide the required capabilities:
[JAVA_COMPILER]` — it reads like a dependency problem and is a toolchain choice.
`--offline` is enough once a normal build has filled the Gradle cache.

### After changing a plugin version, `flutter clean`

An incremental build otherwise fails in `GeneratedPluginRegistrant.java` with
`cannot find symbol` for a plugin class that exists: stale generated output, not a
real break. Run `flutter clean` (or `just clean`) before suspecting the upgrade.
[dependency-upgrades.md](dependency-upgrades.md) lists the upgrades that need more
than a bump.

## Emulators

`just emu-list`, `just emu-boot [avd=…]`, `just run`, `just run-wear` and
`just test-device` drive them; the default phone AVD is `pixel35` (Pixel 7, API 35,
Google APIs, x86_64). Hardware acceleration needs `/dev/kvm` to be usable by your
user (`emulator -accel-check`).

`emu-boot` kills a boot that has not finished in `EMU_BOOT_TIMEOUT` seconds (180 by
default) and tries again, three times in all: a hung emulator shows as `offline` in
adb, and nothing waiting on it would ever give up. The test recipes boot with
`cold`, which adds `-no-snapshot-load`; a snapshot saved from a killed or half-booted
run is what hangs the next boot, and the hung one is killed with SIGKILL so it cannot
save one. An emulator that was already hung before `emu-boot` ran is not found by it
(it reads as not running) and blocks the AVD's lock; kill that process by PID first.

- **A narrow-screen AVD catches layout bugs the default one hides.** Create one
  from the *Galaxy Nexus* device profile, API 35 Google APIs x86_64, 720×1280 at
  320 dpi — 360 dp wide, against 411 dp for the Pixel 7. The justfile mentions it as
  `small360`. Set it to the locale and text size the layout work is measured at
  (see [conventions.md](conventions.md#layout-and-widgets)):

  ```sh
  adb -s <serial> shell setprop persist.sys.locale pl-PL
  adb -s <serial> shell setprop ctl.restart zygote    # kills a running `flutter run`
  adb -s <serial> shell settings put system font_scale 0.85    # no restart needed
  ```

- **Wear OS 3 (API 30) has no x86_64 system image**; only `x86` and `arm64-v8a`
  exist. On `x86` the APK installs (the image translates ARM) but the Dart VM
  crashes with SIGSEGV, and Flutter no longer builds 32-bit x86 (`--target-platform`
  accepts `android-arm`, `android-arm64`, `android-x64`). Such an AVD is good for
  the splash screen, which the window manager draws from resources before Dart
  starts, and for nothing else; test the watch UI on API 34 or newer. Raise the
  AVD's RAM to 1536 MB — the profile's 512 MB stopped the boot early.

## On-device tests

`just test-device` runs `integration_test/` and `just test` adds the watch tests
under `patrol_test/` when `adb` and the emulator exist (and says so when it skips
them; the watch ones need `dart pub global activate patrol_cli`). They exist because
a host `flutter test` cannot see a socket: its binding replaces the HTTP client, so
a server and a client in one test exchange status and headers and no body.
The traps that shaped them are written next to the code they bit:

- Dio never delivers a `multipart/x-mixed-replace` body, which is why the camera
  view is on `dart:io` — [mjpeg_view.dart](../lib/features/camera/mjpeg_view.dart).
- A test server must push frames periodically; one write proves nothing — and the
  subscription is not cancelled before the socket closes, which would leave an
  unhandled "Connection closed" error — both in
  [camera_stream_test.dart](../integration_test/camera_stream_test.dart) and
  `mjpeg_view.dart`.
- The debug APK is reinstalled with `adb install -r -g` before each test file, for
  the notification permission — comment on the `test-device` recipe.

## Contract tests locally

`test/contract/` runs against a real bambuddy and is skipped everywhere
`BAMBUDDY_CONTRACT_URL` is unset. Mirror
[contract-tests.yml](../.github/workflows/contract-tests.yml) with containers of
your own names (other sessions' may be running):

1. A broker standing in for a printer: `eclipse-mosquitto:2` with
   [mosquitto.conf](../tool/ci/mosquitto.conf) and a self-signed certificate.
2. `docker run -d -p 127.0.0.1:<port>:8000 -e TZ=Europe/Warsaw
   ghcr.io/maziggy/bambuddy:<tag>`. The workflow's matrix is `latest` (last
   release), `daily` (development branch, newest features) and a pinned older
   release. A new field is asserted on `daily`; the older tags prove the silent drop,
   so write each test to pass on all of them (detect the feature from the payload,
   `markTestSkipped` where an old server has nothing to check).
3. [seed_bambuddy.sh](../tool/ci/seed_bambuddy.sh) with the server URL, the broker's
   container IP and name.
4. `BAMBUDDY_CONTRACT_URL`, `_USER`, `_PASS`, `_BROKER` (container name) and
   `_BROKER_IP` set, then `flutter test test/contract --concurrency=1`.

Why the flags: `--concurrency=1` because every file writes to the same server and
SQLite reuses a deleted row's id, so one file's "id is gone" check can read
another's new row. A non-UTC `TZ` (the workflow uses `Europe/Warsaw`) because in UTC
a naive timestamp read as local or as UTC is the same instant, and the timestamp
tests would pass whatever the parser did.

Working with the seeded server: it has a library file but no archive; one is made by
`POST /archives/upload` with that file's bytes. A print is driven with
`publishReport` in [contract_harness.dart](../test/contract/contract_harness.dart)
(`mosquitto_pub` into the broker container); the server's print-start handling
retries FTP against the stand-in for a while, so wait for the archive before
publishing `FINISH`. A test that moves the seeded printer is named to sort last
(`ws_…`), since the files run in name order. Prove a new test bites: invert the
detection it relies on and watch it fail.

## The server reference clone

`reference/bambuddy` is a shallow clone of the server, excluded through
`.git/info/exclude` so the tracked `.gitignore` stays untouched. It answers contract
questions (see AGENTS.md); these are the ways it misleads.

- **Know what it stands on.** `git -C reference/bambuddy log -1 --format='%h %cs'`
  — the checkout moves between a tag, `dev` and a detached commit. Read an older
  state with `git show <tag>:<file>`. `git log A..B` does not cross the shallow
  boundary; `git fetch --unshallow` if you need the history.
- **Match the issue you are triaging.** The `Server drift: <sha>` issue (#31)
  carries a `server_sha:` line; `git -C reference/bambuddy checkout --detach <sha>`
  before judging it, or you read older code than the report describes and conclude
  a route "does not exist". Back to current: `checkout dev && git pull`.
- **A clone whose `remote.origin.fetch` lists only `main` never updates
  `origin/dev` on a bare `git fetch origin`**, and prints nothing about it. Check
  `git config --get-all remote.origin.fetch`; fetch explicitly with
  `git fetch origin "+dev:refs/remotes/origin/dev"` and compare
  `git ls-remote origin dev` with `git log -1 origin/dev` before denying that
  something in a report exists.
- **Use absolute paths.** `cd reference/bambuddy` in a command moves the shell's
  working directory for everything after it.
- The server version a running instance reports is readable without a key:
  `curl -s <host>/api/v1/updates/version`.
- **Fixtures from a live server:** `tool/capture_fixtures.sh <base-url>`, key read
  from a file (see the script header). Capture with a printer connected: an offline
  printer's status has no `ams`, and the capture would replace a full fixture with a
  thin one. The script skips a non-200 endpoint and leaves the old file in place, so
  check `git status` afterwards.

## Copy checks (LanguageTool)

`just l10n-check` (branch diff) and `just l10n-check-all` send the strings to a
LanguageTool server. Without configuration that is the public API: the **whole copy
of the app goes to a third party** and it is limited to 20 requests a minute. Set
`LANGUAGETOOL_URL` to a self-hosted instance in your shell or agent environment, not
in the repository — the script default stays the public URL, and no instance address
belongs in the justfile, `tool/l10n_language.toml` or the docs. A self-hosted
instance may reject Python's default `urllib` User-Agent with a 403; the checker
sends its own. After touching the check, `grep -rn` the repo for your instance's host name:
there must be no hit.

Terminology the check cannot judge (printer part names in Polish) is in
[glossary.md](glossary.md).
