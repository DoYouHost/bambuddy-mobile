# Unification lessons

What the successive de-duplication passes over the UI and core code left behind:
where each shared helper lives, the traps that cost debugging time, and the merges
that were measured and **rejected**, so nobody proposes them a second time.
**Read it before extracting a helper from code that merely looks repeated.**
Per-helper reasoning lives in [ui-primitives.md](ui-primitives.md),
[test-harness.md](test-harness.md) and [conventions.md](conventions.md); this file
is the map and the decisions.

## Rules that survived

1. **Count the call sites and read what each one does before extracting.** Twice
   the right answer was a test, not a helper.
2. **Check whether the theme already does it.** `buildDashThemeData` (`dash_ui`)
   sets `TextButton`'s foreground to the accent ink, so a call site repeating
   `TextButton.styleFrom(foregroundColor: …)` is deleted, not wrapped. A button that
   is a *state* rather than an action (`onPressed: null` for good) gets its colour
   from `disabledForegroundColor`.
3. **A unification keeps each call site's behaviour.** It must not spread a rule
   that made sense in one place over all of them; a flag per difference is the sign
   the merge is wrong.
4. **Before changing a size, grep the number, not the widget.** `_HeaderLine` in
   [printer_card.dart](../lib/features/dashboard/widgets/printer_card.dart)
   subtracts the leading glyph square's width from the line, so it once took 2 px
   from the printer name's guaranteed width when the tile grew from 34 to 36 and
   nothing failed. The number is now the named constant `glyphSquare`.
5. **A test that scans sources matches content, not line layout.** `dart format`
   moved a `?.add(` to a new line and broke the first version.
6. **Log the event, not the intent**, or the log fills with flows that did nothing
   ([logging-guide.md](logging-guide.md)).

## Where the shared code lives

| What | Where |
| --- | --- |
| `DashIconTile`, `DashProgressBar`, `ThumbnailPlaceholder`, `SheetSurface`, `InlineNote`, `TappableCard`, `DashStepper`, `dashCombo` / `dashPickerField` (`dash_input.dart`), `screenListPadding` (padding of every screen list), `ButtonPair`, `confirmDialog` | `dash_kit` package |
| `DashPill`, `DashSpace`, the `cardBox` decoration, `buildDashThemeData` | `dash_ui` package |
| `textWidth` (`text_measure.dart`), `classifyDioException` (`dio_failure.dart`), `ServerReachability` | `app_util` package |
| `testWithClock`, `identifiersIn`, `byLogId`, `settle`, `usePhoneWindow`, `ScriptedAdapter`, `RequestLog` | `app_test_kit` package, re-exported by [test/helpers.dart](../test/helpers.dart) |
| `dashAsync`, `dashAsyncStrip`, `BusyLine` | [dash_async.dart](../lib/features/common/dash_async.dart) |
| `plate_clear`, `openWebLink`, `showApiFailure`, `MediaImage` | `lib/features/common/` (`plate_clear.dart`, `web_link.dart`, `api_failure_snack.dart`, `media_image.dart`) |
| `ObservedCapability`, `ActionOutcome`, `mapDioException`, `MediaAuthService` | `lib/core/api/` (`observed_capability.dart`, `action_outcome.dart`, `api_exceptions.dart`, `media_auth.dart`) |
| `dateTimeFromJson`: server times are converted with `toLocal()` once, here, and nowhere else | [json_utils.dart](../lib/core/models/json_utils.dart) |
| `detachFrom`, the handles of a flow that outlives its widget | [app_context.dart](../lib/core/app_context.dart), see [riverpod-traps.md](riverpod-traps.md) §6 |
| `TimerFactory`, the injectable timer | [offline_debounce.dart](../lib/core/printers/offline_debounce.dart) |

## Traps that cost real debugging

- **`DropdownMenu` keeps its selection when the entry list changes.** In the Flutter
  version used, `didUpdateWidget` adopts a new `initialSelection` only if the value
  is among the entries. When the options' *range* changes (another printer, so other
  AMS slots), give the `dashCombo` a `ValueKey`, or the field shows empty while the
  state still holds the old value. The arrow's 8 px of extra height is in
  [ui-primitives.md](ui-primitives.md).
- **`ResizeImage` with both width and height decodes exactly to the box** and
  stretches a source of another aspect ratio. Cap `cacheWidth` only, so
  `BoxFit.cover` can crop (`_decodeWidth` in
  [media_image.dart](../lib/features/common/media_image.dart)).
