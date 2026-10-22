# Recipe naming: a bare verb is earned by the ones typed weekly and safe to run
# twice (test, run, build, ship); a variant appends only what differs from the
# silent defaults — phone, APK, stable channel (build-wear-aab, ship-dev).
# Machines and objects read <subject>-<verb> (emu-boot, release-publish).
# Anything irreversible on GitHub is purge-<deepest thing lost>, so
# `just purge<TAB>` enumerates every no-undo command and nothing else.
#
# The listed description is the [doc] attribute; without one just shows the last
# comment line. Attributes must touch the recipe line — a comment between them is
# `error: extraneous attribute` for the whole file. Groups are numbered so bare
# `just` (source order) and `just --list` (alphabetical) agree.

# Release artifacts live in build/dist (survives _clean-artifacts, which only
# wipes build/app) so the phone build isn't destroyed by the later watch build's
# clean — both flavors must coexist for `release-publish` to upload them together.
apk := "build/dist/app-mobile-release.apk"
wear_apk := "build/dist/app-wear-release.apk"
aab := "build/dist/app-mobile-release.aab"
wear_aab := "build/dist/app-wear-release.aab"
repo := "DoYouHost/bambuddy-mobile"

emulator_bin := "$HOME/Android/Sdk/emulator/emulator"
# Pixel 7, API 35. Every local recipe takes `avd=`; `just emu-list` shows the
# others (e.g. small360, a 360 dp narrow screen).
avd := "pixel35"

# Default watch AVD. The wear flavor needs its own recipe rather than an `avd=`
# on `run`: it is a different flavor AND a different entry point, and pointing
# the phone build at a watch installs an app whose UI does not fit the screen.
wear_avd := "wear_round"
# The newer watch the on-device tests also run on: dumpsys output and the system
# back gesture differ between Wear OS 5 and 6.
wear6_avd := "wear6_round"

[doc('show available commands')]
default:
    @just --list --unsorted

# ---- 1-develop — runs the app and the tests, publishes nothing ----

