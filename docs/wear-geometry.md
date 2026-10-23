# Laying out on a round watch face

[lib/wear/wear_geometry.dart](../lib/wear/wear_geometry.dart) is the only place
in the watch app that knows the display is a circle. This file is the derivation
behind it: why the numbers are what they are, and which of them were paid for in
a rejected Play release rather than chosen.

## The problem `SafeArea` does not solve

A round display is **not reported as a view inset**. `SafeArea` on Wear OS
resolves to zero, so Flutter lays out against the square the display reports and
a full-width row near the top or bottom has its corners off the glass. Every
screen here used to inset itself by a hand-picked 8–18 px; that is what Google
Play rejected, with the first list row and the setup screen's Save button cut by
the bezel.

There are two answers, and a screen uses one or the other:

| | shape | when |
|---|---|---|
| **Inscribed rectangle** | the largest rectangle that fits in the circle | paragraphs, forms, anything taller than the face's radius |
| **Scaling list** | the full face, items shrinking and fading toward its top and bottom — Wear OS's `ScalingLazyColumn` | lists |

### Why the rectangle is not the answer for both

The rectangle is the easy thing to be sure of, and that is its whole appeal. It
costs 36% of the height of a display that had none to spare, and it hands every
row the width available at the *worst* point of the viewport — including the
rows crossing the middle, where the whole diameter is lit. Measured on a 225 dp
face it leaves **144 dp of viewport, 1.8 rows of a printer list**.

`WearScrollView` is where the choice is made: a screen holding still with
`centerWhenShort` is a fixed layout and keeps the rectangle; `curved: true` is
the list, and a confirmation is the same list laid out as Wear Material 3's
`AlertDialog` (`contentPadding`, centred when it fits).

### The insets go on the viewport, not on the content

This is the whole fix, and the part that is easy to get wrong. Padding the
*content* only settles where the first and last item come to rest — everything
between them still travels through the top and bottom of the circle as the
screen scrolls. That is how a paragraph ended up sliced mid-word and a Pause
button lost both its ends. A viewport that **is** the inscribed rectangle cannot
paint outside it at any scroll offset. `WearScrollView` owns that.

### The list is Google's, not ours

`curved: true` is a port of Wear Compose's `ScalingLazyColumn`
(compose-foundation 1.7.1), the list Google's Wear OS list guidance prescribes —
[`wear_scaling_list.dart`](../lib/wear/widgets/wear_scaling_list.dart), with
function names kept from the Kotlin so the two read side by side. It replaced a
curve of our own that scaled each row down until it fitted the chord where it
stood: rows near the rim went microscopic and still looked tappable. That curve
never painted its scale until 2026-10-15 (`getMaxScaleOnAxis` counts the z axis),
so the moment it worked was the moment it was seen to be wrong.

## The tunables

Everything else follows from the circle. These two are the decisions.

### `roundEdgeFraction = 0.18`

Height kept clear above and below the viewport, as a fraction of the display
height — the one number the inscribed rectangle is tuned by. The trade is
strict: a larger margin buys **width**, because the outermost row lands nearer
the middle where the chord is longer, and pays for it in vertical room a 225 dp
face barely has.

At **0.21 the setup screen's own button fell below the fold**, which is a worse
first screen than a slightly narrower one.

### `roundSideSlack = 0.015`

Added to the derived side inset, as a fraction of the diameter, so a row is
inside the circle rather than exactly tangent to it. Two reasons: the corners of
a rounded row cross the circle before its flat edge does, and a real bezel eats
a pixel or two more than the display metrics admit to. Solved exactly, the
arithmetic lands the corners a rounding error *outside* the circle.

## The scaling list

Everything below is `ScalingLazyColumn` with its defaults; a number here is
Google's, and changing one is a deviation from the guidance.

- **Scale and alpha** — `calculateScaleAndAlpha` with
  `ScalingLazyColumnDefaults.scalingParams()`: an item eases from full size to
  `edgeScale` 0.7 and from full opacity to `edgeAlpha` 0.5 as it crosses a
  transition line 35–55% of the viewport from the edge (further in for taller
  items: `minElementHeight` 0.2, `maxElementHeight` 0.6), along
  `CubicBezier(0.3, 0, 0.7, 1)`. Nothing is ever drawn below 70%; what does not
  fit on the glass is cut by the bezel, as on every system list.
- **Packing** — the layout pass of `ScalingLazyListState`: the item at the centre
  line keeps its place, and every other one is set against the scaled edge of
  its neighbour nearer the middle (`translationY`), so shrinking opens no gaps.
  An item above the centre line shrinks toward its bottom edge, one below toward
  its top. This needs every item's position at once, which is why it is a sliver
  (`RenderWearScalingSliverList`) and not a wrapper around each child.
