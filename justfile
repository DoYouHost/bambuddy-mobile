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
_bump ver:
    #!/usr/bin/env bash
    set -e
    git pull --rebase origin master
    major=$(echo "{{ver}}" | cut -d. -f1)
    minor=$(echo "{{ver}}" | cut -d. -f2)
    patch=$(echo "{{ver}}" | cut -d. -f3)
    code=$((major * 10000 + minor * 100 + patch))
    sed -i "s/^version: .*/version: {{ver}}+${code}/" pubspec.yaml
    git add pubspec.yaml
    git commit -m "chore: bump version to {{ver}}"

# create Codeberg release and upload APK (assumes APK already built)
# usage: just release 1.0.0
release ver:
    #!/usr/bin/env bash
    set -euo pipefail
    # Push the bump commit first; let Codeberg create the tag together with the
    # release in one server-side call. This avoids the race where we push a tag
    # and immediately reference it before Codeberg has indexed it.
    git push origin HEAD:master
    tea releases create --remote origin --target master --tag v{{ver}} --title "v{{ver}}"
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
