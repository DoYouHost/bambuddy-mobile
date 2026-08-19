# Recipe naming: a bare verb is earned by the ones typed weekly and safe to run
# twice (test, run, build, ship); a variant appends only what differs from the
# silent defaults — phone, APK, stable channel, this machine (build-wear-aab,
# run-remote). Machines and objects read <subject>-<verb> (emu-boot,
# release-publish). Anything irreversible on GitHub is purge-<deepest thing lost>,
# so `just purge<TAB>` enumerates every no-undo command and nothing else.
#
# The listed description is the [doc] attribute, not the comment above it: just
# shows only the LAST comment line, which is how half this file used to advertise
# itself as "usage: …". Attributes must touch the recipe line — a comment between
# them is `error: extraneous attribute`, and it breaks the whole file, not one
# recipe. Group names are numbered because bare `just` (via --unsorted) reads in
# source order while `just --list` re-sorts alphabetically; the digits are what
# keep the two agreeing, and the cleanup ladder readable.

# Release artifacts live in build/dist (survives _clean-artifacts, which only
# wipes build/app) so the phone build isn't destroyed by the later watch build's
# clean — both flavors must coexist for `release-publish` to upload them together.
apk := "build/dist/app-mobile-release.apk"
wear_apk := "build/dist/app-wear-release.apk"
aab := "build/dist/app-mobile-release.aab"
wear_aab := "build/dist/app-wear-release.aab"
repo := "DoYouHost/bambuddy-mobile"

# Shared headless GPU Android 14 emulator (TofuSadurki: lxc-docker-android).
emu_host := "192.168.2.208"
emu := emu_host + ":5555"
emu_web := "http://" + emu_host + ":8000"
emulator_bin := "$HOME/Android/Sdk/emulator/emulator"
# Default local AVD (Pixel 7, API 35). Every local recipe takes an `avd=`
# argument, so `just emu-list` shows the alternatives (e.g. small360, a 360dp
# narrow screen). Serials are resolved by AVD name, not hardcoded — the port
# depends on boot order.
avd := "pixel35"

[doc('show available commands')]
default:
    @just --list --unsorted

# ---- 1-develop — runs the app and the tests, publishes nothing ----

[doc('run unit and widget tests')]
[group('1-develop')]
test:
    flutter test

# Boots the AVD first if needed, then builds, installs and runs with hot reload.
# This is the primary pre-commit verify loop.
# usage: just run [AVD]
[doc('run the app on a local AVD, booting it first')]
[group('1-develop')]
run avd=avd: (emu-boot avd)
    #!/usr/bin/env bash
    set -euo pipefail
    flutter run -d "$(just _emu-serial {{avd}})" --flavor mobile

[doc('run the app on the shared LAN emulator')]
[group('1-develop')]
run-remote: emu-connect
    flutter run -d {{emu}} --flavor mobile

# usage: just test-integration [AVD]
[doc('run integration tests on a local AVD')]
[group('1-develop')]
test-integration avd=avd: (emu-boot avd)
    #!/usr/bin/env bash
    set -euo pipefail
    flutter test integration_test/ --flavor mobile -d "$(just _emu-serial {{avd}})"

[doc('run integration tests on the shared LAN emulator')]
[group('1-develop')]
test-integration-remote: emu-connect
    flutter test integration_test/ --flavor mobile

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
# usage: just emu-boot [AVD]
[doc('boot a local AVD and wait for it to finish booting')]
[group('2-emulator')]
emu-boot avd=avd:
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
    "{{emulator_bin}}" -avd {{avd}} >/dev/null 2>&1 &
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

[doc('adb connect to the shared LAN emulator')]
[group('2-emulator')]
emu-connect:
    adb connect {{emu}}

