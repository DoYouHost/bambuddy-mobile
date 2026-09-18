# /// script
# requires-python = ">=3.11"
# dependencies = ["google-api-python-client>=2.100", "google-auth>=2.20"]
# ///
"""Google Play publishing: list the tracks, or release bundles to internal testing.

  tracks                        list every track and the releases on it
  internal [--dry-run] AAB...   upload the bundles and release each one to
                                internal testing, all in one committed edit

A bundle whose versionCode is already on its track is skipped, so a re-run after
a failure finishes the job instead of tripping over "version code already used".

The service-account key lives outside the repo; PLAY_SA_KEY overrides its path.
Run through uv, which resolves the dependencies declared above:

usage: uv run tool/play_internal.py tracks | internal [--dry-run] AAB...
"""

import argparse
import os
import socket
import sys
import zipfile
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

from aab_versions import bundle_versions

# The frozen applicationId — the Play listing's identity, see android/app/build.gradle.kts.
PACKAGE = "page.codeberg.morganmlgman.bambuddy_mobile"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
KEY = Path(os.environ.get("PLAY_SA_KEY", "~/.config/bambuddy/play-sa.json")).expanduser()

# The watch band starts a billion up (versionCode table in the justfile), so the
# code baked into a bundle says which form factor it is — more reliably than the
# order or the name of the files handed in.
WEAR_OFFSET = 1_000_000_000

# Play answers a bundle upload only once it has processed it, which can outlast
# the client's 60 s socket default; fastlane's supply waits 300 s for the same reason.
socket.setdefaulttimeout(300)


def list_tracks(edits, edit_id):
    tracks = edits.tracks().list(packageName=PACKAGE, editId=edit_id).execute()
    for track in tracks.get("tracks", []):
        # A track with no releases still gets a line: its name is what we need.
        for release in track.get("releases") or [{}]:
            codes = ",".join(release.get("versionCodes", [])) or "-"
            print(
                f"{track['track']:<22} {release.get('status', '-'):<12}"
                f" {release.get('name', '-'):<22} {codes}"
            )


def read_bundles(paths):
    """(path, versionName, versionCode, track) per bundle, checked as one pair."""
    bundles = []
    for path in paths:
        try:
            name, code = bundle_versions(path)
        except (OSError, zipfile.BadZipFile, KeyError, ValueError, StopIteration) as err:
            sys.exit(f"{path}: cannot read the bundle ({err})")
        if name is None or code is None:
            sys.exit(f"{path}: manifest carries no version")
        track = "wear:internal" if int(code) >= WEAR_OFFSET else "internal"
        bundles.append((path, name, int(code), track))

    # Phone and watch are built from one version, so a mismatch means one file is
    # a leftover from an earlier build, not the pair this run produced.
    if len({name for _, name, _, _ in bundles}) != 1:
        sys.exit("Bundles carry different versions:\n" + "\n".join(
            f"  {path}  {name}  {code}" for path, name, code, _ in bundles))
    if len({track for *_, track in bundles}) != len(bundles):
        sys.exit("Two bundles would go to the same track.")
    return bundles


def release_internal(edits, edit_id, bundles, dry_run):
    """Stage every bundle on its internal track; True when the edit needs a commit."""
    on_track = {
        track["track"]: {
            int(code) for release in track.get("releases", [])
            for code in release.get("versionCodes", [])
        }
        for track in edits.tracks().list(packageName=PACKAGE, editId=edit_id)
        .execute().get("tracks", [])
    }
    # Bundles already in the app's library — uploaded by a run that died before
    # its commit, or by hand in the Console — only need assigning to the track.
    uploaded = {
        bundle["versionCode"] for bundle in
        edits.bundles().list(packageName=PACKAGE, editId=edit_id).execute().get("bundles", [])
    }

    changed = False
    for path, name, code, track in bundles:
        release_name = f"{code} ({name})"
        if code in on_track.get(track, set()):
            print(f"{track}: {release_name} already there, skipping")
            continue
        if dry_run:
            action = "assign" if code in uploaded else "upload"
            print(f"{track}: would {action} {release_name} from {path}")
            continue
        if code not in uploaded:
            print(f"{track}: uploading {path} ({release_name})")
            edits.bundles().upload(
                packageName=PACKAGE,
                editId=edit_id,
                media_body=MediaFileUpload(path, mimetype="application/octet-stream", resumable=True),
            ).execute()
        edits.tracks().update(
            packageName=PACKAGE,
            editId=edit_id,
            track=track,
            body={
                "track": track,
                "releases": [{"name": release_name, "versionCodes": [str(code)], "status": "completed"}],
            },
        ).execute()
        print(f"{track}: {release_name} staged")
        changed = True
    return changed


def main():
    parser = argparse.ArgumentParser(description="Google Play publishing for bambuddy-mobile.")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("tracks", help="list every track and the releases on it")
    internal = commands.add_parser("internal", help="release bundles to internal testing")
    internal.add_argument("--dry-run", action="store_true", help="read and report, change nothing")
    internal.add_argument("bundles", nargs="+", metavar="AAB")
    args = parser.parse_args()

    # Read before touching the network, so a missing or mismatched bundle
    # costs nothing and leaves no edit behind.
    bundles = read_bundles(args.bundles) if args.command == "internal" else []
    if not KEY.is_file():
        sys.exit(f"No service-account key at {KEY} (set PLAY_SA_KEY to override).")
    creds = service_account.Credentials.from_service_account_file(str(KEY), scopes=[SCOPE])
    edits = build("androidpublisher", "v3", credentials=creds, cache_discovery=False).edits()

    try:
        edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
        committed = False
        try:
            if args.command == "tracks":
                list_tracks(edits, edit_id)
            elif release_internal(edits, edit_id, bundles, args.dry_run):
                edits.commit(packageName=PACKAGE, editId=edit_id).execute()
                committed = True
                print("Released to internal testing.")
        finally:
            if not committed:
                edits.delete(packageName=PACKAGE, editId=edit_id).execute()
    except HttpError as e:
        # A fresh Play Console grant can take a while to reach the API, so a 403
        # right after setup is not necessarily a wrong permission.
        sys.exit(f"Play API {e.status_code}: {e.reason}")


if __name__ == "__main__":
    main()
