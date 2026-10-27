# Rendered accessibility tests

Every app screen is rendered in a widget test and held to Flutter's accessibility
guidelines (`textContrastGuideline`, `androidTapTargetGuideline`,
`labeledTapTargetGuideline`) under three accents, both themes, and three text sizes.
This file is the state of that work, the facts it rests on, and what is left. Read it
before touching `test/a11y/` or fixing a finding it reports.

Branch `test/a11y-guidelines`. The harness is `test/a11y/a11y_harness.dart` (every
public name starts with `a11y`); each feature has its own `*_a11y_test.dart`.

## Setting up a machine

The work runs against the sibling checkout of the shared packages, not a tagged
release:

1. Clone `git@github.com:DoYouHost/app-shared.git` next to this repository as
   `../DoYouHost.app-shared` and keep it on `master`.
2. Create the git-ignored `pubspec_overrides.yaml` in this repository:

   ```yaml
   dependency_overrides:
     dash_kit:
       path: ../DoYouHost.app-shared/packages/dash_kit
     dash_ui:
       path: ../DoYouHost.app-shared/packages/dash_ui
     app_report_ui:
       path: ../DoYouHost.app-shared/packages/app_report_ui
   ```
3. `flutter pub get` rewrites the tracked `pubspec.lock` for that machine. It shows as
   modified on purpose: **never commit it, never stash it.**
4. `just hooks` once per clone, then `flutter analyze` and
   `flutter test test/a11y/a11y_contrast_judge_test.dart` must pass before any work.

## Running it

- The whole suite: `just test-a11y` (one `flutter test --concurrency=4` under a
  12 GB scope). On the maintainer's laptop: 726-732 s against 1409 s one file at a
  time, about 6 GiB. Another machine will time differently.
- Several `flutter test` processes at once corrupt the shared `build/test_cache`; the
  parallelism is inside the one run. Kill by PID, never `pkill -f`.
- The rest of the tests: `flutter test --concurrency=4 test/features test/l10n
  test/core` (4973 tests, 194 s on the same laptop).
- Contrast report (analysis only, writes nothing unless asked):
  `just test-a11y "--dart-define=A11Y_CONTRAST_REPORT=/tmp/x.jsonl test/a11y"`
  appends one JSON line per judged finding: verdict, text, foreground, grounds,
  contrast by the text's own colours, needed ratio, token and widget chain.

## What the harness does

- `a11ySurface` runs a screen under three accents in both themes at 100 % text, plus
  150 % and 200 % under the first accent in light (`a11yTextScales`). Widget tests
  elsewhere pass at text scale 1.0, 1.5 and 2.0 too (AGENTS.md).
- Widget tests run in the **app theme**: `plApp` in `test/helpers.dart` passes
  `buildDashThemeData`. Before, they used the default Material theme and could not
  see anything that depends on it (icon scaling, button padding, fonts).
- A text scale reaches a sheet only through `MaterialApp.builder`: a sheet is a route
  above the card, so scaling the card does not scale it.

## How `textContrastGuideline` really works

Verified in the `flutter_test` source; do not re-derive it.

- It never reads the colour of the text. It takes the pixels of the node's rect (one
  pixel per dp, inflated by 4), splits them by HSL lightness at the mean and compares
  the commonest light colour with the commonest dark one (`_ContrastReport`; its own
  class doc calls it "very naive partitioning"). On 11-14 dp semi-transparent text most
  glyph pixels are blends, so it fails text that passes at 5:1 by its own colours.
- It skips disabled nodes (`isEnabled == Tristate.isFalse`), invisible, hidden and
  merged-into-parent nodes. It finds the text with `find.text(label)`, so a node whose
  label is several merged `Text`s matches nothing and is **never checked**.
- It is the tool Flutter documents (flutter.dev, accessibility testing) and there is
  no other contrast evaluator in `flutter_test`. WCAG 1.4.3 exempts inactive
  components; the framework's way to say "inactive" is the semantics disabled flag. A
  dimmed label therefore carries `Semantics(enabled: false)` (or is part of a disabled
  control). It is not exempted in the test.
- Thresholds are the framework's: 3:1 from 18, or from 14 bold; 4.5:1 otherwise.

Our wrapper, `_ContrastBesideMisreads` in the harness: the guideline stays the judge.
A finding has to fail at three paint offsets (0.37 and 0.71 dp re-measure), and then
`judgeContrastFindings` (`test/a11y/a11y_contrast_report.dart`) must not clear it. It
finds the paragraphs (a `Text` or a text field) inside the node's bounds, reads every
span's colour (parents merged, ancestor opacity applied), takes the ground from the
paragraph's own box without the glyph colours (a ring around it only as a fallback) and
compares. A node is an **artefact** only when every paragraph passes by its own
colours; no paragraph or no ground is **inconclusive** and the guideline's finding
stands. A device pixel ratio other than 1 judges nothing. The judge has its own tests
(`a11y_contrast_judge_test.dart`; they use the real face `Manrope`, because the test
default paints every glyph as a solid block).

