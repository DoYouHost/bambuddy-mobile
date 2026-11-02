#!/usr/bin/env bash
# Retakes docs/store-assets/screenshots/ from release builds, so no DEBUG banner,
# on the AVDs the published set was taken on. The app runs the demo backend and
# reaches each screen through Flutter's built-in deep links
# (`-d bambuddy://open/<route>` on an explicit intent); what has no route of its
# own (the demo login, a spool's sheet, the watch) is tapped by its accessibility
# label from `uiautomator dump`, never by coordinates.
#
#   tool/store_screenshots.sh [phone|tablet7|tablet10|wear|all] [--no-build]
#
# Everything the run changes on an AVD is put back when it ends, a failed step
# included: the app is uninstalled, the status bar leaves demo mode, the rotation
# returns, and an AVD this run booted is shut down. The app's language is set per
# app (`cmd locale set-app-locales`), not system-wide.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=page.codeberg.morganmlgman.bambuddy_mobile
OUT=docs/store-assets/screenshots
WHICH=${1:-all}
BUILD=yes
[ "${2:-}" = --no-build ] || [ "${1:-}" = --no-build ] && BUILD=no
[ "$WHICH" = --no-build ] && WHICH=all
SERIAL=
# What the current AVD looked like before the run, for [restore].
BOOTED_HERE=no SYSUI_BEFORE= ROT_BEFORE= ACC_BEFORE= RESIZED=no

adb_() { adb -s "$SERIAL" "$@"; }

# Puts the current AVD back as it was found; also runs when a step fails.
restore() {
  [ -n "$SERIAL" ] || return 0
  adb_ uninstall "$PKG" >/dev/null 2>&1 || true
  if [ -n "$SYSUI_BEFORE" ]; then
    adb_ shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
    adb_ shell settings put global sysui_demo_allowed "$SYSUI_BEFORE" >/dev/null 2>&1 || true
  fi
  [ -n "$ROT_BEFORE" ] && adb_ shell settings put system user_rotation "$ROT_BEFORE" >/dev/null 2>&1
  [ -n "$ACC_BEFORE" ] && adb_ shell settings put system accelerometer_rotation "$ACC_BEFORE" >/dev/null 2>&1
  [ "$RESIZED" = yes ] && adb_ shell wm size reset >/dev/null 2>&1
  [ "$BOOTED_HERE" = yes ] && adb_ emu kill >/dev/null 2>&1
  SERIAL= BOOTED_HERE=no SYSUI_BEFORE= ROT_BEFORE= ACC_BEFORE= RESIZED=no
  return 0
}
trap restore EXIT