# ws-scrcpy deep-link skips the device list (MSE player, fixed scrcpy port 8886,
# stable across restarts). URL is single-quoted so the shell keeps the &/#/%.
# A dedicated --user-data-dir forces a separate Chrome instance so --window-size
# is actually honored (a window in an already-running Chrome ignores size flags).
[doc('open the shared emulator screen in a browser window')]
[group('2-emulator')]
emu-view:
    flatpak run com.google.Chrome \
      --user-data-dir="$HOME/.config/chrome-emu" --no-first-run --no-default-browser-check \
      --window-size=500,1000 \
      --app='{{emu_web}}/#!action=stream&udid=android-emulator%3A5555&player=mse&ws=ws%3A%2F%2F{{emu_host}}%3A8000%2F%3Faction%3Dproxy-adb%26remote%3Dtcp%253A8886%26udid%3Dandroid-emulator%253A5555' \
      >/dev/null 2>&1 &

# Opens the device list in emu-view's own Chrome profile so that "Fit to screen"
# + Save persists there (localStorage, per player=mse). Configure -> keep Fit to
# screen ON -> Save, and `just emu-view` picks it up afterwards.
[doc('one-time Chrome profile setup that emu-view reuses')]
[group('2-emulator')]
emu-view-setup:
    flatpak run com.google.Chrome \
      --user-data-dir="$HOME/.config/chrome-emu" --no-first-run --no-default-browser-check \
      --app='{{emu_web}}' >/dev/null 2>&1 &

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

[doc('delete local build outputs')]
[group('3-build')]
clean:
    flutter clean

# ---- 4-release — writes to master and to GitHub ----
#
# `ship` and `ship-dev` produce the same four artifacts in the same order; they
# differ only in where the version comes from. Both build the Play bundles
# *before* publishing the GitHub release, so a bundle that fails to build cannot
# leave a published release with nothing to promote.

# versionCode = (major*10000 + minor*100 + patch) * 1000 (e.g. 1.2.3 → 10203000).
# The trailing three zeros are the dev slots `ship-dev` numbers its builds into,
# so a dev build can never block the release it precedes. The old bare
# major*10000+minor*100+patch left no integer at all between two patches.
#
# Idempotent: safe to re-run after a partially-completed `ship` — it skips the
# edit/commit when the version is already bumped, so the pipeline can resume.
_bump ver:
    #!/usr/bin/env bash
    set -euo pipefail
    git pull --rebase --autostash origin master
    major=$(echo "{{ver}}" | cut -d. -f1)
    minor=$(echo "{{ver}}" | cut -d. -f2)
    patch=$(echo "{{ver}}" | cut -d. -f3)
    code=$(((major * 10000 + minor * 100 + patch) * 1000))
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

# Produces everything a stable version needs: APKs for the GitHub release (and
# Obtainium), plus both Play bundles in build/dist/, which you upload to Play by
# hand.
# usage: just ship X.Y.Z
[doc('bump, test, build and publish a stable release')]
[group('4-release')]
ship ver:
    just _bump {{ver}}
    just test
    just build
    just build-wear
    just build-aab
    just build-wear-aab
    just release-publish {{ver}}

# Test, build both flavors and publish the current commit as a dev prerelease.
#
#   versionName  X.Y.Z-dev.N    versionCode  (X.Y.Z as in _bump) - 1000 + N
#
# X.Y.Z is the release this build is heading for (default: the next patch after
# the last tag) and N counts the dev builds of that target — so every dev build
# is above the last release and below the next one. Passing the whole
# `X.Y.Z-dev.N` pins N instead of counting it, as long as that slot is free.
#
# pubspec.yaml is not touched and nothing is committed: the version travels as a
# build flag, so master never carries a `-dev` version and the release points at
# a SHA. Obtainium hides prereleases by default, so a tester opts in with one
# switch and everyone else keeps seeing stable only.
#
# The Play bundles stay in build/dist/ for the internal testing track; pass
# `bundles=no` when a build is only meant for Obtainium. The parameter is
# `bundles` and not `aab` because a parameter shadows the global of the same name
# for the whole recipe, which would expand `{{aab}}` to `yes`.
#
# usage: just ship-dev [X.Y.Z | X.Y.Z-dev.N] [bundles=yes|no]
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
    if [ "$n" -gt 999 ]; then
        echo "$n dev builds under $target — past the 999 slots. Ship a release." >&2
        exit 1
    fi
    maj=$(cut -d. -f1 <<<"$target")
    min=$(cut -d. -f2 <<<"$target")
    pat=$(cut -d. -f3 <<<"$target")
    code=$(( (maj * 10000 + min * 100 + pat) * 1000 - 1000 + n ))
    name="$target-dev.$n"
    sha=$(git rev-parse HEAD)
    # The release is created around a commit, so the server needs it first. Said
    # rather than pushed: which branch a dev build comes off is the user's call.
    if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
        echo "HEAD is not on the remote yet. Push it first: git push origin HEAD" >&2
        exit 1
    fi
    echo "Dev build $name (versionCode $code) from ${sha:0:8}"
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
    tag="v$name"
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
        echo "Upload to Play internal testing ($name):"
        ls -1 {{aab}} {{wear_aab}}
    fi

