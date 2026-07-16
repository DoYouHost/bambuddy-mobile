# Release artifacts live in build/dist (survives _clean-artifacts, which only
# wipes build/app) so the phone build isn't destroyed by the later watch build's
# clean — both flavors must coexist for `release` to upload them together.
apk := "build/dist/app-mobile-release.apk"
wear_apk := "build/dist/app-wear-release.apk"
repo := "DoYouHost/bambuddy-mobile"
# Shared headless GPU Android 14 emulator (TofuSadurki: lxc-docker-android).
emu := "192.168.2.208:5555"
# Local AVD (Pixel 7, API 35) — boots as emulator-5554 (see dev-env-fedora).
avd := "pixel35"
local_emu := "emulator-5554"

# show available commands
default:
    @just --list

# run tests
test:
    flutter test

# wipe build outputs + the Dart kernel snapshot so a release build can't pack a
# stale snapshot (incremental release builds here repeatably reused an outdated
# one — same code shipped, wrong bytes). Cheap insurance before any release build.
_clean-artifacts:
    rm -rf build/app .dart_tool/flutter_build

# build phone release APK (flavors force an explicit --flavor)
build: _clean-artifacts
    flutter build apk --release --flavor mobile
    mkdir -p build/dist
    cp build/app/outputs/flutter-apk/app-mobile-release.apk {{apk}}

# build watch release APK (Wear OS entry point + wear flavor/manifest)
build-wear: _clean-artifacts
    flutter build apk --release --flavor wear --target lib/wear/main_wear.dart
    mkdir -p build/dist
    cp build/app/outputs/flutter-apk/app-wear-release.apk {{wear_apk}}

# build Play Store bundles (AAB) for both flavors — Play accepts only AAB.
# Clean before each flavor so neither packs the other's (or a stale) snapshot;
# the clean wipes build/app, so copy each AAB into build/dist/ before the next
# build. Both end up side by side in build/dist/ for a single Play release.
build-aab:
    just _clean-artifacts
    flutter build appbundle --release --flavor mobile
    mkdir -p build/dist
    cp build/app/outputs/bundle/mobileRelease/app-mobile-release.aab build/dist/
    just _clean-artifacts
    flutter build appbundle --release --flavor wear --target lib/wear/main_wear.dart
    cp build/app/outputs/bundle/wearRelease/app-wear-release.aab build/dist/
    @echo "AABs ready in build/dist/:" && ls -1 build/dist/*.aab

# clean build artifacts
clean:
    flutter clean

# connect to the remote GPU emulator on the nuc LXC (idempotent, needs LAN)
emu-connect:
    adb connect {{emu}}

# run the app on the remote GPU emulator (screen view at http://192.168.2.208:8000)
dev: emu-connect
    flutter run -d {{emu}} --flavor mobile

# run integration tests on the remote GPU emulator
itest: emu-connect
    flutter test integration_test/ --flavor mobile

# Idempotent (no-op if emulator-5554 is already online); boots in the background
# and blocks until Android finishes booting, so local recipes can depend on it.
# boot the local pixel35 AVD
emu-local:
    #!/usr/bin/env bash
    set -euo pipefail
    if adb devices | grep -q "^{{local_emu}}"; then
        echo "{{local_emu}} already running"
        exit 0
    fi
    "$HOME/Android/Sdk/emulator/emulator" -avd {{avd}} >/dev/null 2>&1 &
    disown
    echo "Booting {{avd}}..."
    adb -s {{local_emu}} wait-for-device
    until [ "$(adb -s {{local_emu}} shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
        sleep 2
    done
    echo "{{avd}} ready"

# Boots the emulator first if needed; builds, installs and runs with hot reload.
# This is the primary pre-commit verify loop.
# run the app (debug) on the local pixel35 AVD
dev-local: emu-local
    flutter run -d {{local_emu}} --flavor mobile

# run integration tests on the local pixel35 AVD (boots it first if needed)
itest-local: emu-local
    flutter test integration_test/ --flavor mobile

# one-time setup: open the device list in emu-view's dedicated Chrome profile so
# "Fit to screen" + Save settings persists there (localStorage, per player=mse).
# Then `just emu-view` picks it up. Configure -> keep Fit to screen ON -> Save.
emu-config:
    flatpak run com.google.Chrome \
      --user-data-dir="$HOME/.config/chrome-emu" --no-first-run --no-default-browser-check \
      --app='http://192.168.2.208:8000' >/dev/null 2>&1 &

# ws-scrcpy deep-link skips the device list (MSE player, fixed scrcpy port 8886,
# stable across restarts). URL is single-quoted so the shell keeps the &/#/%.
# A dedicated --user-data-dir forces a separate Chrome instance so --window-size
# is actually honored (a window in an already-running Chrome ignores size flags).
# open the emulator screen straight into a dedicated phone-sized browser window
emu-view:
    flatpak run com.google.Chrome \
      --user-data-dir="$HOME/.config/chrome-emu" --no-first-run --no-default-browser-check \
      --window-size=500,1000 \
      --app='http://192.168.2.208:8000/#!action=stream&udid=android-emulator%3A5555&player=mse&ws=ws%3A%2F%2F192.168.2.208%3A8000%2F%3Faction%3Dproxy-adb%26remote%3Dtcp%253A8886%26udid%3Dandroid-emulator%253A5555' \
      >/dev/null 2>&1 &

# bump version in pubspec.yaml and commit
# versionCode = major*10000 + minor*100 + patch (e.g. 1.2.3 → 10203)
# Idempotent: safe to re-run after a partially-completed `ship` — it skips the
# edit/commit when the version is already bumped, so the pipeline can resume.
_bump ver:
    #!/usr/bin/env bash
    set -euo pipefail
    git pull --rebase --autostash origin master
    major=$(echo "{{ver}}" | cut -d. -f1)
    minor=$(echo "{{ver}}" | cut -d. -f2)
    patch=$(echo "{{ver}}" | cut -d. -f3)
    code=$((major * 10000 + minor * 100 + patch))
    target="version: {{ver}}+${code}"
    if [ "$(grep '^version: ' pubspec.yaml)" = "$target" ]; then
        echo "pubspec.yaml already at {{ver}}+${code}, skipping bump"
    else
        sed -i "s/^version: .*/${target}/" pubspec.yaml
    fi
    git add pubspec.yaml
    if git diff --cached --quiet; then
        echo "Nothing to commit — version {{ver}} already committed, resuming"
    else
        git commit -m "chore: bump version to {{ver}}"
    fi