# Centre of the smallest node whose content-desc or text matches the regex, or
# nothing. Smallest, because Flutter repeats a child's label in its ancestors'.
find_node() {
  adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 0
  adb_ exec-out cat /sdcard/ui.xml | python3 -I -c '
import re, sys, xml.etree.ElementTree as ET
pattern = re.compile(sys.argv[1], re.S)
best = None
for node in ET.fromstring(sys.stdin.read()).iter("node"):
    label = node.get("content-desc") or node.get("text") or ""
    if not pattern.search(label):
        continue
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
    area = (x2 - x1) * (y2 - y1)
    if area and (best is None or area < best[0]):
        best = (area, (x1 + x2) // 2, (y1 + y2) // 2)
if best:
    print(best[1], best[2])
' "$1"
}

# Waits for a label, scrolling down between looks when asked to.
wait_label() {
  local pattern=$1 scroll=${2:-no} at
  for _ in $(seq 1 20); do
    at=$(find_node "$pattern")
    [ -n "$at" ] && { echo "$at"; return 0; }
    [ "$scroll" = scroll ] && swipe_up 30 || sleep 1
  done
  echo "not on screen: $pattern" >&2
  return 1
}

tap_label() {
  local at
  at=$(wait_label "$@")
  adb_ shell input tap $at
  sleep 1.5
}

# Taps it only when it is there: first-run prompts that may or may not show.
tap_if_shown() {
  local at
  at=$(find_node "$1")
  [ -n "$at" ] && adb_ shell input tap $at && sleep 1.5
  return 0
}

screen_size() { adb_ shell wm size | awk -F'[ x]' '/size/{w=$(NF-1); h=$NF} END{print w, h}'; }

# Drags the content up by a share of the screen height.
swipe_up() {
  local w h
  read -r w h < <(screen_size)
  adb_ shell input swipe $((w / 2)) $((h * 3 / 4)) $((w / 2)) $((h * 3 / 4 - h * $1 / 100)) 600
  sleep 1
}

open_route() {
  adb_ shell am start -n "$PKG/.MainActivity" -d "bambuddy://open$1" >/dev/null
  sleep 3
}

shot() {
  mkdir -p "$OUT/$1"
  # The watch's scroll bar fades a moment after the last scroll.
  [ "$1" = wear ] && sleep 2
  adb_ exec-out screencap -p >"$OUT/$1/$2.png"
  echo "  $OUT/$1/$2.png"
}

status_bar_demo() {
  adb_ shell settings put global sysui_demo_allowed 1
  local b="am broadcast -a com.android.systemui.demo -e command"
  adb_ shell "$b enter" >/dev/null
  adb_ shell "$b clock -e hhmm 1200" >/dev/null
  adb_ shell "$b battery -e level 100 -e plugged false" >/dev/null
  adb_ shell "$b network -e wifi show -e level 4" >/dev/null
  adb_ shell "$b network -e mobile hide" >/dev/null
  adb_ shell "$b notifications -e visible false" >/dev/null
}

boot() {
  just _emu-serial "$1" >/dev/null 2>&1 || BOOTED_HERE=yes
  just emu-boot "$1" >/dev/null
  SERIAL=$(just _emu-serial "$1")
  echo "== $1 ($SERIAL)"
}

# A clean install of [apk], in English, notifications granted so no dialog
# covers the first screen.
install_app() {
  adb_ uninstall "$PKG" >/dev/null 2>&1 || true
  adb_ install -g "$1" >/dev/null
  adb_ shell cmd locale set-app-locales "$PKG" --locales en-US
}

phone_like() {
  local avd=$1 dir=$2 portrait=$3 size=${4:-}
  boot "$avd"
  if [ -n "$size" ]; then
    adb_ shell wm size "$size"
    RESIZED=yes
    sleep 2
  fi
  SYSUI_BEFORE=$(adb_ shell settings get global sysui_demo_allowed | tr -d '\r')
  if [ -n "$portrait" ]; then
    ROT_BEFORE=$(adb_ shell settings get system user_rotation | tr -d '\r')
    ACC_BEFORE=$(adb_ shell settings get system accelerometer_rotation | tr -d '\r')
    adb_ shell settings put system accelerometer_rotation 0
    adb_ shell settings put system user_rotation "$portrait"
  fi
  status_bar_demo
  install_app build/dist/app-mobile-release.apk

  adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
  tap_label '^Try the demo$'
  tap_label '^Sign in and connect$' scroll
  wait_label 'X1 Carbon' >/dev/null
  tap_if_shown '^Skip tour$'
  tap_if_shown '^(Not now|Later|Close)$'
  sleep 3

  open_route /
  shot "$dir" "$dir-01-dashboard"
  tap_label '^Details$' scroll
  swipe_up 35
  shot "$dir" "$dir-02-dashboard-details"
  open_route /queue
  shot "$dir" "$dir-03-queue"
  open_route /inventory
  shot "$dir" "$dir-04-filaments"
  tap_label 'Bambu Lab PLA Basic'
  shot "$dir" "$dir-05-spool-details"
  adb_ shell input keyevent BACK
  open_route /maintenance
  shot "$dir" "$dir-06-maintenance"
  open_route /stats
  shot "$dir" "$dir-07-statistics"
  # Added since the July set.
  open_route /files
  shot "$dir" "$dir-08-library"
  open_route /settings/app
  shot "$dir" "$dir-09-appearance"
  # The controller is landscape: under the portrait lock it would be letterboxed.
  [ -n "$portrait" ] && adb_ shell settings put system user_rotation 0
  open_route /controller/1
  sleep 3
  # Android's one-time "Viewing full screen" hint, shown over the immersive
  # controller on an AVD that has not seen it yet.
  tap_if_shown '^Got it$'
  shot "$dir" "$dir-10-controller"
  restore
}

wear() {
  boot wear_round
  # What `just _test-wear` sets too: no ambient, no sleep on a wristless AVD.
  for setting in ambient_enabled=0 ungaze_sleep_enabled=0; do
    adb_ shell settings put global "${setting%%=*}" "${setting#*=}"
  done
  adb_ shell input keyevent KEYCODE_WAKEUP
  install_app build/dist/app-wear-release.apk

  adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
  tap_label '^Demo$' scroll
  wait_label '^X1 Carbon' >/dev/null
  sleep 2
  shot wear wear-01-printers
  tap_label '^X1 Carbon'
  shot wear wear-02-printing
  tap_label '^Stop$' scroll
  shot wear wear-04-stop-confirm
  adb_ shell input keyevent BACK
  sleep 1
  adb_ shell input keyevent BACK
  sleep 1
  tap_label '^P1S' scroll
  shot wear wear-03-idle
  restore
}

if [ "$BUILD" = yes ]; then
  case $WHICH in
    wear) just build-wear ;;
    all) just build && just build-wear ;;
    *) just build ;;
  esac
fi

case $WHICH in
  # Play refuses a long side over twice the short one, which the Pixel's 1080x2400
  # is; 9:16 is also what store promotion asks for.
  phone) phone_like pixel35 phone '' 1080x1920 ;;
  tablet7) phone_like tablet7 tablet7 '' ;;
  # The AVD's panel is landscape; the published set is portrait.
  tablet10) phone_like tablet10 tablet10 1 ;;
  wear) wear ;;
  all)
    phone_like pixel35 phone '' 1080x1920
    phone_like tablet7 tablet7 ''
    phone_like tablet10 tablet10 1
    wear
    ;;
  *) echo "usage: $0 [phone|tablet7|tablet10|wear|all] [--no-build]" >&2; exit 2 ;;
esac