On the first honest measurement 88 % of 1865 contrast findings were artefacts, 7 %
genuine, 4 % unmatched. A model consultation (Gemini 4 Argon) confirmed the
mechanism; one claim of it, about Android's two-stage `TextContrastCheck`, was not
verified.

## Decisions (do not reopen)

- A control that does not fit beside its label goes under it and **fills the width in
  equal shares**; never `Wrap(spaceBetween)`, never a control hugging the left edge.
  `BesideOrBelow`, `ButtonPair` and `ContentGrid` (`dash_kit`) do this. Tiles are laid
  out by content (`ContentGrid`: rows as tall as the tallest tile, columns from
  `minTileWidth`, optional `maxColumns`), never a fixed aspect ratio.
- Icons follow the text size (`dash_ui`: `applyTextScaling` in the icon themes).
- Tap targets are fixed by merging and reusing the height for information, not by
  padding every row to 48 dp. Before a bigger visual change, show three variants
  rendered for real at 100, 150 and 200 %.
- HMS panel: wiki link is a 48 dp icon in the tile's corner, the code sits under the
  text inside the same touch target, a description is a button only when cut to two
  lines, the buttons share the tile width. AMS and external-spool rows: one column of
  48 dp rows whose extra height carries a level bar, the percent and the remaining
  grams (the weight stays). AMS temperature shows `°C`.
- No text is shortened to one letter and an ellipsis anywhere: wrap it or give it its
  own line.
- A dimmed label is a disabled node for a screen reader too (`Semantics(enabled:
  false)`), not a test exemption.

## State (end of 2026-10-28)

Failing tests in `test/a11y`: 1843 of 6765, from 2478 at the start. Overflow findings
are gone everywhere except the single-printer controller (19 tests) and the
`material_ui` `SnackBar` (2 tests, not our code). Contrast findings in the output: 0;
the report still lists two genuine ones (`65°` in `#c8ccc6` on `#f1f3ef`, 1.46:1) that
are not located yet.

## Open, in this order

1. **Tap targets of the pickers**, about 720 findings: `location_form.icon`,
   `maintenance_type_form.icon`, `spool_form.color_swatch`, `project_form.color`.
   Probably one shared 48 dp tile with a 36 dp drawing (as `ams_slot_colour.swatch`):
   check first whether the four share code. Then the controller screen's dozens of
   17-46 dp targets.
2. **Controller layout at large text** (19 tests; bottom overflows of 15-39 dp in
   `controller_overview.dart` and `controller_print.dart`). The screen is designed to
   fill without scrolling in landscape. Decision pending: scroll above 130 % text
   (recommended), scale the captions down, or leave it.
3. The two `65°` contrast findings.
4. About twelve test-side failures at large text, where the test's `arrange` does not
   reach the control (controller keypad, "Test cube" in the print log, the "X1 Carbon"
   tile in the dashboard fold test, the wall tile tap, the pipelines fan-out select).
   Fix with `ensureVisible`, not in the app.
5. No widget test yet for the swatches section header, the queue-edit schedule row,
   the archive colour-filter row and the timelapse info row (the a11y suite covers
   them). The wall tile caption has a test, but its render is black (camera).
6. Unification: two `SectionCard` classes (`stats_common.dart`,
   `project_detail_sections.dart`) and two `_StatTile`s that differ in look; needs a
   decision before merging.
7. Waiting for the maintainer: new screen-reader copy in five languages, the
   date-range picker cells, how many accents after a `timeit`, `°C` on the
   temperature tiles if wanted.

## How to prove a change

- **Mutation-check every test**: revert the fix and the test must fail. Verify the
  mutation really applied (a string replace that stops matching after `dart format` is
  a silent no-op).
- **Mock-ups are real renders.** A hand-written sketch with guessed sizes is not
  accepted. Render the real widget in a throwaway widget test in the app theme (app
  fonts load from `test/flutter_test_config.dart`; load `MaterialIcons` and `Roboto`
  with `FontLoader` in `setUpAll`; never read a file inside the test body, fake time
  makes it hang), capture with `captureImage`, crop and compare before and after pixel
  by pixel (a clock in the fixture shows up as a difference). "Before" is
  `git stash push -- <files>`, or `git checkout <sha>^ -- <files>` for committed code;
  restore afterwards and check `git stash list`. Show 100 % next to 150 and 200 %, and
  show the stacked layout, not only that nothing overflows.
- Say so when a visible layout changes at 100 %.

## Working rules

- No commit and no push without the maintainer's word; a commit message is one
  Conventional Commits line.
- Do not raise tags, pins, CI or push order unprompted: the shared packages come from
  the sibling checkout until the work is done.
- Before proposing a custom solution where Google or Flutter recommends one, read what
  they recommend (context7 or the official docs) and cite it.
