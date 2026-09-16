#!/usr/bin/env python3
"""Assert what the watch APK does and does not contain.

Two things the Dart test suite cannot see, because both are decided by Gradle
and the Android manifest merger rather than by any code a widget test runs:

1. **Phone-only assets are pruned.** `pubspec.yaml` declares assets once for
   both flavors, so the watch would otherwise ship the G-code viewer, the slicer
   schemas, the dashboard's cover placeholder and four JetBrains Mono faces —
   roughly 2.2 MB behind screens the wear entry point does not have. The pruning
   lives in `android/app/build.gradle.kts`, and a path that stops matching fails
   silently: the build still succeeds, the megabytes just come back.

2. **Startup components are stripped.** `MlKitInitProvider` and friends are
   ContentProviders, which Android instantiates inside `Application.onCreate` on
   every cold start — before Flutter is asked to start. They are removed in
   `android/app/src/wear/AndroidManifest.xml`, and a merger change or a plugin
   upgrade that reintroduces one is invisible until somebody dumps the manifest.

Each pruned asset is checked both ways where the APK can answer: gone from the
build, and never named by the wear Dart snapshot. The second half is what makes
the first safe — an asset the snapshot still names is one a screen can still ask
for, and deleting it would trade a megabyte for a missing asset at runtime.

That half needs an AOT build. A debug APK carries `kernel_blob.bin`, the whole
program before tree shaking, which names the phone's assets whatever the watch
can reach; there the check reports itself skipped rather than passing on a
signal it does not have. CI builds debug, so the reachability half runs on the
release builds `just build-wear` makes, and the rest runs on every PR.

Usage:
    tool/check_wear_apk.py build/app/outputs/flutter-apk/app-wear-debug.apk
    tool/check_wear_apk.py <wear.apk> --mobile <mobile.apk>

`--mobile` turns on the control checks: the same assets must still be *present*
on the phone, so a pruning rule that accidentally matched everything, or an
asset quietly dropped from `pubspec.yaml`, fails here rather than in the store.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ASSETS = "assets/flutter_assets/"

# Prefixes under flutter_assets that must not reach the watch. Mirrors
# `wearPrunedAssetPaths` in android/app/build.gradle.kts — the two are a pair,
# and this file is the half that fails loudly.
PRUNED_ASSET_PREFIXES = [
    "assets/gcode/",
    "assets/slicer/",
    "assets/icons/cover_placeholder.png",
    "assets/fonts/JetBrainsMono-",
]

# Font families the watch must not declare. A family left in FontManifest.json
# after its files are gone is worse than not pruning at all.
PRUNED_FONT_FAMILIES = ["JetBrainsMono"]

# Families the watch genuinely draws with. Named so an over-eager prune — or a
# pubspec edit — cannot quietly take the app's own typeface with it.
REQUIRED_FONT_FAMILIES = ["Manrope", "MaterialIcons"]

# Assets the watch does use, listed for the same reason.
REQUIRED_ASSET_PREFIXES = [
    "assets/hms/print_errors_en.json",
    "assets/fonts/Manrope-400.ttf",
]

# Components that must not be declared in the watch manifest. Every one either
# runs at process start or is wired to something the watch has stripped.
FORBIDDEN_COMPONENTS = [
    "com.google.mlkit.common.internal.MlKitInitProvider",
    "com.google.mlkit.common.internal.MlKitComponentDiscoveryService",
    "net.nfet.flutter.printing.PrintFileProvider",
    "dev.fluttercommunity.plus.share.ShareFileProvider",
    "androidx.glance.appwidget.GlanceRemoteViewsService",
    "androidx.glance.appwidget.action.ActionCallbackBroadcastReceiver",
    "androidx.camera.core.impl.MetadataHolderService",
    "androidx.core.widget.RemoteViewsCompatService",
    "com.pravera.flutter_foreground_task.service.ForegroundService",
    "com.pravera.flutter_foreground_task.service.RebootReceiver",
    "page.codeberg.morganmlgman.bambuddy_mobile.BambuddyWidgetProvider",
    "page.codeberg.morganmlgman.bambuddy_mobile.BambuddyMultiWidgetProvider",
    "page.codeberg.morganmlgman.bambuddy_mobile.wear.WearRelayListenerService",
]

# What still has to be there, so "stripped everything" is not a pass.
REQUIRED_COMPONENTS = [
    "page.codeberg.morganmlgman.bambuddy_mobile.MainActivity",
]

# Printable ASCII runs, the way `strings(1)` finds them — used to ask the Dart
# snapshot whether it still names an asset we are about to delete.
_STRINGS = re.compile(rb"[\x20-\x7e]{4,}")


class Failure(Exception):
    """One assertion that did not hold, worded for the console."""


def entries(apk: Path) -> list[str]:
    with zipfile.ZipFile(apk) as z:
        return z.namelist()


def asset_names(names: list[str]) -> list[str]:
    return [n[len(ASSETS):] for n in names if n.startswith(ASSETS)]


def total_size(apk: Path, prefixes: list[str]) -> int:
    with zipfile.ZipFile(apk) as z:
        return sum(
            i.file_size
            for i in z.infolist()
            if i.filename.startswith(ASSETS)
            and any(i.filename[len(ASSETS):].startswith(p) for p in prefixes)
        )


def font_families(apk: Path) -> list[str]:
    with zipfile.ZipFile(apk) as z:
        try:
            raw = z.read(f"{ASSETS}FontManifest.json")
        except KeyError:
            raise Failure("FontManifest.json is missing from the APK")
    return [f.get("family") for f in json.loads(raw)]


def snapshot_strings(apk: Path) -> set[bytes] | None:
    """Printable runs in the Dart AOT snapshot, or None when there is not one.

    Only an AOT build answers this usefully. A debug APK ships `kernel_blob.bin`
    — the whole program, tree shaking not yet applied — so the phone's screens
    and every string they hold are in there whatever the watch can reach. Asking
    it "does the watch still name this?" gets a yes for everything, which is why
    this returns None there and the caller skips rather than fails.
    """
    with zipfile.ZipFile(apk) as z:
        blobs = [n for n in z.namelist() if n.endswith("/libapp.so")]
        if not blobs:
            return None
        found: set[bytes] = set()
        for name in blobs:
            found.update(_STRINGS.findall(z.read(name)))
    return found


def aapt2() -> str | None:
    """aapt2 from the Android SDK, or None when there is none to find."""
    direct = shutil.which("aapt2")
    if direct:
        return direct
    root = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not root:
        root = str(Path.home() / "Android" / "Sdk")
    build_tools = Path(root) / "build-tools"
    if not build_tools.is_dir():
        return None
    # Highest version wins; they all dump a manifest the same way.
    for version in sorted(build_tools.iterdir(), reverse=True):
        candidate = version / "aapt2"
        if candidate.is_file():
            return str(candidate)
    return None


def declared_components(apk: Path) -> str:
    tool = aapt2()
    if tool is None:
        raise Failure(
            "aapt2 not found — set ANDROID_HOME, or put it on PATH, so the "
            "manifest half of this check can run"
        )
    out = subprocess.run(
        [tool, "dump", "xmltree", "--file", "AndroidManifest.xml", str(apk)],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise Failure(f"aapt2 could not read the manifest:\n{out.stderr.strip()}")
    return out.stdout


def check_wear(apk: Path) -> list[str]:
    """Every assertion about the watch APK. Returns the lines to print on pass."""
    names = entries(apk)
    assets = asset_names(names)
    notes = []

    stowaways = [
        a for a in assets if any(a.startswith(p) for p in PRUNED_ASSET_PREFIXES)
    ]
    if stowaways:
        raise Failure(
            "phone-only assets are still in the watch APK — the pruning in "
            "android/app/build.gradle.kts stopped matching:\n  "
            + "\n  ".join(sorted(stowaways))
        )

    # The other half, and the one that says the prune is *safe* rather than
    # merely done: an asset the snapshot still names is one a screen can still
    # ask for, so pruning it would trade a megabyte for a missing asset at
    # runtime. Only an AOT build can answer — see [snapshot_strings].
    snapshot = snapshot_strings(apk)
    if snapshot is None:
        notes.append(
            "reachability: skipped — no AOT snapshot in this APK "
            "(a debug build has not been tree-shaken, so it names everything)"
        )
    else:
        reachable = [
            p
            for p in PRUNED_ASSET_PREFIXES + PRUNED_FONT_FAMILIES
            if any(p.encode() in run for run in snapshot)
        ]
        if reachable:
            raise Failure(
                "the wear Dart snapshot still names something the build prunes "
                "— a watch screen now reaches it, so the prune list is wrong, "
                "not the code:\n  " + "\n  ".join(sorted(reachable))
            )
        notes.append(
            f"reachability: the wear snapshot names none of the "
            f"{len(PRUNED_ASSET_PREFIXES) + len(PRUNED_FONT_FAMILIES)} pruned paths"
        )

    families = font_families(apk)
    left = [f for f in families if f in PRUNED_FONT_FAMILIES]
    if left:
        raise Failure(f"FontManifest.json still declares {left} on the watch")
    missing_families = [f for f in REQUIRED_FONT_FAMILIES if f not in families]
    if missing_families:
        raise Failure(
            f"the watch lost a font it draws with: {missing_families} — the "
            "prune took more than it was asked for"
        )

    missing_assets = [
        p for p in REQUIRED_ASSET_PREFIXES if not any(a.startswith(p) for a in assets)
    ]
    if missing_assets:
        raise Failure(f"the watch lost an asset it uses: {missing_assets}")

    notes.append(f"assets: {len(assets)} kept, none from the prune list")
    notes.append(f"fonts: {', '.join(f for f in families if f)}")

    manifest = declared_components(apk)
    present = [c for c in FORBIDDEN_COMPONENTS if f'"{c}"' in manifest]
    if present:
        raise Failure(
            "components that should be stripped are declared in the watch "
            "manifest — check android/app/src/wear/AndroidManifest.xml:\n  "
            + "\n  ".join(present)
        )
    absent = [c for c in REQUIRED_COMPONENTS if f'"{c}"' not in manifest]
    if absent:
        raise Failure(f"the watch manifest lost something it needs: {absent}")

    notes.append(f"manifest: {len(FORBIDDEN_COMPONENTS)} components confirmed absent")
    return notes


def check_mobile(apk: Path) -> list[str]:
    """The control: the phone must still carry everything the watch dropped."""
    assets = asset_names(entries(apk))
    missing = [
        p for p in PRUNED_ASSET_PREFIXES if not any(a.startswith(p) for a in assets)
    ]
    if missing:
        raise Failure(
            "the phone APK is missing assets only the watch should lose — the "
            "prune is running for the wrong flavor, or pubspec dropped "
            f"them:\n  {missing}"
        )
    families = font_families(apk)
    gone = [f for f in PRUNED_FONT_FAMILIES if f not in families]
    if gone:
        raise Failure(f"the phone APK lost font families it needs: {gone}")
    return [f"phone control: all {len(PRUNED_ASSET_PREFIXES)} prune targets present"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wear_apk", type=Path, help="the watch APK to check")
    parser.add_argument(
        "--mobile",
        type=Path,
        help="the phone APK, checked as the control that the prune is flavor-scoped",
    )
    args = parser.parse_args()

    for apk in [args.wear_apk, args.mobile]:
        if apk is not None and not apk.is_file():
            print(f"no such APK: {apk}", file=sys.stderr)
            return 2

    try:
        notes = check_wear(args.wear_apk)
        if args.mobile:
            notes += check_mobile(args.mobile)
            saved = total_size(args.mobile, PRUNED_ASSET_PREFIXES)
            notes.append(f"pruned from the watch: {saved / 1024:.0f} KiB uncompressed")
    except Failure as failure:
        print(f"FAIL  {failure}", file=sys.stderr)
        return 1

    for note in notes:
        print(f"ok    {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
