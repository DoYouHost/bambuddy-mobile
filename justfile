# Release artifacts live in build/dist (survives _clean-artifacts, which only
# wipes build/app) so the phone build isn't destroyed by the later watch build's
# clean — both flavors must coexist for `release` to upload them together.
apk := "build/dist/app-mobile-release.apk"
wear_apk := "build/dist/app-wear-release.apk"
repo := "DoYouHost/bambuddy-mobile"
# Shared headless GPU Android 14 emulator (TofuSadurki: lxc-docker-android).
emu := "192.168.2.208:5555"
# Default local AVD (Pixel 7, API 35). Recipes below take an `avd=` argument, so
# `just emu-list` shows the alternatives (e.g. small360, a 360dp narrow screen).
# Serials are resolved by AVD name, not hardcoded — the port depends on boot order.
avd := "pixel35"

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

# list local AVDs, marking which are running and on which serial
emu-list:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in $("$HOME/Android/Sdk/emulator/emulator" -list-avds); do
        serial=$(just _emu-serial "$name" 2>/dev/null || true)
        if [ -n "$serial" ]; then
            printf '  %-16s running   %s\n' "$name" "$serial"
        else
            printf '  %-16s stopped\n' "$name"
        fi
    done

# print the adb serial of a running AVD (fails if it isn't running). An emulator
# takes whatever port is free, so the serial is looked up by name via `emu avd
# name` rather than assumed to be 5554.
_emu-serial avd:
    #!/usr/bin/env bash
    set -euo pipefail
    for serial in $(adb devices | awk '/^emulator-/ {print $1}'); do
        if [ "$(adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "{{avd}}" ]; then
            echo "$serial"
            exit 0
        fi
    done
    exit 1

# Idempotent (no-op if the AVD is already online); boots in the background and
# blocks until Android finishes booting, so local recipes can depend on it.
# boot a local AVD (default: pixel35) — `just emu-local small360`
emu-local avd=avd:
    #!/usr/bin/env bash
    set -euo pipefail
    if serial=$(just _emu-serial {{avd}} 2>/dev/null); then
        echo "{{avd}} already running ($serial)"
        exit 0
    fi
    if ! "$HOME/Android/Sdk/emulator/emulator" -list-avds | grep -qx "{{avd}}"; then
        echo "No such AVD: {{avd}}. Available:" >&2
        just emu-list >&2
        exit 1
    fi
    "$HOME/Android/Sdk/emulator/emulator" -avd {{avd}} >/dev/null 2>&1 &
    disown
    echo "Booting {{avd}}..."
    for _ in $(seq 1 60); do
        serial=$(just _emu-serial {{avd}} 2>/dev/null || true)
        [ -n "${serial:-}" ] && break
        sleep 2
    done
    [ -n "${serial:-}" ] || { echo "{{avd}} did not come up" >&2; exit 1; }
    adb -s "$serial" wait-for-device
    until [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
        sleep 2
    done
    echo "{{avd}} ready ($serial)"

# Boots the emulator first if needed; builds, installs and runs with hot reload.
# This is the primary pre-commit verify loop.
# run the app (debug) on a local AVD (default: pixel35) — `just dev-local small360`
dev-local avd=avd: (emu-local avd)
    #!/usr/bin/env bash
    set -euo pipefail
    flutter run -d "$(just _emu-serial {{avd}})" --flavor mobile

# run integration tests on a local AVD (default: pixel35; boots it first if needed)
itest-local avd=avd: (emu-local avd)
    #!/usr/bin/env bash
    set -euo pipefail
    flutter test integration_test/ --flavor mobile -d "$(just _emu-serial {{avd}})"

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

# Deletes uploaded artifacts (APKs) from old releases — tags, titles and notes
# stay, only the binaries are stripped. Without VER the cutoff is the current
# minor series: "older" = a smaller major.minor than the newest release's, so the
# whole latest minor (e.g. all of v0.2.x) keeps its APKs while v0.1.x and earlier
# lose theirs. With VER (like release-purge) everything at or below that release
# is stripped, the newest minor included.
# Irreversible on the server side.
# free Codeberg release-storage quota: strip artifacts from old releases
# usage: just release-cleanup [0.9.0]
release-cleanup ver='':
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
    if [ -n "{{ver}}" ]; then
        # `sort -V` orders versions numerically (v0.9.0 < v0.10.0, which a plain
        # lexical sort gets backwards). A tag is doomed when it sorts first
        # against the cutoff — i.e. it is older than or equal to it.
        doomed=$(for tag in $tags; do
            v="${tag#v}"
            if [ "$(printf '%s\n%s\n' "$v" "{{ver}}" | sort -V | head -1)" = "$v" ]; then
                echo "$tag"
            fi
        done)
        if [ -z "$doomed" ]; then
            echo "No releases at or below v{{ver}}; nothing to clean."
            exit 0
        fi
        echo "About to strip artifacts from releases at or below v{{ver}} (irreversible; releases and tags stay):"
    else
        # Latest minor = the max (major, minor) across all tags.
        latest_major=-1; latest_minor=-1
        for tag in $tags; do
            v="${tag#v}"; major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
            if (( major > latest_major )) || { (( major == latest_major )) && (( minor > latest_minor )); }; then
                latest_major=$major; latest_minor=$minor
            fi
        done
        # Keep the current minor (and anything newer); clean only older minors.
        doomed=$(for tag in $tags; do
            v="${tag#v}"; major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
            if (( major < latest_major )) || { (( major == latest_major )) && (( minor < latest_minor )); }; then
                echo "$tag"
            fi
        done)
        if [ -z "$doomed" ]; then
            echo "Only v${latest_major}.${latest_minor}.x releases exist; nothing to clean."
            exit 0
        fi
        echo "Latest minor: v${latest_major}.${latest_minor}.x (kept). About to strip artifacts from older releases (irreversible; releases and tags stay):"
    fi
    printf '  %s\n' $doomed
    echo "Keeping: $(comm -23 <(sort <<<"$tags") <(sort <<<"$doomed") | tr '\n' ' ')"
    read -r -p "Type 'yes' to confirm: " answer
    if [ "$answer" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
    for tag in $doomed; do
        mapfile -t assets < <(tea releases assets list --remote origin "$tag" --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
        if (( ${#assets[@]} == 0 )); then
            echo "  $tag: no artifacts"
            continue
        fi
        echo "  $tag: deleting ${assets[*]}"
        tea releases assets delete --remote origin -y "$tag" "${assets[@]}"
    done
    echo "Cleanup done."

# Deletes whole releases (entry, title, notes and artifacts) at VER and below —
# unlike release-cleanup, which only strips artifacts. Tags are kept, so history
# and `git describe` still work, and a release can be recreated from one; pass
# --delete-tag to tea by hand if you really want the tags gone too.
# Irreversible on the server side, hence the preview + typed confirmation.
# delete whole releases from VER downwards: just release-purge 0.9.0
release-purge ver:
    #!/usr/bin/env bash
    set -euo pipefail
    # Capture first (piping tea straight into a filter risks a pipefail abort);
    # tea's TSV wraps notes onto extra lines, so keep only real version tags.
    releases=$(tea releases list --remote origin --limit 100 --output tsv 2>/dev/null | awk -F'\t' 'NR>1 {print $1}')
    tags=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$releases" || true)
    if [ -z "$tags" ]; then
        echo "No version releases found; nothing to purge."
        exit 0
    fi
    # `sort -V` orders versions numerically (v0.9.0 < v0.10.0, which a plain
    # lexical sort gets backwards). A tag is doomed when it sorts first against
    # the cutoff — i.e. it is older than or equal to it.
    doomed=$(for tag in $tags; do
        v="${tag#v}"
        if [ "$(printf '%s\n%s\n' "$v" "{{ver}}" | sort -V | head -1)" = "$v" ]; then
            echo "$tag"
        fi
    done)
    if [ -z "$doomed" ]; then
        echo "No releases at or below v{{ver}}; nothing to purge."
        exit 0
    fi
    echo "About to DELETE these releases from Codeberg (irreversible; tags stay):"
    printf '  %s\n' $doomed
    echo "Keeping: $(comm -23 <(sort <<<"$tags") <(sort <<<"$doomed") | tr '\n' ' ')"
    read -r -p "Type 'yes' to confirm: " answer
    if [ "$answer" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
    tea releases delete --remote origin -y $doomed
    echo "Purged $(wc -l <<<"$doomed") releases."

# bump version, test, build and release — full pipeline
# usage: just ship 1.0.0
ship ver:
    just _bump {{ver}}
    just test
    just build
    just build-wear
    just release {{ver}}
