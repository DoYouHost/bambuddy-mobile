#!/usr/bin/env python3
"""Regenerate assets/hms/print_errors_{en,pl}.json — the app's only HMS catalog.

The card names exactly the faults bambuddy's own UI names, and no others. That
is a deliberate choice, not a limitation: bambuddy's table covers the 32-bit
`print_error` channel — the faults that pause or kill a print and offer the
user a button (filament ran out, door open, wrong plate) — while the `hms[]`
channel it ignores is component diagnostics.

Two independent sources, each doing the job the other cannot:

* WHICH codes ship — bambuddy's own `HMS_ERROR_DESCRIPTIONS`
  (backend/app/services/hms_errors.py), plus the one full-code entry its
  frontend adds by hand (see EXTRA below).
* WHAT the text says — ha-bambulab's `device_error` tables, which are Bambu's
  own strings in every language they publish. bambuddy's copy went through a
  200-character truncation (47 entries end in "..."), and it is English-only.

Usage: python3 tool/fetch_print_error_catalog.py [path/to/bambuddy]
"""

from __future__ import annotations

import gzip
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

HA_BAMBULAB = (
    "https://raw.githubusercontent.com/greghesp/ha-bambulab/main/"
    "custom_components/bambu_lab/pybambu/hms_error_text/hms_{lang}.json.gz"
)
LANGS = ("en", "pl")
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "assets" / "hms"

# The one fault bambuddy names outside its generated table: an `hms[]`-channel
# code (hence 16 hex, not 8) whose meaning lives in bits the short form throws
# away, so its frontend keys it by the full code and writes the text itself.
# Worth carrying because it is the error that explains why nothing the app sends
# reaches the printer. Bambu never published it, so there is nothing to fetch —
# the text below is bambuddy's, translated.
EXTRA = {
    "0500050000010007": {
        "en": "The printer rejected a command because it could not verify it. Prints, "
        "temperature changes and filament loads sent from Bambuddy will be ignored "
        "until this is fixed.",
        "pl": "Drukarka odrzuciła polecenie, bo nie mogła go zweryfikować. Wydruki, zmiany "
        "temperatury i ładowanie filamentu wysyłane z Bambuddy będą ignorowane, dopóki "
        "problem nie zostanie naprawiony.",
    },
}


def bambuddy_codes(server_repo: Path) -> set[str]:
    """The 8-hex print-error codes bambuddy names, read from its Python table."""
    table = server_repo / "backend" / "app" / "services" / "hms_errors.py"
    source = table.read_text(encoding="utf-8")
    codes = {c.replace("_", "") for c in re.findall(r'"([0-9A-F]{4}_[0-9A-F]{4})":', source)}
    if not codes:
        raise SystemExit(f"no error codes found in {table}")
    return codes


def fetch_texts(lang: str) -> dict[str, dict[str, list[str]]]:
    with urllib.request.urlopen(HA_BAMBULAB.format(lang=lang), timeout=60) as response:
        raw = response.read()
    return json.load(gzip.GzipFile(fileobj=io.BytesIO(raw)))["device_error"]


def pick(variants: dict[str, list[str]]) -> str:
    """One text per code. Bambu ships per-model wordings (57 codes) keyed by an
    empty model list for the generic one; the app has no model at lookup time,
    so the generic wording is the honest pick."""
    for text, models in variants.items():
        if not models:
            return text
    return next(iter(variants))


def main() -> None:
    server_repo = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "reference" / "bambuddy"
    wanted = bambuddy_codes(server_repo)
    for lang in LANGS:
        texts = fetch_texts(lang)
        missing = sorted(wanted - texts.keys())
        table = {code: pick(texts[code]) for code in sorted(wanted & texts.keys())}
        table.update({code: variants[lang] for code, variants in EXTRA.items()})
        out = OUT_DIR / f"print_errors_{lang}.json"
        out.write_text(
            json.dumps(table, ensure_ascii=False, indent=0, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"{out.relative_to(REPO_ROOT)}: {len(table)} codes, {len(missing)} missing {missing[:5]}")


if __name__ == "__main__":
    main()
