---
name: log-coverage
description: Report which buttons, text fields, dropdowns, list tiles and other controls in lib/ are still missing a diagnostic-log identifier (logTag / .tagged), so taps on them record as a bare role. Use when auditing bug-report log coverage, asking "what is not logged yet", "which controls have no name", after adding screens, or before shipping a change to the bug-report feature.
---

# Diagnostic-log coverage

The bug-report log records `Semantics(identifier:)` and **never** accessibility
labels — a merged label is the whole content of a card (model names, file names,
spool names) and the log ends up in a public issue. So an unnamed control records
as `{"evt":"tap","role":"button"}` and nothing more. This skill finds those.

Paths are relative to the repo root.

## Step 1 — run the scan

```bash
python3 .claude/skills/log-coverage/log_coverage.py
```

| flag | effect |
|---|---|
| `--limit N` | list only the first N gaps (the summary is always complete) |
| `--kind TextField` | one widget kind |
| `--wear` | include `lib/wear` (excluded by default — the recorder is a phone feature) |
| `--json` | machine-readable, for counting per file or feeding a diff |

Output: totals, a table per widget kind, the worst files, then every gap as
`file:line kind in _OwnerClass`.

## Step 2 — read it honestly

Three states, matching how the probe resolves a name at runtime:

- **named directly** — a `logTag(...)` / `.tagged(...)` encloses it (or the
  `…Material` variant, which adds the filament type as a separate `mat` field —
  the only on-screen content the log carries, and only from a closed list).
- **inherits a name** — something above it is named and the identifier reaches
  down: its widget class or builder method is tagged at every call site
  (`_FilterButton` is wrapped where it is used; `Widget _iconButton(...)` inherits
  from its callers), a raw `Semantics(identifier: …)` encloses it (the recording
  bar uses that, because it also sets a label), or it is an argument to
  `dashAppBar`, which names the whole bar `chrome.appbar`. Resolved to a fixpoint
  across files, with private names scoped to their library — several screens have
  their own `_FilterButton`.
- **UNNAMED** — nothing reaches it.

One kind never inherits: a **row of a menu** (`PopupMenuItem`,
`CheckedPopupMenuItem`, `DropdownMenuItem`, `DropdownMenuEntry`,
`MenuItemButton`). The framework rebuilds it in a route of its own, so the tag on
the anchor — the `PopupMenuButton`, the `DropdownMenu`, the field around it —
stays behind in the main tree and never reaches the row. Only a tag the row
carries with it counts, and the scanner scores those rows on that rule alone.

**A gap is a question, not a bug.** The scanner is a text scan, not the analyzer:
it cannot follow a widget assigned to a local variable and inserted into a tagged
tree later (the spool form's core-weight field does that), nor one passed through
a `Widget` field. Open the file before believing the line — and when the gap is
real but the fix belongs in the scanner, fix the scanner.

`lib/` (phone flavour) reports **zero** unnamed controls; `--wear` still lists the
watch app, which has no recorder. The one control the scan leaves out is
`SnackBarAction`: `SnackBar.action` is typed to it, so it cannot be wrapped and
has no child to tag — the two in the app record as a bare `button`, and naming
them would mean replacing the snackbar.

## Step 3 — decide what actually needs a name

The rule this project settled on after four live runs:

> **Name what decides something.** Confirmations, choices, toggles, destructive
> actions, anything where the log has to answer "what did they pick?".

A plain text field is fine unnamed: `role":"textField"` plus the sheet it sits in
already says what happened, and the typed content is never logged. Form fields
are worth naming only when the form is long enough that "which field" matters.

Deliberately never named: anything carrying user data in the id — ids are
lowercase, dotted and data-free (`archive.card`, never `archive.card.MyModel`);
every row of a list shares one id, because which row it was is not what a bug
report needs.

The sweep went past that rule for form fields in the end: a field costs one line
to name and "which field were they in when it broke" turned out to be worth it on
the setup and login screens, so the rest followed for consistency.

## Step 4 — add the tag

```dart
logTag('area.thing', SomeWidget(...))     // wraps
SomeLongWidget(...).tagged('area.thing')  // postfix, for long trees
confirmDialog(context, id: 'files.delete_confirm', ...)  // names both buttons
logTagMaterial('inventory.spool', spool.material, SomeWidget(...))  // adds mat=PETG
```

Gotchas that have already cost time here:

- **`PopupMenuItem` cannot be wrapped** — `Semantics` is not a `PopupMenuEntry`.
  Tag its `child:`; the identifier still resolves, because the probe carries what
  it finds on the hit path (there is a test for exactly this).
- **`DropdownMenuEntry` is not a widget at all.** Its tag goes on `labelWidget:`,
  which replaces the plain `Text(label)` the menu would have drawn — keep the
  text identical, `label:` is still what the field shows and filters on.
- **Tag the anchor as well as the rows.** They are two separate presses: opening
  the menu and choosing from it. The anchor's tag names the first, and it is not
  redundant with the rows precisely because it never reaches them.
- **One `NavigatorObserver` per `Navigator`** — unrelated to tagging, but the same
  file: never share a `ModalObserver` instance.
- **A misplaced `.tagged(...)` type-checks.** It lands happily on a `ButtonStyle`
  or an `Icon` and the analyzer stays silent. After adding tags, re-run the scan
  and check the id appears where you meant it — the constructor under each tag is
  worth eyeballing.

## Step 5 — prove it on the device, not in the head

Coverage is a static number; the log is the truth. After tagging, record a
session on the phone, walk the screens you touched, and read the JSONL: every
`role` without an `id` is a control the scan may have called covered.
Do not build or run the app yourself for this — hand the change over and ask.
