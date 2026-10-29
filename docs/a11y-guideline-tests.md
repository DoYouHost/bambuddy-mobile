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
   on `master` and pulled (it has to contain `5b8a74a`, the `pickDate` entry mode). **Look at `ls ..` first:** the
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
- `a11yMeetsAllWhileScrolling` pages a scrolling screen one viewport **less 72 dp** at a
  time, and `A11yTapTargets` skips a node that is flush with its viewport's paint clip
  on the axis the list scrolls (`SemanticsNode.rect` is already clipped, so a control
  half scrolled out reads as a small one). The overlap is what keeps the skip from
  hiding it: the control stands whole at the next stop and is measured there. Flutter's
  own guideline skips only nodes at the edge of a scrollable that marks itself
  implicit, and any node flush with its left side; it also lets a full-width row under
  48 dp through, which this harness does not close. Tests: `a11y_tap_targets_test.dart`.
- `a11yTap` and `a11yLongPress` scroll the control to the **middle** of its scrollable and
  pump a frame before tapping. `ensureVisible` moves the scroll position but not the
  render tree, so the finder still answered with the old place and the tap landed
  where the control had been, under the fold; and its default puts the control at the
  leading edge, under a pinned header. Find a row of a lazy list by its text, not as
  `.at(n)`: the nth built match is another row once the list has scrolled.
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
- **Date picker in landscape**: Flutter's calendar rows are 48 dp in portrait only; in
  landscape they are 42 dp cut to the window's height over seven rows (about 35 dp, at
  every text size; the source says "landscape mode is not specified"). The print screen
  asks for a time through `pickDateTime(initialEntryMode: input)` when the window is
  landscape: a field, no target under 48 dp. **The toggle to the calendar stays**, and
  no test opens that view, by decision: the calendar is a Flutter widget that is
  smaller than 48 dp in landscape and is reachable on purpose. Do not add a test that
  toggles it unless the calendar is replaced.
