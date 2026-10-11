#!/usr/bin/env python3
"""Glue every one-letter word in the .arb strings to the word after it.

A line must not end on a one-letter word ("i", "w", "a", "à", "y"), in any
language. The space after such a word becomes a no-break space (U+00A0), which
the translation looks the same with and Flutter never breaks a line at.

Rewrites lib/l10n/app_*.arb in place; run `flutter gen-l10n` after it
(`just l10n-glue` does both). test/l10n/short_words_test.dart fails on any
string this would still change.

Usage:
  python3 tool/glue_short_words.py
"""
import glob
import json
import re

# A letter on its own: not after a letter, a digit or a placeholder (the "h"
# of "1h" and "{hours}h" is a unit, not a word), and not after an apostrophe,
# where it is the tail of "don't".
SHORT_WORD = re.compile(r"(?<![\w'’}])([^\W\d_]) ")

# The one-letter units the copy uses ("24 h", "{grams} g", "5 s", "7 j",
# "{watts} W"). After a number or a placeholder only these are units; any other
# letter there is a word ("{name} a échoué", "{count} w kolejce").
UNITS = "hsdgjW"
UNIT = re.compile(r"([0-9}]) (?=[" + UNITS + r"](?![\w'’]))")


def _short_word(match: re.Match) -> str:
    # A unit keeps the space after it: it is glued to its number instead.
    before = match.string[max(0, match.start() - 2) : match.start()]
    if match.group(1) in UNITS and re.fullmatch(r"[0-9}][ \u00a0]", before):
        return match.group(0)
    return match.group(1) + "\u00a0"


def glue(text: str) -> str:
    return UNIT.sub("\\1\u00a0", SHORT_WORD.sub(_short_word, text))


def main() -> None:
    for path in sorted(glob.glob("lib/l10n/app_*.arb")):
        with open(path, encoding="utf-8") as f:
            arb = json.load(f)
        changed = 0
        for key, value in arb.items():
            if key.startswith("@") or not isinstance(value, str):
                continue
            glued = glue(value)
            if glued != value:
                arb[key] = glued
                changed += 1
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(arb, indent=2, ensure_ascii=False) + "\n")
        print(f"{path}: {changed} strings")


if __name__ == "__main__":
    main()
