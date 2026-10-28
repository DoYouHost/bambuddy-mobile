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

1. Keep a clone of `git@github.com:DoYouHost/app-shared.git` next to this repository,
   on `master` and pulled (it has to contain `afc1783`). **Look at `ls ..` first:** the
   maintainer's machines already have it as `../app-shared`; a second clone under
   another name is a duplicate. Run the commands through the sibling `../flake.nix`
   shell (`direnv exec .. <cmd>`), where `flutter` and `just` live.
2. Create the git-ignored `pubspec_overrides.yaml` in this repository, pointing at
   that clone:

   ```yaml
   dependency_overrides:
     dash_kit:
       path: ../app-shared/packages/dash_kit
     dash_ui:
       path: ../app-shared/packages/dash_ui
     app_report_ui:
       path: ../app-shared/packages/app_report_ui
   ```
3. `flutter pub get` rewrites the tracked `pubspec.lock` for that machine. It shows as
   modified on purpose: **never commit it, never stash it.**
4. `just hooks` once per clone, then `flutter analyze` and
   `flutter test test/a11y/a11y_contrast_judge_test.dart` must pass before any work.

## Running it

- The whole suite: `just test-a11y` (one `flutter test --concurrency=4` under a
  12 GB scope). On the maintainer's laptop: 726-732 s against 1409 s one file at a
  time, about 6 GiB; on the desktop 598 s. Another machine will time differently.
- Several `flutter test` processes at once corrupt the shared `build/test_cache`; the
  parallelism is inside the one run. Kill by PID, never `pkill -f`.
- The rest of the tests: `flutter test --concurrency=4 test/features test/l10n
  test/core` (4973 tests, 194 s on the same laptop).
