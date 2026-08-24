---
name: reference-update
description: Triage what changed in the bambuddy server reference since the last review into a one-line-per-change checklist — regressions first, then half-done, then missing. Use when catching up with the server's dev branch, when the weekly server-drift job needs its report, or when asking "what did maziggy change that we have to follow".
---

# Server reference triage

The server moves faster than the app: 102 commits in the range this was first
built for, of which 20 files could move the API contract. This skill turns that
range into a checklist: one line per change, sorted into the category that says
how urgent it is. It is an index of what moved, not an analysis of it — the
analysis happens when someone picks a line up and reads the code.

Paths are relative to the repo root.

## Step 1 — the baseline

The last triaged server commit lives in the GitHub issue labelled
`server-drift`, in a marker block in its body:

```sh
gh issue list --label server-drift --state all --limit 1 --json number,state,body
```

No issue means nothing has been triaged yet, and the baseline is a decision, not
a guess — ask for the commit to start from rather than picking one.

## Step 2 — the facts

```sh
tool/server-ref-diff.sh --from <baseline-sha>
```

It writes two files. **`.server-drift/facts.md`** is the one to read whole: the
routes and schema fields that appeared or vanished and, for each of them,
whether `lib/core/api/endpoints.dart` names that route and whether anything
under `lib/` reads that JSON key. **`.server-drift/diff.md`** is the filtered
diff those facts were read from — thousands of lines, so open the parts an item
actually depends on.

Those greps answer *exists*, never *is wired to anything a user can see*. A key
named `description`, `id` or `status` is read in a dozen unrelated models, which
is why the facts name the files rather than saying yes: read them before
believing a hit.

## Step 3 — two files

**`.server-drift/open-items.md` — the checklist.** It replaces the issue body
wholesale. The version standing before this run is at
`.server-drift/open-items-current.md`: start from it, strike off what is now
done, append what this range added, and copy every surviving line
**byte-for-byte**.

**`.server-drift/report.md` — what this range did to the checklist.** Posted as
a comment and never edited again. It is a delta, never a copy: the items it adds
are already above it in the body, so it counts them instead of repeating them.

So the checklist shrinks as work gets done, and nothing is lost by the
shrinking — the comment from that week says what went and why. The record is
append-only; the checklist is not.

Change nothing else — no source files, no `app_en.arb`, no branch. Those two
files are the whole output.

## The format: one line, one checkbox

```markdown
## Regressions
- [ ] `GET /printers/{id}/foo` — route gone; called from `endpoints.dart:412`

## Half-done
- [ ] `PrinterStatus.ams_switch_inlet` — parsed in `printer_status.g.dart:88`, shown nowhere

## Missing
- [ ] `hms_errors[].description` — new field; `printer_status.dart:788` still reads `message`
- [ ] `GET /scheduled-dryings` — new route, not in `endpoints.dart`
```

Each line names what moved on the server and where we stand, with a `file:line`
whenever there is one. **That is the entire entry.** No "what changed", no "why
it matters", no "do", no "done when", no size tag. Whoever picks an item up
reads the code; a paragraph explaining the code to them takes longer to read
than the code.

One short parenthetical is the budget for a line that genuinely cannot be
understood without one. Anything longer is not an item but a question: put it
under the list, under `## Questions`, in one sentence.

The three sections mean:

- **Regressions** — a route or field that vanished server-side and that our code
  still depends on. The only category that breaks the app for someone who has
  already updated their server, and the easiest to miss, because a diff invites
  you to read what was added.
- **Half-done** — the route is in `endpoints.dart` but nothing calls it; the
  field is in the model but no screen shows it.
- **Missing** — everything else that is still owed.

An empty section keeps its heading and says `- none`.

The report is short by construction — on a first run it is three lines:

```markdown
`7c117dc6` → `ed84f0f7`, 102 commits, 24 contract files.

Added 7 items: 0 regressions, 1 half-done, 6 missing.
Already covered: 3 (`endpoints.dart:412`, `queue_item.dart:257`, `archive.g.dart:88`).

Struck off:
- `POST /printers/{id}/files/download-job` — done in `printer_files_repository.dart:50`
```

**Never restate the items it added.** They are in the checklist directly above
the comment; printing them twice is how the first version of this job produced
one list in the body and the same list underneath it. What only the comment can
say is what *left* — and that gets a line each, with its evidence.

## Rules that decide what goes in

- **A list in the wrong shape gets converted, not preserved.** If the standing
  list is prose rather than one line per change, rewrite every entry into a
  checkbox line — keeping each item and its tick — and say in the report that
  you converted it. This is the one exception to copying lines byte-for-byte.
- **A ticked box is the maintainer speaking.** Never untick one, never remove a
  ticked line without saying so in the report, and never reword a line you are
  carrying forward — a rewritten line reads as a new one and loses its tick.
- **Evidence or it stays on the list.** Never strike an item off without a
  `file:line` from our tree. A false "done" disappears and comes back as a bug
  months later; a false "to do" costs ten seconds of reading.
- **Every removal is accounted for.** A line may leave `open-items.md` only
  through the report's *Struck off* section. A line that quietly differs between
  the old body and the new one is a bug in the triage, not tidying.
- **`dev` is the only baseline.** Work sitting on an unmerged feature branch
  counts as not done. That is deliberate: it repeats an item you are mid-way
  through rather than hiding one that was abandoned.
- **The CHANGELOG is a claim.** The server's author explains each change at
  length and is usually right, but the diff is the evidence. Check anything you
  put on the list.
- **What is not yours to decide gets `(needs a decision)`** and nothing more: a
  limit, cap, timeout or threshold; anything that cannot be built so an older
  server still works (see [CLAUDE.md](../../../CLAUDE.md)); anything that is a
  product call rather than a contract change.
- **One contract change, one line.** Do not bundle unrelated changes because
  they landed in the same commit.
