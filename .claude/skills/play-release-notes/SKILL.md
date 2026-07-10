---
name: play-release-notes
description: Generate Google Play "What's new" release notes (Informacje o wersji) as a diff between the newest app version and the previous one — concise, user-facing changes in English and Polish, in the <en-US>/<pl-PL> format. Use when preparing a Play Store release, writing release notes / changelog / "what's new" / whats new / release info for a new version.
---

# Google Play release notes (EN + PL)

Produces the text for the Play Console **"What's new in this version"** field:
concise, user-facing bullets describing what changed since the previous
release, in English and Polish, wrapped in the BCP-47 language tags Play
expects (`<en-US>`, `<pl-PL>`).

Two steps: a script gathers the verified changes, then **you** (the agent) turn
them into human, non-technical notes. The script never writes the notes — good
release notes need judgment and translation.

Paths below are relative to the repo root.

## Step 1 — collect the changes

Versions are lightweight `vX.Y.Z` git tags; the range is
`<previous tag>..<latest tag>`, and commits follow Conventional Commits, so the
script keeps `feat`/`fix`/`perf` and sets aside `chore`/`docs`/`refactor`/etc.

```bash
.claude/skills/play-release-notes/collect-changes.sh
```

Variants:

```bash
.claude/skills/play-release-notes/collect-changes.sh HEAD          # unreleased work vs latest tag
.claude/skills/play-release-notes/collect-changes.sh v0.11.0 v0.10.1  # explicit range
```

It prints the version range, the **user-facing** commits with their bodies
(bodies often list several squashed changes — read them), and the skipped
internal commits (for completeness, so nothing is dropped silently).

## Step 2 — author the notes

Write from the "USER-FACING" list. Rules:

- **User-facing only.** Skip anything a user can't perceive: version bumps,
  build/CI/release-pipeline fixes, refactors, tests, docs. A `fix(build)` or
  `fix(release)` is internal even though it's a `fix` — drop it.
- **Concrete, not a commit dump.** Say what changed for the user. "Redesigned
  home screen widgets" — not "feat(widget): redesign … #5FE08A accent". Never
  leak code identifiers, hex colors, file names, or Conventional-Commit prefixes.
- **Merge & prioritize.** Fold tiny tweaks into one "UI polish" bullet; lead
  with the biggest change. Aim for 3–6 bullets.
- **Bilingual, not machine-translated.** Write natural Polish and natural
  English independently. Keep app content PEGI-16 clean (see project rules).
- **Length.** Play caps each language at **500 characters**. Stay well under.
- **Format** exactly as below (bullets with `•`); paste the whole block into the
  Play Console field.

```
<en-US>
• ...
• ...
</en-US>
<pl-PL>
• ...
• ...
</pl-PL>
```

## Worked example (v0.10.0 → v0.10.1)

`collect-changes.sh` returned a widget redesign + new multi-printer widget
(`feat`), a thumbnail/maintenance/UI fix, and a remember-me/search-spacing fix;
it skipped `chore: bump version`. Those became:

```
<en-US>
• Redesigned home screen widgets with a fresh dark look, plus a new multi-printer widget that shows all your printers at once.
• Print thumbnails now reload automatically instead of disappearing after a while.
• Maintenance sections can be collapsed for a tidier view.
• UI polish: clearer "remember me" checkbox and better search bar spacing.
</en-US>
<pl-PL>
• Odświeżony, ciemny wygląd widgetów na ekranie głównym oraz nowy widget wielu drukarek pokazujący wszystkie drukarki naraz.
• Miniatury wydruków odświeżają się automatycznie zamiast znikać po pewnym czasie.
• Sekcje konserwacji można teraz zwijać dla czytelniejszego widoku.
• Poprawki interfejsu: wyraźniejszy checkbox „zapamiętaj mnie" i lepsze odstępy paska wyszukiwania.
</pl-PL>
```

## Gotchas

- **A `fix` type isn't automatically user-facing.** `fix(build)`,
  `fix(release)`, `fix(ci)` are plumbing — the script lists them under
  user-facing (they match `fix`), but you must drop them. Read the subject.
- **Read commit bodies, not just subjects.** One squashed `fix:` commit often
  bundles 2–3 distinct user-visible changes worth separate bullets.
- **Latest tag may equal HEAD, or HEAD may be ahead of it.** With no args the
  script skips tags pointing at the same commit as the newest and compares the
  two most recent distinct releases. If you've committed post-tag work you want
  to preview, pass `HEAD` explicitly.
- The release pipeline is `just ship X.Y.Z` (bump + tag via Codeberg). Generate
  notes **after** the tag exists, or pass `HEAD` to preview before shipping.