- Controller at large text: **a screen is rearranged, never scaled with the font**
  (`ScaleToFit(reflows: true)`, from 1.3x text), no caption gets smaller, and a touch
  target stays 48 dp or more. What cannot fit the window then scrolls as a page (Overview,
  Heat, Filament, the print-settings screen, the Prints items' dialog), with the actions
  pinned where there are any; nothing scrolls inside a card that sits in such a page, as it
  would take the drag from the page. Details and the numbers:
  `docs/single-printer-controller.md` §2 and §9.

## State (2026-10-28, end of the day)

**597 of 6779 tests in `test/a11y` fail**, from 2478 at the start of the work (1843 at the
start of that day, 1018 at the last full run before the harness changes, 629 after
them). A whole run is about 10 minutes (`just test-a11y`, four files at a time).

Left, by file. One surface is 8 tests (three accents in both themes at 100 %, then 150
and 200 %). Tap targets and missing labels come in pairs wherever a control is both, so
check both before counting.

| File | Fails | Surfaces |
|---|---|---|
| queue | 0 (was 126, fixed 2026-10-29) | the submit pill was 40 dp; the controller's mapping dialog is now measured in the landscape window |
| inventory | 18 (was 109) | the two colour dialogs: the wheel has no name (new copy, see below); the new spool form's material menu (framework assertion) |
| files | 0 (was 88) | the quick-nav chips lost their 48 dp area to the bar's padding; the file photo tiles take the section title as their tooltip |
| archive | 0 (was 60) | the colour swatches got a 48 dp cell and the colour code as their name; the timelapse trim strip, surface and seek bar are named from strings the app already has |
| locations | 0 (was 48) | the location header was 44 dp tall |
| common | 25 (was 33) | the colour wheel (8, no name), the QR scanner's torch button (16, no name and no existing string), the snack bar with the long "Pokaż w menedżerze plików" action at 200 % (1: the shared `dash_kit` snack lays the action label out without wrapping) |
| controller | 0 (was 33 of 520) | see the controller section below |
| projects | 0 (was 24) | the bill-of-materials checkbox takes the item name; the project link is 48 dp |
| dashboard sheets | 8 (was 22) | the slot colour dialog's wheel; the movement sheet buttons are 48 dp |
| admin | 0 (was 19) | the advanced permissions row is 48 dp; the API key is read as one label |
| swatches | 0 (was 16) | the delete button takes the Material delete tooltip |
| print log, stats | 16 | the date-range picker: its day cells are 56 × 42 dp (Flutter's calendar) |
| dashboard, model sources | 1 (was 3) | MakerWorld "plate imported" at 200 %: the same long snack action as in common |

**The 68 left (2026-10-29) all wait for a decision**: the colour wheel (32, new copy and a wrapper around a library widget), the QR torch button (16, new copy), the date-range calendar (16), the material menu (2) and the long snack action (2, a shared package).
What the day fixed, in short, so it is not redone: the pickers (`PickerTile`), 558
missing labels, the controller's rail and its reflow from 1.3x text, the print-settings
screen and every dialog it opens, the Prints items' dialog, the date picker in
landscape, and four harness faults (a cut control read as a small one; paging without
overlap; `a11yTap` tapping the old place; tests arranged only for the normal text size).
Contrast findings in the output: 0; the two `genuine` rows of the report are the `65°`
fixture (see Running it), nothing to fix.

## Controller, 2026-10-29

All 520 controller surfaces pass, and 45 more on a window 360 dp tall at 120, 150 and
200 % (`short window` in `controller_a11y_test.dart`; without the height trigger in
`ScaleToFit` 27 of them fail). The last 33 failures had three causes, none of them a
`ScaleToFit` shrink on the Redmi's window (its height factor is 1.1 there): the search
chip was 40 dp (now 48); the fault chip lived only in the rail's open panel (it is on
the Overview picture now); the four-heater Heat tab at 200 % was squeezed by a fixed
440 dp box (42.5 dp buttons). The last is why every tab that could be squeezed is now a
`ControllerPage` (see `single-printer-controller.md` §2). **Known limit, unchanged:** a
window narrower than about 890 dp shrinks the body by its width (800 dp of window: 0.89,
a 48 dp button is 42.7 dp). A surface on such a window fails the tap-target guideline; the
short-window surfaces use 891 dp for that reason. Reflowing for width is not done.

## Open, in this order

1. **The controller is done** (above). Design and rules: `docs/single-printer-controller.md` §2 and §9.
2. **The other screens, 68 tests, all waiting for a decision** (the table above): the
   colour wheel in four dialogs (32; the library's gesture node has no name and offers no
   hook, so it needs new copy in five languages and a wrapper), the QR scanner's torch
   button (16; there is no torch string in the app), the date-range calendar of print log
   and statistics (16; the day cell is 56 x 42 dp in Flutter's own picker), the spool
   form's material menu (2; a framework assertion `transformed == position -
   childParentData.offset` in a hit test, cause not found) and the snack bar whose action
   "Pokaż w menedżerze plików" overflows by 47 dp at 200 % text (2; the `snack` helper is
   in `dash_kit`, so the fix is a shared release or a shorter label).
3. No widget test yet for the swatches section header, the queue-edit schedule row,
   the archive colour-filter row and the timelapse info row (the a11y suite covers
   them), nor for the maintenance type sheet and the project form (only the a11y suite
   builds them). The wall tile caption has a test, but its render is black (camera).
4. Unification: two `SectionCard` classes (`stats_common.dart`,
   `project_detail_sections.dart`) and two `_StatTile`s that differ in look; needs a
   decision before merging.
5. Waiting for the maintainer: new screen-reader copy in five languages (the picker
   tiles say the icon key or the colour code today; the X/Y jog arrows say "Move X plus"
   and the like; the plate and chamber steppers say `Plate −1` and `−5°` from existing
   words and signs; the spool colour wheel and the QR torch button have no name), how
   many accents after a `timeit`, `°C` on the temperature tiles if wanted.
6. **The shared packages.** `app-shared` has `PickerTile`, the search field's clear
   tooltip and `pickDate(initialEntryMode)` on `master` (`5b8a74a`, pushed directly past
   the pull-request rule). This branch builds against the sibling checkout
   (`pubspec_overrides.yaml`) only: `pubspec.yaml` still pins `dash_kit` and `dash_ui` at
   `v0.14.4`, which has none of that. CI goes green after a shared release and a ref bump
   (`docs/shared-packages.md`). Not raised unprompted.

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
