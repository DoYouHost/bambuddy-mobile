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
| **Scaled curve** | the full face, each item scaled to the chord lit where it sits | lists of short rows |

### Why the rectangle is not the answer for both

The rectangle is the easy thing to be sure of, and that is its whole appeal. It
costs 36% of the height of a display that had none to spare, and it hands every
row the width available at the *worst* point of the viewport — including the
rows crossing the middle, where the whole diameter is lit. Measured on a 225 dp
face it leaves **144 dp of viewport, 1.8 rows of a printer list**.

`WearScrollView` is where the choice is made: a screen with a footer, or one
holding still with `centerWhenShort`, is a fixed layout and keeps the rectangle;
`curved: true` is the list.

### The insets go on the viewport, not on the content

This is the whole fix, and the part that is easy to get wrong. Padding the
*content* only settles where the first and last item come to rest — everything
between them still travels through the top and bottom of the circle as the
screen scrolls. That is how a paragraph ended up sliced mid-word and a Pause
button lost both its ends. A viewport that **is** the inscribed rectangle cannot
paint outside it at any scroll offset. `WearScrollView` owns that.

### Why a scale and not a narrower inset

An inset re-lays-out the item, so a printer name would re-wrap and ellipsize
differently on every frame of a scroll. A scale is a paint-time transform and
the text keeps its metrics all the way out. Wear OS's own transforming list
shrinks items toward the edges for the same reason — they are hard to read
there anyway.

Only for short rows. An item taller than the face's *radius* has a corner past
the chord wherever it stands, so a paragraph or a fault card keeps the
rectangle, where the viewport clips it safely.

## The tunables

Everything else follows from the circle. These four are the decisions.

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

### `wearNarrowWidthFraction = 0.62`

`roundEdgeFraction` read from the other end: content that does not need the full
chord can reach further up and down before the circle catches it. The
confirmation dialog is the case — icon, question and button row are taller than
the rectangle a full-width screen gets, and a confirm nobody can reach without
scrolling is worse than one that gives up some width.

### `roundCurveEndFraction = 0.10`

The curved list's counterpart to `roundEdgeFraction`: **not** a margin content
may never enter, but where the first and last item come to rest. The band above
and below is scrolled *through* rather than left black, which is the difference
the curve buys.

## The curve

### Anchoring: the inner edge, not the centre

`roundCurveAnchor` holds an item by whichever part of it is nearest the middle
of the face, so the item compresses *towards* the middle rather than retreating
past the rim.

Holding it by its own centre is the obvious choice and the one this shipped
with. As that centre passes the edge the whole item walks off the glass: the
demo fleet's third printer was scaled to nothing with 15 dp of its row still
over the display, so a list of four showed two and a black gap.

### The scale is solved, not approximated

Shrinking an item pulls its far corner in as well as narrowing it, so the scale
that fits is not a ratio of chords. With the anchor at distance `d` from the
middle, an item of width `w` reaching `reach` from its anchor, a corner radius
`r` and an effective radius `R`, the scale `s` has to satisfy

```
(s·(w/2 − r))² + (d + s·(reach − r))² ≤ (R − s·r)²
```

— a quadratic in `s`, and the larger root is the biggest scale that still fits
(`c` is negative wherever the anchor is on the glass, so the discriminant is
positive). An item lying across the middle anchors at zero and simply takes the
largest scale the chord allows.

The scale reaches zero only once the **anchor itself** — the nearest part of the
item — has left the face, which is the point where there is genuinely nothing
left to show.

### `cornerRadius`

How round the caller's items actually are. A rounded item has nothing at the
corner of its box, so requiring that corner to fit shrinks it to protect a pixel
it never paints: measured against the square box, a row 20 dp round was being
held at 0.85. What has to fit is the corner *arc* — its centre, `cornerRadius`
in from both edges, plus that radius.

It defaults to nothing because the watch's items are not uniform — a progress
bar is 6 dp round, an input 4, a button a stadium — so only a screen whose rows
are all one shape may claim it. Corners that would eat the whole item leave the
quadratic without a usable root, and the code falls back to the plain box, which
only ever asks for less.

## Checking a change

`test/wear/wear_geometry_test.dart` holds the geometry to itself: that a
returned scale actually fits, that nothing with glass under it is scaled away,
that degenerate sizes stay finite. `rowFitsRoundFace` is the same check the
insets are built to pass, exposed so a test can hold them to it.

A widget test only catches this on a large face — `pumpWear` defaults to
384x384, and `wearFaceLarge` (450x450) is the roomier one to check against.
`expectOnGlass` (`test/helpers.dart`) is the assertion for anything a screen
positions itself rather than handing to `WearScrollView`: a plain widget test is
otherwise happy with a layout that fits the square and lights none of the circle.
