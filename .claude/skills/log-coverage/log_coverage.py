#!/usr/bin/env python3
"""Reports which interactive widgets are missing a diagnostic-log identifier.

The bug-report log records `Semantics(identifier:)` and never accessibility
labels, so a control nobody named reads as `role=button` and nothing else. This
scans `lib/` for widgets a finger can land on and tells you which ones no
`logTag(...)` / `.tagged(...)` reaches.

Coverage follows the probe's runtime rule — an identifier is inherited *down* the
tree — so a widget counts as covered when:

  * it sits inside a `logTag(...)` / `.tagged(...)` argument in the same file, or
  * it sits inside a call to a wrapper that tags what it is given (`dashAppBar`), or
  * it sits in a widget class whose every instantiation is itself covered
    (`_FilterButton` is tagged at its call site, so its innards inherit).

The last rule is resolved to a fixpoint, which is what makes the numbers usable
rather than alarmist. It is still a text scan, not the analyzer: it cannot see a
widget handed through a variable or a builder callback, so treat a reported gap
as "worth looking at", not as proof.

Usage:
  log_coverage.py [--wear] [--limit N] [--kind NAME] [--json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --- what counts as a control -------------------------------------------------

# Always a control: the user can put a finger on it and something happens.
ALWAYS = {
    "ElevatedButton", "FilledButton", "TextButton", "OutlinedButton",
    "IconButton", "FloatingActionButton", "SegmentedButton", "MenuItemButton",
    "PopupMenuButton", "TextField", "TextFormField", "DropdownMenu",
    "DropdownButton", "DropdownButtonFormField", "Checkbox", "Switch",
    "Radio", "Slider", "RangeSlider", "ChoiceChip", "FilterChip", "ActionChip",
    "InputChip", "Dismissible", "PopupMenuItem", "CheckedPopupMenuItem",
    "DropdownMenuItem", "DropdownMenuEntry", "ExpansionTile",
    "ReorderableDragStartListener", "ReorderableDelayedDragStartListener",
}

# Rows of a menu, which the framework builds into a route of its own. The tag on
# the anchor — the `PopupMenuButton`, the `DropdownMenu` — stays behind in the
# main tree, so it never reaches them: at runtime a row named that way still
# records as a bare `menuItem`. Only a tag the row carries with it counts, which
# means one written inside it (`child:`, `labelWidget:`) or hung off it.
POPUP_ITEMS = {
    "PopupMenuItem", "CheckedPopupMenuItem", "MenuItemButton",
    "DropdownMenuItem", "DropdownMenuEntry",
}

# A control only when it is given a callback — a bare `ListTile` is a row of
# text, an `InkWell` without `onTap` is decoration.
NEEDS_CALLBACK = {
    "InkWell", "GestureDetector", "ListTile", "CheckboxListTile",
    "SwitchListTile", "RadioListTile", "InkResponse",
}

CALLBACK = re.compile(r"\bon(Tap|Pressed|Changed|Selected|LongPress|Submitted)\s*:")
DISABLED_ARG = re.compile(r"\benabled\s*:\s*false\b")

# Functions that tag whatever they are handed, so arguments to them inherit.
# `dashAppBar` wraps the whole bar in `chrome.appbar`, which reaches the
# framework-built back button and every action passed in.
WRAPPERS = {"dashAppBar": "chrome.appbar"}

# The type argument is optional and may itself be generic — `SegmentedButton<X>`,
# `DropdownButtonFormField<int>`, `PopupMenuButton<String>`. Without it those
# constructors matched nothing and a whole kind went unreported.
WIDGET_CALL = re.compile(
    r"\b(" + "|".join(sorted(ALWAYS | NEEDS_CALLBACK))
    + r")(?:<[^()\n]*?>)?(?:\.(\w+))?\s*\("
)

# `FilledButton.styleFrom(...)` builds a style, `Theme.of(...)` reads one —
# neither is a control on screen.
NOT_WIDGETS = {"styleFrom", "of", "maybeOf"}
# `logTag` is a thin wrapper over this; a few places (the recording bar) use the
# raw widget because they also set a label.
SEMANTICS_CALL = re.compile(r"\bSemantics\s*\(")
IDENTIFIER_ARG = re.compile(r"\bidentifier\s*:")
CLASS_DECL = re.compile(r"\bclass\s+(\w+)\b")
# `Widget _iconButton({...}) => IconButton(...)` — a builder method inherits the
# name from wherever it is called, exactly like a widget class does.
METHOD_DECL = re.compile(
    r"\b(?:Widget|PreferredSizeWidget|PopupMenuEntry|PopupMenuItem|List<Widget>)"
    r"(?:<[^>\n]*>)?\s+(_?\w+)\s*(?:<[^>\n]*>)?\s*\("
)
TAG_CALL = re.compile(r"\blogTag(?:Material)?\s*\(")
TAGGED_CALL = re.compile(r"\.tagged(?:Material)?\s*\(")
WRAPPER_CALL = re.compile(r"\b(" + "|".join(WRAPPERS) + r")\s*\(")

SKIP_FILES = ("app_localizations",)


def mask(src: str) -> str:
    """Blanks out comments and string bodies, keeping every index and newline.

    Paren matching has to run on code only: a `'('` in a label would throw the
    whole file off. String interpolations stay visible, since widgets do get
    built inside `${...}`.
    """
    out = list(src)
    i, n = 0, len(src)
    # Stack of open `${` interpolations: each entry is the brace depth to return
    # to the surrounding string at.
    interp: list[tuple[str, bool, int]] = []
    while i < n:
        ch = src[i]
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if two == "/*":
            while i < n and src[i:i + 2] != "*/":
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            for j in range(i, min(i + 2, n)):
                out[j] = " "
            i += 2
            continue
        if ch in "'\"":
            raw = i > 0 and src[i - 1] == "r"
            triple = src[i:i + 3] in ("'''", '"""')
            quote = src[i:i + 3] if triple else ch
            i += len(quote)
            while i < n:
                if src[i] == "\\" and not raw:
                    out[i] = " "
                    if i + 1 < n and src[i + 1] != "\n":
                        out[i + 1] = " "
                    i += 2
                    continue
                if src[i:i + len(quote)] == quote:
                    i += len(quote)
                    break
                if not raw and src[i:i + 2] == "${":
                    depth = 1
                    i += 2
                    while i < n and depth:
                        if src[i] == "{":
                            depth += 1
                        elif src[i] == "}":
                            depth -= 1
                        i += 1
                    continue
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            continue
        i += 1
    return "".join(out)


