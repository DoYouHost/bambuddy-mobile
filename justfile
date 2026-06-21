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

# build and create a Codeberg release with APK attached
# usage: just release 1.0.0
release ver: build
    git tag v{{ver}}
    git push origin v{{ver}}
    tea releases create \
        --login codeberg.org \
        --repo {{repo}} \
        --tag v{{ver}} \
        --title "v{{ver}}"
    tea releases assets create \
        --login codeberg.org \
        --repo {{repo}} \
        v{{ver}} {{apk}}