# Assumes both APKs are already built. Phone and watch share an applicationId but
# have distinct filenames (app-mobile/app-wear), so Obtainium picks the right one
# via a filename regex.
# usage: just release-publish X.Y.Z
[doc('publish the GitHub release for an already-built version')]
[group('4-release')]
release-publish ver:
    #!/usr/bin/env bash
    set -euo pipefail
    # Push the bump commit first; let GitHub create the tag together with the
    # release in one server-side call. This avoids the race where we push a tag
    # and immediately reference it before the server has indexed it.
    git push origin HEAD:master
    # Skip creating the release if it already exists (e.g. a previous run got
    # this far before failing), so the pipeline can be resumed safely.
    if gh release view "v{{ver}}" --repo {{repo}} >/dev/null 2>&1; then
        echo "Release v{{ver}} already exists, skipping create"
    else
        # Empty notes on purpose: the Play/Obtainium changelog is written by hand
        # afterwards, and --generate-notes would fill it with raw commit subjects.
        gh release create "v{{ver}}" --repo {{repo}} --target master \
            --title "v{{ver}}" --notes ""
    fi
    just _upload-assets "v{{ver}}" {{apk}} {{wear_apk}}
    # Sync the server-created tag back to the local repo.
    git fetch --tags origin

# ---- 5-danger — deletes what cannot be restored ----
#
# All three are irreversible on the server side, hence the preview + typed
# confirmation. The original driver was Codeberg's release storage quota, which
# GitHub does not impose; what is left is housekeeping, so old releases stay
# findable without carrying binaries nobody installs.

# Echo the subset of `tags` older than or EQUAL to `cutoff`, in input order.
# `sort -V` orders versions numerically (v0.9.0 < v0.10.0, which a plain lexical
# sort gets backwards). A tag is doomed when it sorts first against the cutoff;
# the callers' contract is "VER and below", so equality is included. This
# predicate decides which releases get destroyed — do not grow a second copy.
[no-exit-message]
_at-or-below cutoff tags:
    #!/usr/bin/env bash
    set -euo pipefail
    cutoff={{ quote(cutoff) }}
    tags={{ quote(tags) }}
    for tag in $tags; do
        v="${tag#v}"
        if [ "$(printf '%s\n%s\n' "$v" "$cutoff" | sort -V | head -1)" = "$v" ]; then
            echo "$tag"
        fi
    done

