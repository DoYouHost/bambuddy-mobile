apk := "build/app/outputs/flutter-apk/app-mobile-release.apk"
wear_apk := "build/app/outputs/flutter-apk/app-wear-release.apk"
repo := "MorganMLGman/bambuddy-mobile"
# Shared headless GPU Android 14 emulator (TofuSadurki: lxc-docker-android).
emu := "192.168.2.208:5555"

# show available commands
default:
    @just --list

# run tests
test:
    flutter test

# build phone release APK (flavors force an explicit --flavor)
build:
    flutter build apk --release --flavor mobile

# build watch release APK (Wear OS entry point + wear flavor/manifest)
build-wear:
    flutter build apk --release --flavor wear --target lib/wear/main_wear.dart

# build Play Store bundles (AAB) for both flavors — Play accepts only AAB.
# Outputs: build/app/outputs/bundle/{mobileRelease,wearRelease}/
build-aab:
    flutter build appbundle --release --flavor mobile
    flutter build appbundle --release --flavor wear --target lib/wear/main_wear.dart

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
    if tea releases list --remote origin | grep -qw "v{{ver}}"; then
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
        if tea releases assets list --remote origin v{{ver}} 2>/dev/null | grep -qw "$name"; then
            echo "Asset $name already uploaded, skipping"
        else
            tea releases assets create --remote origin v{{ver}} "$f"
        fi
    done
    # Sync the server-created tag back to the local repo.
    git fetch --tags origin

# bump version, test, build and release — full pipeline
# usage: just ship 1.0.0
ship ver:
    just _bump {{ver}}
    just test
    just build
    just build-wear
    just release {{ver}}