# create Codeberg release and upload phone + watch APKs (assumes both built)
# usage: just release 1.0.0
release ver:
    #!/usr/bin/env bash
    set -euo pipefail
    # Push the bump commit first; let Codeberg create the tag together with the
    # release in one server-side call. This avoids the race where we push a tag
    # and immediately reference it before Codeberg has indexed it.
    git push origin HEAD:master
    # Skip creating the release if it already exists (e.g. a previous run got
    # this far before failing), so the pipeline can be resumed safely.
    # Capture the list first: piping straight into `grep -q` deadlocks against
    # `set -o pipefail` — grep closes the pipe on the first match, tea dies with
    # SIGPIPE (141), the pipeline returns non-zero, and the `if` wrongly takes
    # the "not found" branch → a bogus re-create that aborts the run.
    existing=$(tea releases list --remote origin --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
    if grep -qxF "v{{ver}}" <<<"$existing"; then
        echo "Release v{{ver}} already exists, skipping create"
    else
        tea releases create --remote origin --target master --tag v{{ver}} --title "v{{ver}}"
    fi
    # Upload both APKs to the one release. Phone + watch share an applicationId
    # but have distinct filenames (app-mobile/app-wear), so Obtainium picks the
    # right one via a filename regex. Skip an asset that's already up so a
    # resumed run doesn't duplicate it.
    for f in {{apk}} {{wear_apk}}; do
        name=$(basename "$f")
        assets=$(tea releases assets list --remote origin v{{ver}} --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
        if grep -qxF "$name" <<<"$assets"; then
            echo "Asset $name already uploaded, skipping"
        else
            tea releases assets create --remote origin v{{ver}} "$f"
        fi
    done
    # Sync the server-created tag back to the local repo.
    git fetch --tags origin

# Deletes uploaded artifacts (APKs) from every release older than the current
# minor series — tags, titles and notes stay, only the binaries are stripped.
# "Older" = a smaller major.minor than the newest release's, so the whole latest
# minor (e.g. all of v0.2.x) keeps its APKs while v0.1.x and earlier lose theirs.
# Irreversible on the server side.
# free Codeberg release-storage quota: strip artifacts from old releases
release-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    # Capture the list first (piping tea straight into a filter risks a pipefail
    # abort). tea's TSV wraps the notes body onto extra lines, so keep only real
    # vMAJOR.MINOR.PATCH tags. A high --limit grabs every release in one page.
    releases=$(tea releases list --remote origin --limit 50 --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
    tags=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$releases" || true)
    if [ -z "$tags" ]; then
        echo "No version releases found; nothing to clean."
        exit 0
    fi
    # Latest minor = the max (major, minor) across all tags.
    latest_major=-1; latest_minor=-1
    for tag in $tags; do
        v="${tag#v}"; major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
        if (( major > latest_major )) || { (( major == latest_major )) && (( minor > latest_minor )); }; then
            latest_major=$major; latest_minor=$minor
        fi
    done
    echo "Latest minor: v${latest_major}.${latest_minor}.x (kept). Stripping artifacts from older releases:"
    for tag in $tags; do
        v="${tag#v}"; major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
        # Keep the current minor (and anything newer); clean only older minors.
        if (( major > latest_major )) || { (( major == latest_major )) && (( minor >= latest_minor )); }; then
            continue
        fi
        mapfile -t assets < <(tea releases assets list --remote origin "$tag" --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
        if (( ${#assets[@]} == 0 )); then
            echo "  $tag: no artifacts"
            continue
        fi
        echo "  $tag: deleting ${assets[*]}"
        tea releases assets delete --remote origin -y "$tag" "${assets[@]}"
    done
    echo "Cleanup done."

# bump version, test, build and release — full pipeline
# usage: just ship 1.0.0
ship ver:
    just _bump {{ver}}
    just test
    just build
    just build-wear
    just release {{ver}}