# Preview an irreversible list and demand a typed `yes`. The Keeping line is what
# catches an off-by-one in the cutoff before it executes.
#
# `printf ... $doomed` is deliberately unquoted: $doomed is a newline-separated
# blob and the word split is what puts one item per line.
#
# Call it as a bare statement — never `|| true`, never inside an `if`: the
# `exit 1` below IS the abort, and a caller that swallows it walks straight into
# the deletion loop.
[no-exit-message]
_confirm headline doomed keeping:
    #!/usr/bin/env bash
    set -euo pipefail
    doomed={{ quote(doomed) }}
    keeping={{ quote(keeping) }}
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
# usage: just purge-assets [X.Y.Z]
[doc('DELETE the APKs of old releases, releases and tags stay')]
[group('5-danger')]
purge-assets ver='':
    #!/usr/bin/env bash
    set -euo pipefail
    # Capture the list first (piping gh straight into a filter risks a pipefail
    # abort). Keep only real vMAJOR.MINOR.PATCH tags; a high --limit grabs every
    # release in one page.
    releases=$(gh release list --repo {{repo}} --limit 50 --json tagName --jq '.[].tagName')
    tags=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$releases" || true)
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
        headline="Latest minor: v${latest_major}.${latest_minor}.x (kept). About to strip artifacts from older releases (irreversible; releases and tags stay):"
    fi
    just _confirm "$headline" "$doomed" "$(comm -23 <(sort <<<"$tags") <(sort <<<"$doomed") | tr '\n' ' ')"
    for tag in $doomed; do
        mapfile -t assets < <(gh release view "$tag" --repo {{repo}} --json assets --jq '.assets[].name')
        if (( ${#assets[@]} == 0 )); then
            echo "  $tag: no artifacts"
            continue
        fi
        echo "  $tag: deleting ${assets[*]}"
        # One call per asset: gh takes a single asset name, unlike tea.
        for name in "${assets[@]}"; do
            gh release delete-asset "$tag" "$name" --repo {{repo}} -y
        done
    done
    echo "Cleanup done."

# Deletes whole releases (entry, title, notes and artifacts), unlike
# purge-assets. Tags are kept, so history and `git describe` still work and a
# release can be recreated from one; pass --cleanup-tag to gh by hand if you
# really want the tags gone too.
# usage: just purge-releases X.Y.Z
[doc('DELETE whole releases at VER and below, tags stay')]
[group('5-danger')]
purge-releases ver:
    #!/usr/bin/env bash
    set -euo pipefail
    # Capture first (piping gh straight into a filter risks a pipefail abort);
    # keep only real version tags.
    releases=$(gh release list --repo {{repo}} --limit 100 --json tagName --jq '.[].tagName')
    tags=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$releases" || true)
    if [ -z "$tags" ]; then
        echo "No version releases found; nothing to purge."
        exit 0
    fi
    doomed=$(just _at-or-below "{{ver}}" "$tags")
    if [ -z "$doomed" ]; then
        echo "No releases at or below v{{ver}}; nothing to purge."
        exit 0
    fi
    just _confirm "About to DELETE these releases from GitHub (irreversible; tags stay):" "$doomed" \
        "$(comm -23 <(sort <<<"$tags") <(sort <<<"$doomed") | tr '\n' ' ')"
    # One call per release: gh deletes a single tag, unlike tea.
    for tag in $doomed; do
        gh release delete "$tag" --repo {{repo}} -y
    done
    echo "Purged $(wc -l <<<"$doomed") releases."

# Keeps the newest KEEP dev prereleases and deletes the rest whole — release,
# notes, APKs and tag. The tags go too, unlike purge-assets and purge-releases: a
# dev tag marks a build nobody can install any more, and `git describe` picking
# one over the release it came after is actively misleading. Stable releases are
# unreachable from here — the pattern only matches -dev tags.
# usage: just purge-dev-tags [KEEP]
[doc('DELETE old dev prereleases and their tags')]
[group('5-danger')]
purge-dev-tags keep='5':
    #!/usr/bin/env bash
    set -euo pipefail
    # gh lists newest first, and that is the right order here: a dev build is
    # superseded by the next one, so "old" is positional rather than semantic —
    # no version sort to get wrong on a `-dev.10` vs `-dev.9`.
    releases=$(gh release list --repo {{repo}} --limit 100 --json tagName --jq '.[].tagName')
    devs=$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9]+$' <<<"$releases" || true)
    if [ -z "$devs" ]; then
        echo "No dev prereleases; nothing to clean."
        exit 0
    fi
    doomed=$(tail -n +$(( {{keep}} + 1 )) <<<"$devs")
    if [ -z "$doomed" ]; then
        echo "Only $(wc -l <<<"$devs") dev prerelease(s), keeping {{keep}}; nothing to clean."
        exit 0
    fi
    just _confirm "About to DELETE these dev prereleases and their tags (irreversible):" "$doomed" \
        "$(head -n {{keep}} <<<"$devs" | tr '\n' ' ')"
    for tag in $doomed; do
        gh release delete "$tag" --repo {{repo}} --cleanup-tag -y
    done
    # Drop the local copies of the tags the server no longer has.
    git fetch --prune --prune-tags --tags origin
    echo "Purged $(wc -l <<<"$doomed") dev prereleases."