def match_paren(masked: str, open_at: int) -> int:
    """Index just past the `)` closing the `(` at [open_at]."""
    depth = 0
    for i in range(open_at, len(masked)):
        if masked[i] == "(":
            depth += 1
        elif masked[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(masked)


def open_paren_before(masked: str, close_at: int) -> int:
    """Index of the `(` matching the `)` at [close_at]."""
    depth = 0
    for i in range(close_at, -1, -1):
        if masked[i] == ")":
            depth += 1
        elif masked[i] == "(":
            depth -= 1
            if depth == 0:
                return i
    return 0


def match_brace(masked: str, open_at: int) -> int:
    depth = 0
    for i in range(open_at, len(masked)):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(masked)


class FileScan:
    def __init__(self, path: Path, src: str):
        self.path = path
        self.src = src
        self.masked = mask(src)
        self.lines = [0]
        for i, ch in enumerate(src):
            if ch == "\n":
                self.lines.append(i + 1)
        self.tag_ranges = self._tag_ranges()
        self.classes = self._classes()
        self.methods = self._methods()
        self.widgets = self._widgets()

    def line_of(self, index: int) -> int:
        lo, hi = 0, len(self.lines) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.lines[mid] <= index:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    def _tag_ranges(self) -> list[tuple[int, int]]:
        ranges = []
        for m in TAG_CALL.finditer(self.masked):
            ranges.append((m.end() - 1, match_paren(self.masked, m.end() - 1)))
        for m in WRAPPER_CALL.finditer(self.masked):
            ranges.append((m.end() - 1, match_paren(self.masked, m.end() - 1)))
        for m in SEMANTICS_CALL.finditer(self.masked):
            open_at = m.end() - 1
            end = match_paren(self.masked, open_at)
            if IDENTIFIER_ARG.search(self.masked[open_at:end]):
                ranges.append((open_at, end))
        # `widget.tagged('id')` covers the expression it hangs off, which ends at
        # the `)` right before the dot.
        for m in TAGGED_CALL.finditer(self.masked):
            close = m.start() - 1
            while close > 0 and self.masked[close] in " \n\t":
                close -= 1
            if close <= 0 or self.masked[close] != ")":
                continue
            # Back up past the constructor name too: `.tagged` hangs off
            # `FilledButton(...)`, and the widget's own occurrence is recorded at
            # the `F`, not at the `(`. Without this every postfix tag reads as a
            # gap. Type arguments are stepped over as a matched pair rather than
            # by character class — `PopupMenuButton<String?>` has a `?` in it,
            # and stopping there put the range past the widget's own start.
            start = open_paren_before(self.masked, close)
            if start > 0 and self.masked[start - 1] == ">":
                depth, i = 0, start - 1
                while i >= 0:
                    if self.masked[i] == ">":
                        depth += 1
                    elif self.masked[i] == "<":
                        depth -= 1
                        if depth == 0:
                            break
                    i -= 1
                if i >= 0:
                    start = i
            while start > 0 and (self.masked[start - 1].isalnum()
                                 or self.masked[start - 1] in "_."):
                start -= 1
            ranges.append((max(start - 1, 0), close + 1))
        return ranges

    def _classes(self) -> list[tuple[str, int, int]]:
        found = []
        for m in CLASS_DECL.finditer(self.masked):
            brace = self.masked.find("{", m.end())
            if brace == -1:
                continue
            found.append((m.group(1), brace, match_brace(self.masked, brace)))
        return found

    def _methods(self) -> list[tuple[str, int, int]]:
        found = []
        for m in METHOD_DECL.finditer(self.masked):
            params = match_paren(self.masked, m.end() - 1)
            rest = self.masked[params:params + 200]
            body = rest.find("{")
            arrow = rest.find("=>")
            if arrow != -1 and (body == -1 or arrow < body):
                # Expression body: runs to the `;` outside every bracket.
                depth, i = 0, params + arrow
                while i < len(self.masked):
                    ch = self.masked[i]
                    if ch in "([{":
                        depth += 1
                    elif ch in ")]}":
                        depth -= 1
                    elif ch == ";" and depth == 0:
                        break
                    i += 1
                found.append((m.group(1), params, i))
            elif body != -1:
                start = params + body
                found.append((m.group(1), start, match_brace(self.masked, start)))
        return found

    def method_at(self, index: int) -> str | None:
        for name, start, end in self.methods:
            if start < index < end:
                return name
        return None

    def _widgets(self) -> list[dict]:
        found = []
        for m in WIDGET_CALL.finditer(self.masked):
            name = m.group(1)
            if m.group(2) in NOT_WIDGETS:
                continue
            open_at = m.end() - 1
            end = match_paren(self.masked, open_at)
            if name in NEEDS_CALLBACK and not CALLBACK.search(self.masked[open_at:end]):
                continue
            # A greyed-out menu row — the model dropdown's series headings —
            # takes no tap, so there is nothing for a name to describe. Only
            # menu rows: on an anchor the same argument would be the *menu*
            # holding a disabled row, which is still pressable itself.
            if name in POPUP_ITEMS and DISABLED_ARG.search(
                    self.masked[open_at:end]):
                continue
            found.append({
                "kind": name,
                "start": m.start(),
                "end": end,
                "line": self.line_of(m.start()),
                "text": self.src[m.start():m.end()].strip(),
            })
        return found

    def covered_by_tag(self, index: int) -> bool:
        return any(start < index < end for start, end in self.tag_ranges)

    def tag_carried_by(self, start: int, end: int) -> bool:
        """A tag the widget takes with it: written inside its own call, or hung
        off it postfix. Any wider range belongs to an ancestor — which is what a
        menu row leaves behind when the framework rebuilds it in a route.
        """
        return any(s >= start - 1 and e <= end for s, e in self.tag_ranges)

    def class_at(self, index: int) -> str | None:
        for name, start, end in self.classes:
            if start < index < end:
                return name
        return None


def scan(root: Path, include_wear: bool) -> tuple[list[FileScan], dict, dict]:
    scans = []
    for path in sorted(root.rglob("*.dart")):
        rel = path.relative_to(root.parent)
        if any(skip in path.name for skip in SKIP_FILES):
            continue
        if not include_wear and "/wear" in str(rel):
            continue
        scans.append(FileScan(rel, path.read_text()))

    # Where each widget class is instantiated, so class-level coverage can be
    # resolved across files. A private class is visible only inside its own
    # library, and several screens have their own `_FilterButton` — so private
    # names are keyed by library, not globally. `part of` files share the key of
    # the file they belong to.
    library = {}
    for s in scans:
        # Raw source: the masked copy has blanked the file name out of the string.
        m = re.search(r"^part\s+of\s+'([^']+)'", s.src, re.M)
        library[s.path] = str(s.path.parent / m.group(1)) if m else str(s.path)

    def key(scan: FileScan, name: str) -> str:
        return f"{library[scan.path]}::{name}" if name.startswith("_") else name

    call_sites: dict[str, list[tuple[FileScan, int]]] = {}
    declared = {key(s, name) for s in scans for name, _, _ in s.classes}
    # Builder methods are keyed by library even when public: a name collision
    # only makes "every call site is covered" harder to satisfy, so it errs
    # toward reporting a gap rather than hiding one.
    methods = {f"{library[s.path]}::{name}" for s in scans for name, _, _ in s.methods}
    for s in scans:
        for m in re.finditer(r"\b(_?\w+)\s*\(", s.masked):
            name, at = m.group(1), m.start()
            class_key = key(s, name)
            method_key = f"{library[s.path]}::{name}"
            # A declaration is not a call site: a constructor sits in the class
            # of its own name, a builder method's own header sits outside its
            # body (so `method_at` returns None right where it is declared).
            if class_key in declared and s.class_at(at) != name:
                call_sites.setdefault(class_key, []).append((s, at))
            elif method_key in methods and not _is_method_header(s, name, at):
                call_sites.setdefault(method_key, []).append((s, at))
    return scans, call_sites, library


def _is_method_header(scan: FileScan, name: str, at: int) -> bool:
    return any(n == name and start >= at for n, start, _ in scan.methods
               if abs(start - at) < 200)


def resolve(scans: list[FileScan], call_sites: dict, library: dict) -> set[str]:
    """Classes whose every instantiation is covered — their innards inherit.

    Iterated to a fixpoint: a class tagged only inside another covered class is
    covered too.
    """
    def owner_key(scan: FileScan, name: str) -> str:
        return f"{library[scan.path]}::{name}" if name.startswith("_") else name

    covered: set[str] = set()
    changed = True
    while changed:
        changed = False
        for name, sites in call_sites.items():
            if name in covered or not sites:
                continue
            def named(scan: FileScan, index: int) -> bool:
                if scan.covered_by_tag(index):
                    return True
                owner = scan.class_at(index)
                if owner is not None and owner_key(scan, owner) in covered:
                    return True
                method = scan.method_at(index)
                return (method is not None
                        and f"{library[scan.path]}::{method}" in covered)

            ok = all(named(scan, index) for scan, index in sites)
            if ok:
                covered.add(name)
                changed = True
    return covered


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--wear", action="store_true", help="include lib/wear")
    ap.add_argument("--limit", type=int, default=0, help="max gaps to list")
    ap.add_argument("--kind", help="only this widget kind, e.g. TextField")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[3] / "lib"
    if not root.is_dir():
        print(f"no lib/ under {root.parent}", file=sys.stderr)
        return 2

    scans, call_sites, library = scan(root, args.wear)
    inherited_classes = resolve(scans, call_sites, library)

    total = {"tagged": 0, "inherited": 0, "uncovered": 0}
    by_kind: dict[str, dict[str, int]] = {}
    gaps: list[dict] = []

    for s in scans:
        for w in s.widgets:
            if args.kind and w["kind"] != args.kind:
                continue
            owner = s.class_at(w["start"])
            owner_id = (f"{library[s.path]}::{owner}"
                        if owner and owner.startswith("_") else owner)
            method = s.method_at(w["start"])
            method_id = f"{library[s.path]}::{method}" if method else None
            if w["kind"] in POPUP_ITEMS:
                state = ("tagged" if s.tag_carried_by(w["start"], w["end"])
                         else "uncovered")
            elif s.covered_by_tag(w["start"]):
                state = "tagged"
            elif owner_id in inherited_classes or method_id in inherited_classes:
                state = "inherited"
            else:
                state = "uncovered"
            total[state] += 1
            by_kind.setdefault(w["kind"], {"tagged": 0, "inherited": 0, "uncovered": 0})
            by_kind[w["kind"]][state] += 1
            if state == "uncovered":
                gaps.append({
                    "file": str(s.path),
                    "line": w["line"],
                    "kind": w["kind"],
                    "owner": owner,
                    "text": w["text"],
                })

    gaps.sort(key=lambda g: (g["file"], g["line"]))

    if args.json:
        print(json.dumps({"totals": total, "by_kind": by_kind, "gaps": gaps}, indent=2))
        return 0

    counted = sum(total.values())
    print(f"Interactive widgets in lib/: {counted}")
    print(f"  named directly       {total['tagged']:>5}")
    print(f"  inherits a name      {total['inherited']:>5}")
    print(f"  UNNAMED              {total['uncovered']:>5}")
    print()
    print(f"{'kind':<26}{'named':>7}{'inherit':>9}{'unnamed':>9}")
    for kind in sorted(by_kind, key=lambda k: -by_kind[k]["uncovered"]):
        c = by_kind[kind]
        print(f"{kind:<26}{c['tagged']:>7}{c['inherited']:>9}{c['uncovered']:>9}")

    if not gaps:
        print("\nNothing unnamed.")
        return 0

    worst = {}
    for g in gaps:
        worst[g["file"]] = worst.get(g["file"], 0) + 1
    print("\nWorst files:")
    for path, count in sorted(worst.items(), key=lambda kv: -kv[1])[:10]:
        print(f"{count:>5}  {path}")

    print(f"\nUnnamed ({len(gaps)}):")
    shown = gaps[: args.limit] if args.limit else gaps
    current = None
    for g in shown:
        if g["file"] != current:
            current = g["file"]
            print(f"\n  {current}")
        owner = f" in {g['owner']}" if g["owner"] else ""
        print(f"    {g['line']:>5}  {g['kind']}{owner}")
    if args.limit and len(gaps) > args.limit:
        print(f"\n  … {len(gaps) - args.limit} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
