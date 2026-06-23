apk := "build/app/outputs/flutter-apk/app-release.apk"
repo := "MorganMLGman/bambuddy-mobile"

# show available commands
default:
    @just --list

# run tests
test:
    flutter test

# build release APK
build:
    flutter build apk --release

# clean build artifacts
clean:
    flutter clean

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

# create Codeberg release and upload APK (assumes APK already built)
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
    tea releases assets create --remote origin v{{ver}} {{apk}}
    # Sync the server-created tag back to the local repo.
    git fetch --tags origin

# bump version, test, build and release — full pipeline
# usage: just ship 1.0.0
ship ver:
    just _bump {{ver}}
    just test
    just build
    just release {{ver}}
