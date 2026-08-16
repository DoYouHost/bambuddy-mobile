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

# Descriptions Bambu wrote for its own dialog, where the sentence "select
# 'Resume' to resume the print job" sat right above a Resume button. The app
# draws that button too, from `HMSError.actions`, so the sentence is the button
# said twice — and it is the half that pushes the card past two lines.
#
# Only that clause goes. The diagnosis and any physical instruction stay, and
# where the choice of button carried meaning ("Done if it extruded, Retry if
# not") the question survives as a question — the buttons below answer it.
#
# Keyed by code, with the drift check in `apply_overrides`: an override whose
# upstream text no longer mentions a button is reported rather than applied, so
# a rewritten description cannot be silently replaced by our older wording.
_AMS_MAPPING = {
    "en": "Failed to get the AMS mapping table.",
    "pl": "Nie udało się pobrać tabeli mapowania z AMS.",
}
_MAPPING = {
    "en": "Failed to get the mapping table.",
    "pl": "Nie udało się pobrać tabeli mapowania.",
}
_CHECK_NOZZLE = {
    "en": "Check the nozzle: has filament come out? If not, push the filament forward slightly.",
    "pl": "Sprawdź dyszę — czy filament wyszedł? Jeśli nie, popchnij go lekko do przodu.",
}
_CHECK_NOZZLE_LEFT = {
    "en": "Check the left extruder's nozzle: has filament come out? If not, push the filament"
    " forward slightly.",
    "pl": "Sprawdź dyszę lewego ekstrudera — czy filament wyszedł? Jeśli nie, popchnij go lekko"
    " do przodu.",
}
_CHECK_NOZZLE_RIGHT = {
    "en": "Check the right extruder's nozzle: has filament come out? If not, push the filament"
    " forward slightly.",
    "pl": "Sprawdź dyszę prawego ekstrudera — czy filament wyszedł? Jeśli nie, popchnij go lekko"
    " do przodu.",
}
_PULL_FILAMENT = {
    "en": "Slowly pull the filament out of the extruder by hand.",
    "pl": "Powoli wyciągnij filament z ekstrudera ręcznie.",
}
_PTFE = {
    "en": "Press the black PTFE coupler and unplug the tube.",
    "pl": "Naciśnij czarną złączkę i odłącz rurkę PTFE.",
}

OVERRIDES: dict[str, dict[str, str]] = {
    "03008000": {
        "en": "Printing was paused for an unknown reason.",
        "pl": "Drukowanie zostało wstrzymane z nieznanego powodu.",
    },
    "03008001": {
        "en": "Printing was paused by the user.",
        "pl": "Drukowanie zostało wstrzymane przez użytkownika.",
    },
    "0300800D": {
        "en": "The extruder is not extruding normally. Resume only if the defects are acceptable.",
        "pl": "Ekstruder nie wytłacza prawidłowo. Wznawiaj tylko, jeśli akceptujesz wady wydruku.",
    },
    "03008014": {
        "en": "The nozzle is covered with filament, or the build plate is installed incorrectly."
        " Clean the nozzle or seat the plate properly.",
        "pl": "Dysza jest pokryta filamentem albo płyta robocza jest źle założona. Wyczyść dyszę"
        " lub popraw ułożenie płyty.",
    },
    "03008015": {
        "en": "The filament on the external spool has run out. Load new filament.",
        "pl": "Skończył się filament na zewnętrznej szpuli. Załaduj nowy.",
    },
    "03008016": {
        "en": "The nozzle is clogged with filament. Clean it, or cancel the print.",
        "pl": "Dysza jest zatkana filamentem. Wyczyść ją albo anuluj wydruk.",
    },
    "03008017": {
        "en": "Foreign objects detected on the heatbed. Check it and clean it.",
        "pl": "Wykryto obce obiekty na stole roboczym. Sprawdź go i wyczyść.",
    },
    "0300801C": {
        "en": "The extrusion resistance is abnormal. The extruder may be clogged — see the"
        " printer's assistant.",
        "pl": "Opór przy wytłaczaniu jest nieprawidłowy. Ekstruder może być zapchany — zajrzyj do"
        " asystenta w drukarce.",
    },
    "0C008001": {
        "en": "First layer defects were detected. Resume only if the defects are acceptable.",
        "pl": "Wykryto wady pierwszej warstwy. Wznawiaj tylko, jeśli je akceptujesz.",
    },
    "12018005": {
        "en": "Failed to feed the filament. Load it and try again.",
        "pl": "Nie udało się podać filamentu. Załaduj go i spróbuj ponownie.",
    },
    "07FEC011": _PULL_FILAMENT,
    "07FFC011": _PULL_FILAMENT,
    "07FEC012": _PTFE,
    "07FFC012": _PTFE,
    "07FF8007": _CHECK_NOZZLE,
    "07FFC00A": _CHECK_NOZZLE,
    "12FF8007": _CHECK_NOZZLE,
    "07FE8007": _CHECK_NOZZLE_LEFT,
    "07FEC00A": _CHECK_NOZZLE_LEFT,
    "18FE8007": _CHECK_NOZZLE_LEFT,
    "18FEC00A": _CHECK_NOZZLE_LEFT,
    "18FF8007": _CHECK_NOZZLE_RIGHT,
    "18FFC00A": _CHECK_NOZZLE_RIGHT,
    "07FE8012": _MAPPING,
    "18FE8012": _MAPPING,
    **{
        code: _AMS_MAPPING
        for code in (
            "07008012 07018012 07028012 07038012 07048012 07058012 07068012 07078012 07FF8012"
            " 12008012 12018012 12028012 12038012 12FF8012 18008012 18018012 18028012 18038012"
            " 18048012 18058012 18068012 18078012 18FF8012"
        ).split()
    },
}

# What every overridden description had in common: it told the reader to press a
# button. If Bambu's text stops doing that, the override is stale by definition.
_BUTTON_REFERENCE = re.compile(
    r"(select|choose|click|press|tap)\s*['\"‘“]?(Resume|Continue|Retry|Done|OK)", re.IGNORECASE
)

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


def apply_overrides(table: dict[str, str], english: dict[str, str], lang: str) -> list[str]:
    """Replace the descriptions listed in OVERRIDES; report the stale ones.

    `english` is the untouched English text for the same codes — the drift check
    reads it rather than the localised one, so a translation quirk in any single
    language cannot decide whether an override still applies.
    """
    stale = []
    for code, variants in OVERRIDES.items():
        if code not in table:
            stale.append(f"{code} (no longer in bambuddy's table)")
            continue
        if not _BUTTON_REFERENCE.search(english.get(code, "")):
            stale.append(f"{code} (upstream no longer names a button)")
            continue
        table[code] = variants[lang]
    return stale


def main() -> None:
    server_repo = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "reference" / "bambuddy"
    wanted = bambuddy_codes(server_repo)
    english = {code: pick(variants) for code, variants in fetch_texts("en").items()}
    for lang in LANGS:
        texts = fetch_texts(lang)
        missing = sorted(wanted - texts.keys())
        table = {code: pick(texts[code]) for code in sorted(wanted & texts.keys())}
        table.update({code: variants[lang] for code, variants in EXTRA.items()})
        for note in apply_overrides(table, english, lang):
            print(f"  stale override: {note} — re-read it before trusting our wording")
        out = OUT_DIR / f"print_errors_{lang}.json"
        out.write_text(
            json.dumps(table, ensure_ascii=False, indent=0, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"{out.relative_to(REPO_ROOT)}: {len(table)} codes, {len(missing)} missing {missing[:5]}")


if __name__ == "__main__":
    main()
