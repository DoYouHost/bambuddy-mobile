#!/usr/bin/env python3
"""Fill a throwaway bambuddy with enough data for the contract tests to bite.

A container started for a job has no printer, no files and no queue, so every
list endpoint answers `[]` — which proves a decoder does not crash and nothing
else. This walks the server up to a state the app has something to read, and
does it entirely through the REST API and the printer's own MQTT topics. No
writes to the database: a seed that reached into SQLite would bind CI to the
server's schema, and a migration upstream would then break the run somewhere
far from the cause.

The printer is the part that looks impossible and is not. `POST /printers/`
refuses one it cannot reach, but `printer_manager.test_connection` only needs an
MQTT session to open — `BambuMQTTClient` disables certificate and hostname
verification (Bambu ships self-signed certs) and flips `state.connected` on
rc == 0 without waiting for a payload. A stock mosquitto with TLS therefore
answers the check honestly, and everything after it is a real printer row.

Status, AMS and filament all arrive the way they do from hardware: retained
messages on `device/{serial}/report`, published with the broker's own
`mosquitto_pub`. Retained matters — bambuddy subscribes after it connects, and
an unretained message published before that is simply gone.

Usage:
    seed_bambuddy.py --base-url http://172.17.0.1:8000 \\
                     --broker-ip 172.17.0.3 --broker-container fake-printer
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

SERIAL = "00M09A000000001"
ACCESS_CODE = "12345678"

# Two slots, one material, two colours. Not an arbitrary choice: the archive
# extractor deduplicates the type list and the colour list independently, so
# this is the shape that collapses to one type while both colours survive —
# the mismatch a live server really produces and the app has to render.
PROBE_FILAMENTS = [
    {"id": "1", "type": "PLA", "color": "#FF0000", "used_g": "12.00"},
    {"id": "2", "type": "PLA", "color": "#00FF00", "used_g": "13.50"},
]


def _request(url: str, *, method: str = "GET", token: str | None = None,
             data: dict | None = None, timeout: int = 30):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=timeout) as res:
        raw = res.read()
    return json.loads(raw) if raw else {}


def wait_for_health(base: str, attempts: int = 60) -> None:
    for _ in range(attempts):
        try:
            urllib.request.urlopen(f"{base}/health", timeout=3).read()
            return
        except (urllib.error.URLError, OSError, TimeoutError):
            time.sleep(2)
    raise SystemExit(f"{base}/health never answered")


def seed_admin(base: str, user: str, password: str) -> str:
    """Create the first admin and return a JWT.

    /auth/setup answers 403 once authentication is configured, so this only
    works on a virgin instance — which is the only kind CI should ever see.
    """
    _request(f"{base}/api/v1/auth/setup", method="POST", data={
        "auth_enabled": True,
        "admin_username": user,
        "admin_password": password,
    })
    login = _request(f"{base}/api/v1/auth/login", method="POST",
                     data={"username": user, "password": password})
    token = login.get("access_token")
    if not isinstance(token, str) or not token:
        raise SystemExit(f"login returned no token; keys: {sorted(login)}")
    return token


def add_printer(base: str, token: str, broker_ip: str) -> int:
    printer = _request(f"{base}/api/v1/printers/", method="POST", token=token,
                       timeout=90, data={
                           "name": "Contract X1C",
                           "serial_number": SERIAL,
                           "ip_address": broker_ip,
                           "access_code": ACCESS_CODE,
                           "model": "X1C",
                       })
    return int(printer["id"])


def publish_report(container: str, payload: dict) -> None:
    """Publish one retained report as the printer would."""
    subprocess.run(
        ["docker", "exec", container, "mosquitto_pub",
         "-h", "localhost", "-p", "8883", "--insecure",
         "--cafile", "/mosquitto/certs/server.crt",
         "-t", f"device/{SERIAL}/report", "-r",
         "-m", json.dumps(payload)],
        check=True, capture_output=True,
    )


def printing_report() -> dict:
    """A printer mid-job, with both AMS slots loaded.

    Field names are the wire's, taken from the server's own fixtures
    (`backend/tests/integration/test_available_filaments.py`) rather than
    guessed: tray colours are RRGGBBAA and uppercase, which is what makes the
    app's alpha handling worth testing against something real.
    """
    return {
        "print": {
            "gcode_state": "RUNNING",
            "mc_percent": 42,
            "mc_remaining_time": 75,
            "nozzle_temper": 215.0,
            "bed_temper": 60.0,
            "subtask_name": "contract-probe.3mf",
            "layer_num": 30,
            "total_layer_num": 120,
            "ams": {
                "ams": [{
                    "id": 0,
                    "tray": [
                        {"id": 0, "tray_type": "PLA", "tray_color": "FF0000FF",
                         "tray_info_idx": "GFL99", "tray_sub_brands": "PLA Basic"},
                        {"id": 1, "tray_type": "PLA", "tray_color": "00FF00FF",
                         "tray_info_idx": "GFL99", "tray_sub_brands": "PLA Basic"},
                    ],
                }],
                "ams_exist_bits": "1",
            },
        }
    }


def build_3mf(path: Path) -> None:
    """A 3MF carrying only what the extractor reads.

    `services/archive.py` opens `Metadata/slice_info.config` and nothing else
    for filament data, so the geometry is a stub. A filament with used_g of 0
    is skipped there, which is why both carry a real weight.
    """
    filaments = "\n".join(
        f'    <filament id="{f["id"]}" type="{f["type"]}" '
        f'color="{f["color"]}" used_g="{f["used_g"]}" used_m="4.00"/>'
        for f in PROBE_FILAMENTS
    )
    slice_info = f"""<?xml version="1.0" encoding="UTF-8"?>