# Host tests, then — where this machine has adb and the emulator — the
# on-device ones: the phone's integration_test/ and the watch's patrol_test/ on
# both watch AVDs. A machine without them (CI, the Claude GitHub Action) runs
# the host half and says the rest was skipped; it never passes silently.
[doc('run unit and widget tests, plus on-device tests when an emulator is available')]
[group('1-develop')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    # Piped (ship, ship-dev, an agent) the default reporter prints a line per
    # test — ~5000 lines; this one prints failures and the summary.
    flutter test -r failures-only
    if ! command -v adb >/dev/null || [ ! -x "{{emulator_bin}}" ]; then
        echo "On-device tests SKIPPED: no adb or Android emulator on this machine." >&2
        exit 0
    fi
    patrol=$(command -v patrol || echo "$HOME/.pub-cache/bin/patrol")
    [ -x "$patrol" ] || { echo "patrol CLI missing: dart pub global activate patrol_cli" >&2; exit 1; }
    just test-device
    just _test-wear {{wear_avd}} "$patrol"
    just _test-wear {{wear6_avd}} "$patrol"

# patrol_test/ on one watch AVD. Patrol drives the app from inside, so the watch
# sees no user: it went to sleep (ungaze, ambient) and froze the test services'
# process, and sent a waiting permission dialog to the watch face after 60 s. An
# emulator has no wrist and no battery to save, so all three go.
_test-wear avd patrol:
    #!/usr/bin/env bash
    set -euo pipefail
    running=0
    just _emu-serial {{avd}} >/dev/null 2>&1 && running=1
    just emu-boot {{avd}} cold
    serial=$(just _emu-serial {{avd}})
    # Shut down only an AVD this run booted; one already running was opened by hand.
    if [ "$running" = 0 ]; then
        trap 'adb -s "$serial" emu kill >/dev/null 2>&1 || true' EXIT
    fi
    for setting in ambient_enabled=0 ungaze_sleep_enabled=0 wear_activity_auto_resume_timeout_ms=2147483647; do
        adb -s "$serial" shell settings put global "${setting%%=*}" "${setting#*=}"
    done
    adb -s "$serial" shell input keyevent KEYCODE_WAKEUP
    {{ quote(patrol) }} test -t patrol_test/wear_app_test.dart --flavor wear -d "$serial"

# The tests a host `flutter test` cannot run. Its binding replaces the HTTP
# client, so nothing there ever reads a byte off a socket — which is how a
# camera view that showed a spinner forever passed a green suite. These boot the
# AVD, serve an MJPEG stream from the device's own loopback and assert on what
# reaches the screen.
[doc('run the on-device integration tests (boots the AVD first)')]
[group('1-develop')]
test-device avd=avd:
    #!/usr/bin/env bash
    set -euo pipefail
    running=0
    just _emu-serial {{avd}} >/dev/null 2>&1 && running=1
    just emu-boot {{avd}} cold
    serial=$(just _emu-serial {{avd}})
    # Shut down only an AVD this run booted; one already running was opened by hand.
    if [ "$running" = 0 ]; then
        trap 'adb -s "$serial" emu kill >/dev/null 2>&1 || true' EXIT
    fi
    # One file per `flutter test`, each preceded by an install with -g. Android
    # 13+ gates notifications behind a runtime permission that no test can grant
    # for itself, and a run uninstalls the app when it ends — so a whole-folder
    # run reaches the notification file with the permission already gone. An
    # install with -g grants it, and the reinstall `flutter test` does on top is
    # an update, which keeps it.
    flutter build apk --debug --flavor mobile
    apk=build/app/outputs/flutter-apk/app-mobile-debug.apk
    failed=0
    # Without this an empty integration_test/ hands `flutter test` the pattern
    # itself, which fails as a missing file rather than as "nothing to run".
    shopt -s nullglob
    for file in integration_test/*_test.dart; do
        adb -s "$serial" install -r -g "$apk" >/dev/null
        flutter test "$file" -d "$serial" --flavor mobile || failed=1
    done
    exit $failed

# core.hooksPath is per-clone local config, so a fresh clone has no hooks until
# this runs. Points git at .githooks/, which holds the commit-message check.
[doc('point this clone at the versioned git hooks')]
[group('1-develop')]
hooks:
    git config core.hooksPath .githooks
    @echo "hooks: core.hooksPath = $(git config core.hooksPath)"

# What ships in the watch APK is decided by Gradle and the manifest merger, so
# no Dart test can see it: the per-flavor asset prune and the stripped startup
# components are both silent when they break. Checks the debug APK the compile
# step already produces; pass the phone one too and it also verifies the prune
# is flavor-scoped rather than global.
[doc('check the built watch APK: pruned assets and stripped components')]
[group('1-develop')]
check-wear-apk wear='build/app/outputs/flutter-apk/app-wear-debug.apk' mobile='':
    python3 tool/check_wear_apk.py {{wear}} {{ if mobile != '' { '--mobile ' + mobile } else { '' } }}

# Set LANGUAGETOOL_URL to a self-hosted instance to skip the public rate limit and
# keep the copy off someone else's server.
[doc('spell-check the .arb strings this branch changed')]
[group('1-develop')]
l10n-check base='dev':
    dart run app_guards:l10n_language --base {{base}}

[doc('spell-check every .arb string, not only this branch')]
[group('1-develop')]
l10n-check-all:
    dart run app_guards:l10n_language --all

# test/l10n/short_words_test.dart fails until this has run.
[doc('glue one-letter words to the next word in every .arb, then gen-l10n')]
[group('1-develop')]
l10n-glue:
    dart run app_guards:glue_short_words
    flutter gen-l10n

[doc('check translation status and missing keys against app_en.arb')]
[group('1-develop')]
l10n-status *args:
    dart run app_guards:l10n_sync {{args}}

# Boots the AVD first if needed, then builds, installs and runs with hot reload.
# This is the primary pre-commit verify loop.
[doc('run the app on a local AVD, booting it first')]
[group('1-develop')]
run avd=avd: (emu-boot avd)
    flutter run -d "$(just _emu-serial {{avd}})" --flavor mobile

# Same loop as `run`, for the watch: wear flavor, wear entry point.
[doc('run the watch app on a local Wear AVD, booting it first')]
[group('1-develop')]
run-wear avd=wear_avd: (emu-boot avd)
    flutter run -d "$(just _emu-serial {{avd}})" --flavor wear --target lib/wear/main_wear.dart

# ---- 2-emulator — boots the emulator and puts its screen on your desk ----

# An emulator takes whatever port is free, so the serial is looked up by name via
# `emu avd name` rather than assumed to be 5554.
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
# `cold` boots without loading the quickboot snapshot: the tests pass it, because
# a snapshot saved from a killed or half-booted run is what hangs the next boot.
# A boot that has not finished in EMU_BOOT_TIMEOUT seconds (default 180) is killed
# and tried again, up to three times; an emulator that hangs reads as `offline`
# in adb, and nothing waiting on it would ever give up.
[doc('boot a local AVD, retrying a hung boot, and wait for it to finish')]
[group('2-emulator')]
emu-boot avd=avd cold='':
    #!/usr/bin/env bash
    set -euo pipefail
    if serial=$(just _emu-serial {{avd}} 2>/dev/null); then
        echo "{{avd}} already running ($serial)"
        exit 0
    fi
    if ! "{{emulator_bin}}" -list-avds | grep -qx "{{avd}}"; then
        echo "No such AVD: {{avd}}. Available:" >&2
        just emu-list >&2
        exit 1
    fi
    flags=()
    [ "{{cold}}" = cold ] && flags+=(-no-snapshot-load)
    timeout_s=${EMU_BOOT_TIMEOUT:-180}
    attempts=3
    for attempt in $(seq 1 "$attempts"); do
        "{{emulator_bin}}" -avd {{avd}} "${flags[@]}" >/dev/null 2>&1 &
        pid=$!
        disown
        echo "Booting {{avd}}... (attempt $attempt of $attempts)"
        deadline=$((SECONDS + timeout_s))
        while [ "$SECONDS" -lt "$deadline" ]; do
            serial=$(timeout 20 just _emu-serial {{avd}} 2>/dev/null || true)
            if [ -n "${serial:-}" ] &&
                [ "$(timeout 10 adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
                echo "{{avd}} ready ($serial)"
                exit 0
            fi
            sleep 2
        done
        # SIGKILL, not a polite stop: a polite one lets a hung emulator save its
        # half-booted state as the next quickboot snapshot.
        echo "{{avd}} did not finish booting in ${timeout_s}s; killing it" >&2
        kill -9 "$pid" 2>/dev/null || true
        sleep 3
    done
    echo "{{avd}} did not boot after $attempts attempts" >&2
    exit 1

[doc('list local AVDs, marking which are running')]
[group('2-emulator')]
emu-list:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in $("{{emulator_bin}}" -list-avds); do
        serial=$(just _emu-serial "$name" 2>/dev/null || true)
        if [ -n "$serial" ]; then
            printf '  %-16s running   %s\n' "$name" "$serial"
        else
            printf '  %-16s stopped\n' "$name"
        fi
    done

# ---- 3-build — produces the bytes that get published ----
#
# All four build recipes take the same optional version pair, e.g.
# `just build-aab 0.12.1-dev.1 1200001`.

# Wipe build outputs + the Dart kernel snapshot so a release build can't pack a
# stale snapshot (incremental release builds here repeatably reused an outdated
# one — same code shipped, wrong bytes). Cheap insurance before any release build.
_clean-artifacts:
    rm -rf build/app .dart_tool/flutter_build

# The one implementation behind the four build recipes: resolve the version,
# announce it, clean, build one flavor, leave the artifact in build/dist under a
# fixed name.
#
# The version always reaches gradle explicitly. Without arguments it comes from
# pubspec.yaml, which is what a stable release wants (`ship` bumps it first);
# `ship-dev` passes its own, because a dev build deliberately leaves pubspec
# alone, and building from it silently produces the *previous* release again —
# that is what makes Play answer "version code already in use".
#
# Announced before the build so you see which version is going out before gradle
# spends a minute and a half on it, rather than after Play refuses the upload.
# That echo is also why fixed file names are enough: the artifact is a one-shot
# hand-off to the next step, and a bundle pair alone is ~157 MB.
_build kind flavor name code:
    #!/usr/bin/env bash
    set -euo pipefail
    name='{{name}}'
    code='{{code}}'
    # Both or neither: half a pair would build a version nobody asked for.
    if { [ -n "$name" ] && [ -z "$code" ]; } || { [ -z "$name" ] && [ -n "$code" ]; }; then
        echo "Pass both a name and a code, or neither." >&2
        exit 1
    fi
    if [ -z "$name" ]; then
        pubspec=$(grep '^version: ' pubspec.yaml | cut -d' ' -f2)
        name=${pubspec%%+*}
        code=${pubspec##*+}
    fi
    if [ '{{kind}}' = appbundle ]; then
        ext=aab
        src="build/app/outputs/bundle/{{flavor}}Release/app-{{flavor}}-release.aab"
    else
        ext=apk
        src="build/app/outputs/flutter-apk/app-{{flavor}}-release.apk"
    fi
    # if/then rather than `[ ... ] && x=y`, which under `set -e` aborts the
    # recipe on the mobile flavor instead of just skipping the assignment.
    target=()
    shown=$code
    if [ '{{flavor}}' = wear ]; then
        target=(--target lib/wear/main_wear.dart)
        # The watch code is a billion higher (see android/app/build.gradle.kts):
        # one listing, one applicationId, and Play needs the artifacts to differ.
        shown=$((code + 1000000000))
    fi
    echo "Building {{flavor}} $ext $name (versionCode $shown)"
    just _clean-artifacts
    flutter build {{kind}} --release --flavor {{flavor}} "${target[@]}" \
        --build-name="$name" --build-number="$code"
    mkdir -p build/dist
    cp "$src" "build/dist/app-{{flavor}}-release.$ext"
    # The watch APK is the one artifact whose contents nothing else checks, and
    # a release build is the only one that can answer the reachability half —
    # CI builds debug, where nothing has been tree-shaken yet. An .aab is a
    # different container, so it is left to the APK build.
    if [ '{{flavor}}' = wear ] && [ "$ext" = apk ]; then
        python3 tool/check_wear_apk.py "build/dist/app-wear-release.apk"
    fi
    echo "-> build/dist/app-{{flavor}}-release.$ext"

[doc('build the phone release APK')]
[group('3-build')]
build name='' code='': (_build "apk" "mobile" name code)

[doc('build the watch release APK')]
[group('3-build')]
build-wear name='' code='': (_build "apk" "wear" name code)

[doc('build the phone Play bundle')]
[group('3-build')]
build-aab name='' code='': (_build "appbundle" "mobile" name code)

[doc('build the watch Play bundle')]
[group('3-build')]
build-wear-aab name='' code='': (_build "appbundle" "wear" name code)

# Reads the manifest out of each bundle instead of echoing back what we handed
# to gradle: the flavor offset is applied on the gradle side, so what it baked in
# is the only number Play will judge — and a wrong one stays invisible until the
# upload is rejected. `play-internal` reads the same manifest before it uploads.
[doc('print the versions baked into the built Play bundles')]
[group('3-build')]
aab-show *paths:
    @dart run app_guards:aab_versions {{paths}}

# Read-only. Needs uv and the service-account key (tool/play.toml says where).
[doc('list the Google Play tracks and the releases on them')]
[group('3-build')]
play-tracks:
    @dart run app_guards:play tracks

[doc('delete local build outputs')]
[group('3-build')]
clean:
    flutter clean

# ---- 4-release — writes to the checked-out branch, to GitHub and to Google Play ----
#
# `ship` and `ship-dev` produce the same four artifacts in the same order; they
# differ only in where the version comes from. Both build the Play bundles
# *before* publishing the GitHub release, so a bundle that fails to build cannot
# leave a published release with nothing to promote.

# A release is cut from whatever is checked out: `_bump` commits here and
# `release-publish` pushes here, so shipping off `dev` leaves master alone. One
# definition for both, because a bump landing on a different branch than the
# push would publish a release without its own version commit.
[no-exit-message]
_branch:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! branch=$(git symbolic-ref --short -q HEAD); then
        echo "HEAD is detached — check out the branch you are releasing from." >&2
        exit 1
    fi
    echo "$branch"

# versionCode = (major*10000 + minor*100 + patch) * 20 + 2_000_000
# (e.g. 1.2.3 → 2_204_060). The *20 opens 19 slots under each release for
# `ship-dev` to number its builds into, so a dev build can never block the
# release it precedes; the busiest cycle so far used 8 of them.
#
# The + 2_000_000 is what makes the narrower multiplier safe. Up to 0.13.0 the
# multiplier was 1000, so the phone shipped 1_300_000 and the watch
# 1_001_300_000; going to *20 without the offset would hand the next release a
# LOWER code than installs already carry, which Play refuses to accept and
# Android refuses to install over. The offset lifts the series clear of that
# history — the next patch, 0.13.1, lands on 2_026_020.
#
# Flavors add their own offset on top of this, in android/app/build.gradle.kts.
# A band is ~20 M wide (major up to 99) and they are spaced 100 M apart:
#
#   mobile   +0                    2_000_000 ..    21_999_980
#   tv       +100_000_000        102_000_000 ..   121_999_980
#   (free)   +200_000_000        202_000_000 ..   221_999_980
#   wear     +1_000_000_000    1_002_000_000 .. 1_021_999_980
#
# wear sits a billion up because 1_001_300_000 is already published and cannot
# be moved down. That leaves 300 M..1_000 M and 1_022 M..2_100 M (Play's
# ceiling) empty — room for 17 more bands beyond the one reserved above.
[no-exit-message]
_version-code ver:
    #!/usr/bin/env bash
    set -euo pipefail
    ver={{ quote(ver) }}
    if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$ver"; then
        echo "Version must be X.Y.Z, got '$ver'." >&2
        exit 1
    fi
    IFS=. read -r major minor patch <<<"$ver"
    # 10# so a padded `08` is decimal eight and not an octal error.
    echo $(( (10#$major * 10000 + 10#$minor * 100 + 10#$patch) * 20 + 2000000 ))

# Idempotent: safe to re-run after a partially-completed `ship` — it skips the
# edit/commit when the version is already bumped, so the pipeline can resume.
_bump ver:
    #!/usr/bin/env bash
    set -euo pipefail
    code=$(just _version-code {{ quote(ver) }})
    branch=$(just _branch)
    # A branch that exists only here — the first release cut from it — has
    # nothing to rebase onto, and `git pull` would fail on the missing ref.
    # `--exit-code` says 2 for that and 128 for "could not reach origin": only
    # the first is a reason to skip the rebase, and swallowing the second would
    # build the release on a tree that never caught up with the remote.
    rc=0
    git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 || rc=$?
    case $rc in
        0) git pull --rebase --autostash origin "$branch" ;;
        2) echo "origin has no $branch yet — first release from this branch" ;;
        *) echo "Cannot read origin (git ls-remote exited $rc)." >&2; exit 1 ;;
    esac
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

# Upload the two APKs to one release, skipping any already attached so a resumed
# run cannot duplicate one. Two fixed files and never a variadic: the arity is
# what keeps the ~157 MB Play bundles off the GitHub release.
#
# Capture the asset list before filtering it: `gh ... | grep -q` deadlocks
# against `set -o pipefail` — grep closes the pipe on its first match, gh dies
# with SIGPIPE (141), and the `if` wrongly takes the "not found" branch.
[no-exit-message]
_upload-assets tag file_a file_b:
    #!/usr/bin/env bash
    set -euo pipefail
    tag={{ quote(tag) }}
    assets=$(gh release view "$tag" --repo {{repo}} --json assets --jq '.assets[].name')
    for f in {{ quote(file_a) }} {{ quote(file_b) }}; do
        name=$(basename "$f")
        if grep -qxF "$name" <<<"$assets"; then
            echo "Asset $name already uploaded, skipping"
        else
            gh release upload "$tag" --repo {{repo}} "$f"
        fi
    done

# Succeeds when a failed run only has the Play upload left: the release is
# tagged on HEAD, both APKs are attached to it, and the bundles in build/dist
# carry this versionName. A re-run then skips the tests and the four release
# builds instead of paying ~8 minutes for bytes it already has. The versionName
# is what ties the fixed-name bundles to this tag — any later build overwrites
# them with its own.
[no-exit-message]
_play-only tag name:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch --tags --quiet origin
    grep -qxF {{ quote(tag) }} <<<"$(git tag --points-at HEAD)"
    assets=$(gh release view {{ quote(tag) }} --repo {{repo}} --json assets --jq '.assets[].name' 2>/dev/null)
    grep -q '^app-mobile-.*\.apk$' <<<"$assets"
    grep -q '^app-wear-.*\.apk$' <<<"$assets"
    for f in {{aab}} {{wear_aab}}; do
        [ -f "$f" ]
        grep -qF " {{name}} " <<<"$(dart run app_guards:aab_versions "$f")"
    done

# Produces everything a stable version needs: APKs for the GitHub release (and
# Obtainium), plus both Play bundles released to internal testing. Promoting
# them to production stays a click in the Play Console.
[doc('bump, test, build and publish a stable release')]
[group('4-release')]
ship ver:
    #!/usr/bin/env bash
    set -euo pipefail
    just _bump {{ver}}
    if just _play-only "v{{ver}}" "{{ver}}" 2>/dev/null; then
        echo "v{{ver}} is published and its bundles are built — resuming at the Play upload"
    else
        just test
        just build
        just build-wear
        just build-aab
        just build-wear-aab
        just release-publish {{ver}}
    fi
    just play-internal

# Test, build both flavors and publish the current commit as a dev prerelease.
#
#   versionName  X.Y.Z-dev.N    versionCode  (X.Y.Z as in _version-code) - 20 + N
#
# X.Y.Z is the release this build is heading for (default: the next patch after
# the last tag) and N counts the dev builds of that target — so every dev build
# is above the last release and below the next one. Passing the whole
# `X.Y.Z-dev.N` pins N instead of counting it, as long as that slot is free.
#
# pubspec.yaml is not touched and nothing is committed: the version travels as a
# build flag, so the branch never carries a `-dev` version and the release
# points at a SHA. Obtainium hides prereleases by default, so a tester opts in with one
# switch and everyone else keeps seeing stable only.
#
# The Play bundles go out to internal testing as the last step; pass
# `bundles=no` when a build is only meant for Obtainium. The parameter is
# `bundles` and not `aab` because a parameter shadows the global of the same name
# for the whole recipe, which would expand `{{aab}}` to `yes`.
#
[doc('publish a dev prerelease from the current commit')]
[group('4-release')]
ship-dev target='' bundles='yes':
    #!/usr/bin/env bash
    set -euo pipefail
    # A dev release names a commit, so the build has to *be* that commit —
    # untracked files included, since a new .dart file compiles in whether or not
    # git knows about it.
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree is dirty; commit or stash before shipping a dev build." >&2
        exit 1
    fi
    # The counter is read off the dev tags, so a build published from another
    # machine has to be visible here or it gets its number handed out twice.
    git fetch --tags --quiet origin
    # --exclude, because --match takes a glob and not a regex: the trailing `*`
    # of the patch component happily swallows `-dev.3`, so without this the
    # second dev build of a cycle would measure itself against the first one.
    last=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-dev.*')
    base=${last#v}
    if [ "$(git rev-list --count "$last..HEAD")" -eq 0 ]; then
        echo "Nothing new since $last." >&2
        exit 1
    fi
    target='{{target}}'
    # The full dev version is accepted as well as the bare target, because that
    # is the string you have in hand — off the release page or the phone's about
    # screen — when you re-run a build. Its N then replaces the counter below.
    want_n=''
    case "$target" in
        *-dev.*)
            want_n=${target##*-dev.}
            target=${target%-dev.*}
            ;;
    esac
    if [ -z "$target" ]; then
        IFS=. read -r lmaj lmin lpat <<<"$base"
        target="$lmaj.$lmin.$((lpat + 1))"
    fi
    if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$target"; then
        echo "Target must be X.Y.Z or X.Y.Z-dev.N, got '{{target}}'." >&2
        exit 1
    fi
    if [ -n "$want_n" ]; then
        if ! grep -qE '^[0-9]+$' <<<"$want_n"; then
            echo "Dev number must be a number, got '{{target}}'." >&2
            exit 1
        fi
        # 10# so a padded `-dev.08` is decimal eight and not an octal error.
        want_n=$((10#$want_n))
    fi
    # The dev slots sit *under* the target, so a target at or below the last
    # release would hand out a versionCode the phone has already installed.
    # `sort -V` compares numerically (0.9.0 < 0.10.0, which sorting by text gets
    # backwards); the target loses when it sorts first.
    if [ "$(printf '%s\n%s\n' "$target" "$base" | sort -V | head -1)" = "$target" ]; then
        echo "Target $target is not newer than the last release $base." >&2
        exit 1
    fi
    # N counts dev builds of this target, so the first one is always dev.1 and
    # the sequence has no gaps. Read from the tags rather than kept in a file:
    # the tags are the record of what was published, and a counter on disk would
    # drift from them the first time a run failed halfway.
    #
    # `sed -n .../p` keeps only tags whose suffix really is a number, so a
    # hand-made `-dev.rc1` cannot silently count as zero.
    dev_n() { git tag "$@" --list "v$target-dev.*" | sed -n 's/.*-dev\.\([0-9]\+\)$/\1/p' | sort -n | tail -1; }
    # A dev tag already on this commit means an earlier run of this recipe got
    # as far as publishing it. Reuse it — same commit is the same build, and the
    # steps below skip whatever that run finished.
    n=$(dev_n --points-at HEAD)
    if [ -n "$want_n" ]; then
        # A number spelled out by hand may only name this commit's own build or a
        # free slot; taking another commit's would republish under its name.
        if [ -n "$n" ] && [ "$n" != "$want_n" ]; then
            echo "HEAD is already published as v$target-dev.$n, not dev.$want_n." >&2
            exit 1
        fi
        if [ -z "$n" ] && [ -n "$(git tag --list "v$target-dev.$want_n")" ]; then
            echo "v$target-dev.$want_n already exists on another commit." >&2
            exit 1
        fi
        n=$want_n
    elif [ -z "$n" ]; then
        highest=$(dev_n)
        n=$(( ${highest:-0} + 1 ))
    fi
    if [ "$n" -gt 19 ]; then
        echo "$n dev builds under $target — past the 19 slots. Ship a release." >&2
        exit 1
    fi
    code=$(( $(just _version-code "$target") - 20 + n ))
    name="$target-dev.$n"
    sha=$(git rev-parse HEAD)
    # The release is created around a commit, so the server needs it first. Said
    # rather than pushed: which branch a dev build comes off is the user's call.
    if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
        echo "HEAD is not on the remote yet. Push it first: git push origin HEAD" >&2
        exit 1
    fi
    echo "Dev build $name (versionCode $code) from ${sha:0:8}"
    tag="v$name"
    if [ '{{bundles}}' != 'no' ] && just _play-only "$tag" "$name" 2>/dev/null; then
        echo "$tag is published and its bundles are built — resuming at the Play upload"
        just play-internal
        exit 0
    fi
    just test
    just build "$name" "$code"
    just build-wear "$name" "$code"
    # Renamed only here: unlike the bundles, these APKs are published as release
    # assets a tester downloads, so the file has to say which build it holds.
    mv {{apk}} "build/dist/app-mobile-$name.apk"
    mv {{wear_apk}} "build/dist/app-wear-$name.apk"
    if [ '{{bundles}}' != 'no' ]; then
        just build-aab "$name" "$code"
        just build-wear-aab "$name" "$code"
    fi
    # Resumable like `release-publish`: skip whatever a failed earlier run did.
    if gh release view "$tag" --repo {{repo}} >/dev/null 2>&1; then
        echo "Release $tag already exists, skipping create"
    else
        # --generate-notes, unlike in `release-publish`: raw commit subjects are
        # exactly the changelog a dev channel wants. Play's own notes are the
        # handwritten ones, and internal testing does not ask for them at all.
        gh release create "$tag" --repo {{repo}} --target "$sha" \
            --title "$tag" --prerelease --generate-notes
    fi
    just _upload-assets "$tag" "build/dist/app-mobile-$name.apk" "build/dist/app-wear-$name.apk"
    git fetch --tags origin
    echo "Published $tag"
    if [ '{{bundles}}' != 'no' ]; then
        just play-internal
    fi

# Assumes both APKs are already built. Phone and watch share an applicationId but
# have distinct filenames (app-mobile/app-wear), so Obtainium picks the right one
# via a filename regex.
[doc('publish the GitHub release for an already-built version')]
[group('4-release')]
release-publish ver:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(just _branch)
    sha=$(git rev-parse HEAD)
    # Push the bump commit first; let GitHub create the tag together with the
    # release in one server-side call. This avoids the race where we push a tag
    # and immediately reference it before the server has indexed it.
    git push origin "HEAD:refs/heads/$branch"
    # Skip creating the release if it already exists (e.g. a previous run got
    # this far before failing), so the pipeline can be resumed safely.
    if gh release view "v{{ver}}" --repo {{repo}} >/dev/null 2>&1; then
        echo "Release v{{ver}} already exists, skipping create"
    else
        # Empty notes on purpose: the Play/Obtainium changelog is written by hand
        # afterwards, and --generate-notes would fill it with raw commit subjects.
        gh release create "v{{ver}}" --repo {{repo}} --target "$sha" \
            --title "v{{ver}}" --notes ""
    fi
    just _upload-assets "v{{ver}}" {{apk}} {{wear_apk}}
    # Sync the server-created tag back to the local repo.
    git fetch --tags origin

# Releases the two Play bundles in build/dist to internal testing, phone and
# watch in one edit. Safe to re-run: what is already on its track is skipped.
# Needs uv and the service-account key (tool/play.toml says where).
[doc('release the built Play bundles to internal testing')]
[group('4-release')]
play-internal *flags:
    dart run app_guards:play internal {{flags}} {{aab}} {{wear_aab}}

# ---- 5-danger — deletes what cannot be restored ----
#
# All three are irreversible on the server side, hence the preview + typed
# confirmation. Housekeeping: old releases stay findable without carrying
# binaries nobody installs.

# Echo the subset of `tags` older than or EQUAL to `cutoff`, in input order.
# `sort -V` orders versions numerically (v0.9.0 < v0.10.0, which a plain lexical
# sort gets backwards). A tag is doomed when it sorts first against the cutoff;
# the callers' contract is "VER and below", so equality is included. This
# predicate decides which releases get destroyed — do not grow a second copy.
[no-exit-message]
_at-or-below cutoff tags:
    #!/usr/bin/env bash
    set -euo pipefail
    # A `v` left on the cutoff sorts after every digit, so each tag came out
    # "at or below" it: `purge-releases v0.15.0` deleted every stable release.
    cutoff={{ quote(cutoff) }}
    cutoff=${cutoff#v}
    if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$cutoff"; then
        echo "Cutoff must be X.Y.Z, got '{{cutoff}}'." >&2
        exit 1
    fi
    tags={{ quote(tags) }}
    for tag in $tags; do
        v="${tag#v}"
        if [ "$(printf '%s\n%s\n' "$v" "$cutoff" | sort -V | head -1)" = "$v" ]; then
            echo "$tag"
        fi
    done

# Preview an irreversible list and demand a typed `yes`. The Keeping line (`all`
# minus `doomed`, in input order) is what catches an off-by-one in the cutoff
# before it executes.
#
# `printf ... $doomed` is deliberately unquoted: $doomed is a newline-separated
# blob and the word split is what puts one item per line.
#
# Call it as a bare statement — never `|| true`, never inside an `if`: the
# `exit 1` below IS the abort, and a caller that swallows it walks straight into
# the deletion loop.
[no-exit-message]
_confirm headline doomed all:
    #!/usr/bin/env bash
    set -euo pipefail
    doomed={{ quote(doomed) }}
    keeping=$({ grep -vxF -f <(printf '%s\n' $doomed) <<<{{ quote(all) }} || true; } | tr '\n' ' ')
    echo {{ quote(headline) }}
    printf '  %s\n' $doomed
    echo "Keeping: $keeping"
    read -r -p "Type 'yes' to confirm: " answer
    if [ "$answer" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi

# Without VER the cutoff is the current minor series: "older" = a smaller
# major.minor than the newest release's, so the whole latest minor (e.g. all of
# v0.2.x) keeps its APKs while v0.1.x and earlier lose theirs. With VER
# everything at or below that release is stripped, the newest minor included.
[doc('DELETE the APKs of old releases, releases and tags stay')]
[group('5-danger')]
purge-assets ver='':
    #!/usr/bin/env bash
    set -euo pipefail
    tags=$(gh release list --repo {{repo}} --limit 1000 --json tagName \
        --jq '.[].tagName | select(test("^v\\d+\\.\\d+\\.\\d+$"))')
    if [ -z "$tags" ]; then
        echo "No version releases found; nothing to clean."
        exit 0
    fi
    if [ -n "{{ver}}" ]; then
        doomed=$(just _at-or-below "{{ver}}" "$tags")
        if [ -z "$doomed" ]; then
            echo "No releases at or below v{{ver}}; nothing to clean."
            exit 0
        fi
        headline="About to strip artifacts from releases at or below v{{ver}} (irreversible; releases and tags stay):"
    else
        # The newest release's series (e.g. v0.2) is kept whole; nothing sorts
        # above it, so every other tag belongs to an older minor.
        series=$(sort -V <<<"$tags" | tail -1)
        series=${series%.*}
        doomed=$(for tag in $tags; do [[ $tag == "$series".* ]] || echo "$tag"; done)
        if [ -z "$doomed" ]; then
            echo "Only $series.x releases exist; nothing to clean."
            exit 0
        fi
        headline="Latest minor: $series.x (kept). About to strip artifacts from older releases (irreversible; releases and tags stay):"
    fi
    just _confirm "$headline" "$doomed" "$tags"
    for tag in $doomed; do
        mapfile -t assets < <(gh release view "$tag" --repo {{repo}} --json assets --jq '.assets[].name')
        if (( ${#assets[@]} == 0 )); then
            echo "  $tag: no artifacts"
            continue
        fi
        echo "  $tag: deleting ${assets[*]}"
        for name in "${assets[@]}"; do
            gh release delete-asset "$tag" "$name" --repo {{repo}} -y
        done
    done
    echo "Cleanup done."

# Deletes whole releases (entry, title, notes and artifacts), unlike
# purge-assets. Tags are kept, so history and `git describe` still work and a
# release can be recreated from one; pass --cleanup-tag to gh by hand if you
# really want the tags gone too.
[doc('DELETE whole releases at VER and below, tags stay')]
[group('5-danger')]
purge-releases ver:
    #!/usr/bin/env bash
    set -euo pipefail
    tags=$(gh release list --repo {{repo}} --limit 1000 --json tagName \
        --jq '.[].tagName | select(test("^v\\d+\\.\\d+\\.\\d+$"))')
    if [ -z "$tags" ]; then
        echo "No version releases found; nothing to purge."
        exit 0
    fi
    doomed=$(just _at-or-below "{{ver}}" "$tags")
    if [ -z "$doomed" ]; then
        echo "No releases at or below v{{ver}}; nothing to purge."
        exit 0
    fi
    just _confirm "About to DELETE these releases from GitHub (irreversible; tags stay):" "$doomed" "$tags"
    for tag in $doomed; do
        gh release delete "$tag" --repo {{repo}} -y
    done
    echo "Purged $(wc -l <<<"$doomed") releases."

# Keeps the newest KEEP dev prereleases and deletes the rest whole — release,
# notes, APKs and tag. The tags go too, unlike purge-assets and purge-releases: a
# dev tag marks a build nobody can install any more, and `git describe` picking
# one over the release it came after is actively misleading. Stable releases are
# unreachable from here — the pattern only matches -dev tags.
[doc('DELETE old dev prereleases and their tags')]
[group('5-danger')]
purge-dev-tags keep='5':
    #!/usr/bin/env bash
    set -euo pipefail
    # gh lists newest first, and that is the right order here: a dev build is
    # superseded by the next one, so "old" is positional rather than semantic —
    # no version sort to get wrong on a `-dev.10` vs `-dev.9`.
    devs=$(gh release list --repo {{repo}} --limit 1000 --json tagName \
        --jq '.[].tagName | select(test("^v\\d+\\.\\d+\\.\\d+-dev\\.\\d+$"))')
    if [ -z "$devs" ]; then
        echo "No dev prereleases; nothing to clean."
        exit 0
    fi
    doomed=$(tail -n +$(( {{keep}} + 1 )) <<<"$devs")
    if [ -z "$doomed" ]; then
        echo "Only $(wc -l <<<"$devs") dev prerelease(s), keeping {{keep}}; nothing to clean."
        exit 0
    fi
    just _confirm "About to DELETE these dev prereleases and their tags (irreversible):" "$doomed" "$devs"
    for tag in $doomed; do
        gh release delete "$tag" --repo {{repo}} --cleanup-tag -y
    done
    # Drop the local copies of the tags the server no longer has.
    git fetch --prune --prune-tags --tags origin
    echo "Purged $(wc -l <<<"$doomed") dev prereleases."