- Contrast report (analysis only, writes nothing unless asked):
  `just test-a11y "--dart-define=A11Y_CONTRAST_REPORT=/tmp/x.jsonl test/a11y"`
  appends one JSON line per judged finding: verdict, text, foreground, grounds,
  contrast by the text's own colours, needed ratio, token and widget chain.
  A run of the whole suite lists **two `genuine` findings, both `65°` in `#c8ccc6` on
  `#f1f3ef`: that is the deliberate fixture of `a11y_contrast_phase_test.dart` ("a
  real shortfall fails at every phase"), once per paint offset, not a widget of the
  app.** A `genuine` row with a chain that ends in `Align ← Padding ← Scaffold body`
  and no `token` is that fixture; any other one is real.

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
- Icon and colour pickers (`location_form.icon` / `.color`, `maintenance_type_form.icon`,
  `spool_form.color_swatch`, `project_form.color`) are one `PickerTile`
  (`dash_kit`, `packages/dash_kit/lib/src/picker_tile.dart` in `app-shared`: a generic
  widget with no app import belongs there, see unification-lessons.md): a 48 dp touch cell around a drawing that
  keeps its size (44 for icons, 36 for colours), the `Wrap` gap reduced by
  `PickerTile.gap` so the drawings stay where they were. Chosen from three real
  renders (36 in 48, unchanged drawing, 44 in 48). The glyph inside does not grow with
  the text (`applyTextScaling: false`): the cell is fixed, so a glyph that scaled to
  44 dp at 200 % filled it edge to edge. The project palette wraps to two rows on a
  window under 416 dp (8 × 48 against 379), accepted rather than pushing the grid into
  the page gutter, which would break the hit area.
- A tappable tile needs a **label**, and every picker tile had two findings, size and
  missing label, in equal numbers. A `Tooltip` counts as the label only **inside**
  `logTag` / `.tagged`; outside it the tag's own semantics node takes the tap and
  stays unlabeled. The tooltip text is the icon key or the colour code; real names
  are new copy in five languages and wait for the maintainer.
- **Where a tappable node gets its label from** (found fixing 1500 findings; a test
  that fails on size and label counts once, so check both before counting):
  an `IconButton` takes its `tooltip:`; an icon-only `FilledButton` takes only
  `Icon(semanticLabel:)` (a `Tooltip` around it, inside or outside `logTag`, is not
  merged into the button's node); a `Switch` or checkbox beside a `Text` needs
  `Semantics(label:)` with the same string; a `PickerTile` or `InkWell` takes a
  `Tooltip` **inside** `logTag`. Use strings that already exist
  (`MaterialLocalizations.clearButtonTooltip`, the visible label); a new string is the
  maintainer's call.
- Controller at large text: no scrolling and no smaller captions. The two overflows
  were fixed where the layout was rigid: the job card's percentage keeps its design
  size at any text size (`textScaler.clamp(maxScaleFactor: 1)`, it is the biggest
  figure on the screen), and the filament row in the print settings has
  `minHeight: controllerButtonHeight` instead of a fixed height, inside a list that
  already scrolls. 100 % is unchanged.

## State (2026-10-28, second machine)

Failing tests in `test/a11y`: 1368 of 6765, from 1843 at the start of the day (2478 at
the start of the work); 533 s wall clock for the whole suite on the desktop. Nothing
new fails in any of the last three runs. What went since the morning: the pickers and
the controller overflows (213), the test-side groups (54), then the labels (208: the
slicer's option switch, the search field's clear button, the controller's icon
buttons). Overflow findings are gone everywhere except the `material_ui` `SnackBar`
(2 tests, not our code) and the "common, selection controls" test row (8 tests, a
right-hand overflow of 13-77 dp inside the test's own fixture at
`common_a11y_test.dart:603`, to check before calling it a test bug). Contrast findings
in the output: 0; the two `genuine` rows of the report are the `65°` fixture (see
Running it), nothing to fix.

Left, by file: controller 402, queue 176, files 168, dashboard 155, archive 116,
inventory 109, locations 48, tour 35, common 33, admin 31, dashboard sheets 24,
projects 24 (tap targets and missing labels, in pairs wherever a control is both).

## Open, in this order

1. **Tap targets and labels of the controller screen**: dozens of 17-46 dp targets,
   and tappable nodes with no label (32 in the three print-screen surfaces alone). The
   pickers are done (`PickerTile`, see Decisions); the other screens have the same two
   findings per control, so check both before counting.
2. Nine test-side failures left, none solved by `ensureVisible`: the "X1 Carbon" tile in
   the dashboard fold test at 150 % and 200 % (2), the new spool form's material menu at
   150 % and 200 % (2, a framework assertion `transformed == position -
   childParentData.offset` in a hit test, cause not found), the wall's `wall.live_camera`
   at 150 % and 200 % (4: the panel is not scrollable and the switch sits at y = 476 in
   a 411 dp window, which looks like an **app defect**, not a test one), and the
   "Timelapse" chip of the printer files at 200 % (1, `ensureVisible` does not bring it
   into the horizontal list). The harness now pages a lazy list for `shows` and
   `a11yTap` (`_pageUntilBuilt`) and unmounts at the end of a surface (a poll can start
   a demo request in the last frame).
3. No widget test yet for the swatches section header, the queue-edit schedule row,
   the archive colour-filter row and the timelapse info row (the a11y suite covers
   them), nor for the maintenance type sheet and the project form (only the a11y suite
   builds them). The wall tile caption has a test, but its render is black (camera).
4. Unification: two `SectionCard` classes (`stats_common.dart`,
   `project_detail_sections.dart`) and two `_StatTile`s that differ in look; needs a
   decision before merging.
5. Waiting for the maintainer: new screen-reader copy in five languages (the picker
   tiles say the icon key or the colour code today), the date-range picker cells, how
   many accents after a `timeit`, `°C` on the temperature tiles if wanted.
6. **`PickerTile` and its test sit uncommitted in the `app-shared` working tree**
   (`packages/dash_kit/lib/src/picker_tile.dart`, `test/picker_tile_test.dart`, one
   export line in `dash_kit.dart`). This branch builds against the sibling checkout
   only; it needs that commit, a shared release and a `pubspec.yaml` ref bump before
   CI can go green.

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