- **A `DioException` fake needs `type: DioExceptionType.badResponse`.** Without it
  `classifyDioException` never reaches the status switch, so a 403 fake does not
  come out as the forbidden case and the test passes for nothing.
- **Order inside `MediaAuthService.invalidate()` matters**: the verdict "this route
  is absent" is read before `_media.invalidate()`, which clears it (commented at
  the call).
- **A shared control takes its diagnostic id from the call site**, never builds it
  by interpolation (`'$id.clear'`): the coverage scan does not see interpolated tags
  ([logging-guide.md](logging-guide.md)), and one id for six instances reports them
  as one. Hence `clear` is a `({String id, VoidCallback onPressed})` record. Ids are
  wire values; renaming one orphans reports already filed.
- **`action_tag_vocabulary_test` sees only literal `id: '…'`, `logTag('…')` and
  `.tagged('…')`**, so a shared widget takes the id as a parameter.
  `spacing_scale_test` rejects even a bar's `SizedBox(width: 4)`: name the constant.
- **A regex replace across many files**: diff the log ids and `onTap` handlers
  before and after (`git diff | grep`), and cut a class by its exact text; matching to
  "the end of the block" once swallowed half of the next class.
- **A comment sweep for Polish needs two filters**: diacritics *and* common Polish
  stopwords. A sentence written without the diacritics passes the first.

## Deliberately not unified

Each of these was measured; the merge either changes pixels or behaviour, or costs
more than the lines it saves.

- **A shared card tile.** `subCardBorder` stands in about 90 places in about 50
  files; one widget would be a design-system change, not de-duplication. The
  decoration alone is shared (`cardBox`), without layout.
- **`_StateChip` (printer card header) vs `DashPill`.** Radius 14 vs 20, offline
  gets a solid 1.5 px border where `DashPill` has a 0.4-alpha one, upper-case, and an
  ellipsis that carries the header's layout. Four parameters for two users, and
  `DashPill` lives in `dash_ui`, so it would also be a package release. Likewise
  `ProjectStatusChip` and the queue's `_Chip`: a flag for two users, and
  `DashPill(dense: true)` has other padding, alpha and font, so moving a status
  pill over changes pixels.
- **The online and offline printer-card headers** are two layouts of the same
  extracted widgets, not two copies of logic.
- **The three printer pickers** are three different UIs.
- **`NotificationService` decorators** (`RememberingNotifications`,
  `LoggingNotifications`, `FgsNotificationService`, …) all `implements` the
  interface and share no base. That is the point: a new method becomes a compile
  error in every decorator. A forwarding base class would let a new alert through
  unlogged and unremembered. **The duplication is a safety property.**
- **Two model-name readers.** `isBedSlinger` strips and upper-cases (it matches
  a table), `ownedPrinterCodesProvider` upper-cases to narrow presets, while
  `printerModelsProvider` keeps the server's spelling because the server compares
  that string by plain equality. Each mirrors a different server or web function;
  pointing one at another changes behaviour (see the comment on
  `printerModelsProvider` in
  [inventory_providers.dart](../lib/features/inventory/inventory_providers.dart)).
- **`Archive.isSliced`** mirrors the web's `isSlicedFile` (a `.gcode` / `.gcode.*`
  name, or slice metadata), so it is not folded into `isSlicedFilename`.
- **`plateLabel` vs `batchPlateLabel`** word things differently on purpose, and
  `assignmentSlotLabel` names an external spool by extruder (left / right), as the
  dashboard does, not by slot.
- **One "Save" string in l10n.** Every feature keeps its own key (`fmSave`, …) so
  translators get the context.
- **A shared "N of M" runner.** Manyfold import, `_perSpoolFallback` in
  [inventory_providers.dart](../lib/features/inventory/inventory_providers.dart) and
  the announcements' "mark all" each report and stop differently (progress and
  names, a bare count, stop at the first error); a flag per difference.
- **`_goneWithin` (projects contract test) vs `pollUntil`** (`contract_harness.dart`):
  there a timeout is the answer ("it never went away"), not an error.

## What was dropped as history

Per-round task lists, audit sweeps whose result was "clean" (timers vs `dispose`,
`==` without `hashCode`, `firstWhere` without `orElse`, deep-link `int.parse`,
division by a possible zero) and plan-vs-branch bookkeeping. Re-run an audit when
the code it covered changes; none of them is a standing rule.