- **`AutoCenteringParams()`** — space before the first and after the last item
  lets item 1 and every later one reach the centre line, and the list starts with
  item 1 there. The space depends on measured sizes, so it lands a frame after
  the first layout; until then the items are drawn transparent, as the Compose
  list does before it is initialised. The space after the last item is measured
  once that item is laid out (the cache extent builds it before the end is
  reached), as Compose leaves it at 0 until its last item is visible.
- **Gaps** — Compose spaces items with `verticalArrangement`, not with items. Our
  screens space with empty `SizedBox` children, so those are read as that
  spacing: fixed size, never scaled, never the item that gets centred.
- **Side margins** — from the list guidance and Horologist's
  `ScalingLazyColumnDefaults`: 5.2% of the screen width for every item, another
  5.2% for a text item (`listTextPadding()`; `WearScrollView` adds it to any
  `Text` child), and another 7.3% for a title, "to ensure titles don't clip"
  (`WearHeader`). Leaving the text at 5.2% is how a paragraph ran into the bezel
  mid-word.

Touch targets (Play's WO-V2) follow from auto-centering: every item can be
brought to the middle, where it is full size.

## Rules for a watch screen

- **Every scrolling watch screen goes through `WearScrollView`**
  ([lib/wear/widgets/wear_scroll_view.dart](../lib/wear/widgets/wear_scroll_view.dart)).
  It owns both things Google Play checks on Wear OS: the round-safe geometry
  (`wear_geometry.dart`, never a padding literal) and the curved scroll indicator.
  The insets go on the viewport, not on the content (see above); the viewport's own
  edge is softened by a fade as long as the content's lead-in.
- **A confirmation is Wear Material 3's `AlertDialog`** (`wear_confirm_dialog.dart`):
  a scrolling list with its buttons as the last item, every size taken from the
  compose-material3 source.
- **A watch row needs a corner radius of about 16 or more and a label that can
  ellipsize.** Wear widget tests run on a real watch face (`pumpWear`), which is
  what makes an overflow show up at all.
- **A list says `curved: true`**: Wear OS's own `ScalingLazyColumn`, ported 1:1
  (`wear_scaling_list.dart`). Its numbers are Google's; a list that looks wrong is
  fixed to match the guidance, not with a curve of our own.
- **A watch never shows a `SnackBar`.** A bar is laid out against the square the
  display reports and pinned to its bottom, where a round face has almost no width
  left, so most of the bar and of its sentence is off the glass, and
  `ScaffoldMessenger` offers no hook to move it. Transient messages go through
  `wearToast` ([lib/wear/widgets/wear_toast.dart](../lib/wear/widgets/wear_toast.dart)):
  the middle of the face, the same round-safe rectangle, three seconds, a tap to
  dismiss, hosted by `WearScreen` so a message cannot outlive the screen that
  raised it. `wear_type_scale_test.dart` scans the watch sources to keep snackbars
  out.

## Checking a change

`test/wear/wear_geometry_test.dart` holds the rectangle to itself;
`rowFitsRoundFace` is the same check the insets are built to pass, exposed so a
test can hold them to it. `wear_scroll_view_test.dart` holds the scaling list to
Google's numbers: the reference points of `calculateScaleAndAlpha`, nothing
below 70%, no gaps at any offset, item 1 and the last item centred, and paint,
hit test and semantics agreeing on the size an item shrank to.

**Do not pin text width in a watch widget test.** The test font is as wide as it is
tall (about 1 em a character), while the watch draws in the platform font
(`wearTheme` sets no `fontFamily`; Manrope is in `assets/` but the watch theme
does not use it), about 0.55 em. Measured: the unbreakable `0.14.0+2028000` in the
settings footer came out at 143.5 dp against a 141.8 dp viewport in a test and
about 80 dp on a device, so a `didExceedMaxLines` assertion failed on an artefact.
Pin the **geometry** (`expectOnGlass`), not the pixels of text. Where a length
budget is really needed, make it in **characters** with its estimate written down,
as `wearErrorMaxChars` and `wearToastMaxChars` are (`wear_theme.dart`). What stays
real is the system text scale, which is why the footer's `maxLines` is 3: a
version string such as `Server 1.2.6b1-daily.20260729` breaks only at the hyphen.

A widget test catches this on the small face — `pumpWear` defaults to
`wearFaceSmall` (384x384 px, 192 dp), where the overflow shows; `wearFaceLarge`
(450x450 px, 225 dp) is the roomier one to check against.
`expectOnGlass` (`test/helpers.dart`) is the assertion for anything a screen
positions itself rather than handing to `WearScrollView`: a plain widget test is
otherwise happy with a layout that fits the square and lights none of the circle.
