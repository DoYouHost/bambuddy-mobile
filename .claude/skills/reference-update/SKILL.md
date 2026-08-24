---
name: reference-update
description: Triage what changed in the bambuddy server reference since the last review and turn it into work items for this app — regressions first, then half-done, then missing. Use when catching up with the server's dev branch, when the weekly server-drift job needs its report, or when asking "what did maziggy change that we have to follow".
---

# Server reference triage

The server moves faster than the app: 102 commits in the range this was first
built for, of which 20 files could move the API contract. This skill turns that
range into a list a person can work from, and — as much as it turns anything
into work — keeps the app from silently breaking against a server that has
already shipped.

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

## Step 3 — two files, and the difference between them

**`.server-drift/report.md` — what this range changed.** Posted as a comment and
never edited again. The record: the range examined, the items found, and every
item struck off the standing list along with the evidence that struck it.

**`.server-drift/open-items.md` — what is still owed.** It replaces the issue
body wholesale. The version standing before this run is at
`.server-drift/open-items-current.md`: start from it, remove what is now done,
append what this range added, leave the rest alone.

An item therefore leaves the list in the run it gets finished. A to-do list that
only grows is not a to-do list, and after half a year of appending nobody could
tell from the issue what is actually left. Nothing is lost by the removal: the
comment from that week says which item went and why, with the `file:line` that
proved it. The record is append-only; the list is not.

Change nothing else — no source files, no `app_en.arb`, no branch. Those two
files are the whole output.

Four sections in the report, in this order, because the order is the priority:

**1. Regressions.** A route or field that vanished server-side and that our code
still depends on. This is the only category that breaks the app for someone who
has already updated their server, and it is the easiest to miss, because a diff
invites you to read what was added. If there are none, say so in one line.

**2. Half-done.** The route is in `endpoints.dart` but nothing calls it; the
field is in the model but no screen shows it. Cheapest work in the list and
normally invisible.

**3. Missing.** Full items, in the format below.

**4. Struck off.** What was on the standing list and is not any more, or what
this range brought that we already had — each with the `file:line` that shows
it. This section belongs to the report only. It never travels into
`open-items.md`; that is the point of it.

Sections 1–3 are what `open-items.md` carries forward, in the same order.

## Item format

```markdown
### <short title> — <XS|S|M|L>

**What changed.** The server side, with the route or field named and the file
cited: `backend/app/api/routes/x.py:NN`.

**Why it matters to us.** Our side, with our own file and line.

**Do.** The concrete steps.

**Done when.** The observable result.
```

## Rules that decide what goes in

- **Evidence or it stays on the list.** Never strike an item off without a
  `file:line` from our tree. A false "done" disappears and comes back as a bug
  months later; a false "to do" costs ten seconds of reading.
- **Every removal is accounted for.** An item may leave `open-items.md` only
  through a line in that run's section 4. An item that quietly differs between
  the old body and the new one is a bug in the triage, not tidying.
- **`dev` is the only baseline.** Work sitting on an unmerged feature branch
  counts as not done. That is deliberate: it repeats an item you are mid-way
  through rather than hiding one that was abandoned.
- **Every item must survive an older server.** The app talks to servers the
  maintainer does not control, so a new field is read behind a null check and a
  new route behind a probe — see the compatibility rules in
  [CLAUDE.md](../../../CLAUDE.md). An item that cannot be built that way is not
  an item: it is a question for the maintainer, and it says so.
- **The CHANGELOG is a claim.** The server's author explains each change at
  length and is usually right, but the diff is the evidence. Check anything you
  act on.
- **A new ceiling is not yours to pick.** A limit, cap, timeout or threshold —
  including one that follows obviously from what the server now does — goes into
  the item as a question, never as a decided number.
- **One contract change, one item.** Do not bundle unrelated changes because
  they landed in the same commit.