<config>
  <header><header_item key="X-BBL-Client-Type" value="slicer"/></header>
  <plate>
    <metadata key="index" value="1"/>
    <metadata key="prediction" value="3600"/>
    <metadata key="weight" value="25.50"/>
    <object identify_id="1" name="contract-probe" skipped="false"/>
{filaments}
  </plate>
</config>
"""
    content_types = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>'
        "</Types>"
    )
    rels = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Target="/3D/3dmodel.model" Id="rel-1" '
        'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>'
        "</Relationships>"
    )
    model = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
        "<resources/><build/></model>"
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("3D/3dmodel.model", model)
        z.writestr("Metadata/slice_info.config", slice_info)


def upload_3mf(base: str, token: str, path: Path) -> int:
    """multipart/form-data by hand — the stdlib has no builder for it, and a
    seed script earning a dependency for one request is a bad trade."""
    boundary = "----bambuddyContractSeed"
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n",
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(
        f"{base}/api/v1/library/files", data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as res:
        return int(json.loads(res.read())["id"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--broker-ip", required=True)
    ap.add_argument("--broker-container", required=True)
    ap.add_argument("--admin-user", default="ci-admin")
    ap.add_argument("--admin-pass", default="CiTest!2026x")
    args = ap.parse_args()

    base = args.base_url.rstrip("/")

    wait_for_health(base)
    token = seed_admin(base, args.admin_user, args.admin_pass)
    print("admin seeded")

    printer_id = add_printer(base, token, args.broker_ip)
    print(f"printer {printer_id} accepted against the broker")

    publish_report(args.broker_container, printing_report())
    print("status and AMS published (retained)")

    path = Path("/tmp/contract-probe.3mf")
    build_3mf(path)
    file_id = upload_3mf(base, token, path)
    print(f"library file {file_id} uploaded")

    item = _request(f"{base}/api/v1/queue/", method="POST", token=token,
                    data={"printer_id": printer_id, "library_file_id": file_id})
    print(f"queue item {item.get('id')} created")

    return 0


if __name__ == "__main__":
    sys.exit(main())
