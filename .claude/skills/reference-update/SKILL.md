---
name: reference-update
description: Triage what changed in the bambuddy server reference since the last review into a one-line-per-change checklist sorted by urgency — what is already broken, what is a cheap win, what is a feature, what only needs knowing. Use when catching up with the server's dev branch, when the weekly server-drift job needs its report, or when asking "what did maziggy change that we have to follow".
---

# Server reference triage

The server moves faster than the app: 102 commits in the range this was first
built for, of which 20 files could move the API contract. This skill turns that
range into a checklist: one line per change, sorted into the section that says
how urgent it is, so a glance at the issue answers "what do I fix this week". It is an index of what moved, not an analysis of it — the
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

**Neither file is optional.** Write both before finishing, even half-checked —
the job fails without them, and a partial checklist is worth more than none. And
change nothing else: no source files, no `app_en.arb`, no branch. Those two files
are the whole output.

## The format: one line, one checkbox

```markdown
## Broken now
- [ ] `GET /printers/{id}/files` — restricted API keys now get 403; the file manager shows a generic error — `printer_file_manager_screen.dart:88` — S

## Cheap win
- [ ] `hms_errors[].description` — server sends the fault sentence; `HmsError` has no field for it — `printer_status.dart:770` — S

## Feature
- [ ] `/scheduled-dryings` — schedule a dry run; new repository, sheet entry, l10n — M

## Watch only
- `PATCH /archives/{id}` rejects a weight over 100 kg — nothing to change, but it is the answer if a 422 shows up in a report

## Questions
- Keep-warm settings are readable but we have no settings writer — build one, or leave them?
```

**One line per change: what moved, what it means for us, `file:line` when there
is one, and a size.** No "what changed", no "why it matters", no "do", no "done
when" — whoever picks a line up reads the code, and a paragraph explaining the
code to them takes longer than the code. A line that cannot be understood
without a caveat gets one short parenthetical; anything longer belongs under
`## Questions` as one sentence.

Sizes are `XS` (a field and its test), `S` (a field plus one screen), `M` (a
route, a form, l10n), `L` (a screen or a parked branch).

## The five sections, and what decides which one a line lands in

The point of the sections is that a person scanning the issue can tell, without
reading a word of prose, what to do this week and what can wait.

**`## Broken now`** — the app already misbehaves against a server that has
shipped this. A route or field we call is gone; a gate now answers **403** where
the request used to work; a status code we surface as a generic error; a field
whose meaning changed under a name we still read. **Every line here says what
the user sees**, because that is what decides whether it is worth a hotfix.

**`## Cheap win`** — mechanical and small, with obvious value: a new field to
parse, a route already in `endpoints.dart` that nothing calls, a field parsed
into a model that no screen shows.

**`## Feature`** — a new surface. UI, l10n, diagnostic ids, a product call about
whether we want it at all.

**`## Watch only`** — nothing to do, and that is the finding. A validation rule,
a migration that shifts stored numbers, a limit — the things that explain a
future bug report. No checkbox: these are not work.

"Nothing to do" is a claim about **our** call sites, so every line here names
where our code gets that data: the constant in `endpoints.dart`, or the model
field, or the fact that we call none of that file's routes — which `facts.md`
states outright. A line that says "the app never did this itself" without a
citation is how a server-side plug ranking got filed as harmless while
`smart_plugs_providers.dart:46` was still picking the first visible plug and
`endpoints.dart` had never heard of `/smart-plugs/by-printer/{id}`.

**`## Questions`** — one sentence each, for what is not yours to decide.

An empty section keeps its heading and says `- none`.

Where each kind of finding comes from in `facts.md`:

| facts.md section | usually lands in |
|---|---|
| routes removed, marked `[WE CALL THIS]` | Broken now |
| route bodies → gates touched | Broken now (403) — check who the gate admits |
| route bodies → error codes on added lines | Broken now if we word that code generically |
| fields changed in place, marked `[WE PARSE THIS]` | Broken now or Cheap win |
| fields added, key read nowhere | Cheap win or Feature |
| routes added | Cheap win if one call, Feature if a screen |
| route bodies → functions added | read the diff: ranking and gating changes hide here |
| route bodies → **we call routes in this file** | decides Watch only from real work — this file serves our traffic |
| route bodies → permissions named on changed lines | what an API key may now do; check the scope map in the diff |
| CHANGELOG entries with no footprint above | Watch only or Cheap win — see the rule below |

The report carries the same sections and the same one-line entries, plus
**Struck off**.

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
- **"Broken now: none" is a claim, not a default.** It is only allowed with a
  sentence saying what was checked and found harmless — the gates that moved,
  the codes that appeared, the fields that changed shape. An empty section
  because nobody looked reads exactly like an empty section because nothing is
  wrong, and the first version of this job filed "Regressions: none" over a
  per-printer key allowlist that had started answering 403.
- **`dev` is the only baseline.** Work sitting on an unmerged feature branch
  counts as not done. That is deliberate: it repeats an item you are mid-way
  through rather than hiding one that was abandoned.
- **The CHANGELOG is a claim, and it is also the only place some changes
  exist.** A response that keeps its shape and changes its meaning — a field
  that starts being populated, a flag that survives a disconnect, a listing that
  now reports why it is empty — leaves no trace in routes, fields, gates or
  status codes. Read the CHANGELOG section of `facts.md` for entries that match
  nothing above it, and file those too. Everything you take from it still needs
  the diff as evidence: the author is usually right, and the diff is what
  proves it.
- **What is not yours to decide gets `(needs a decision)`** and nothing more: a
  limit, cap, timeout or threshold; anything that cannot be built so an older
  server still works (see [CLAUDE.md](../../../CLAUDE.md)); anything that is a
  product call rather than a contract change.
- **One contract change, one line.** Do not bundle unrelated changes because
  they landed in the same commit.
