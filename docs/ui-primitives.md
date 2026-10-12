# The shared UI primitives and why they behave as they do

`lib/features/common/dash_input.dart` and `dash_async.dart`. The code keeps the
contract; the reasons behind the non-obvious rules are here.

## Fields and selects (`dash_input.dart`)

- **One chrome.** `dashDecoration` is a rounded `subCard` fill with a hairline
  border, turning the accent on focus. A field built with Material's own
  defaults reads as a different app the moment it sits next to one of these,
  which is exactly what happens in a bottom sheet. A field's `helperText` may take
  three lines (Flutter's default is one, ellipsized, which cut a two-sentence hint
  off mid-word).
- **`dashInputTheme` is the same chrome as an `InputDecorationTheme`**, for
  `DropdownMenu`, which builds its own text field and takes no `InputDecoration`.
  It is read off `dashFieldDecoration` rather than restated, because that is how
  the two drifted apart. `suffixIconConstraints` is deliberately absent: it boxes
  a select's arrow (`dashCombo` applies it), while a text field's own suffix icon
  is a real button whose tap target nothing here should shrink.
- **Every select goes through `dashCombo`**, never `DropdownButtonFormField`,
  whose full-screen overlay is the old Material look. Rows carry their own
  diagnostic ids: the menu opens in a route of its own, so the field's id never
  reaches them ([logging-guide.md](logging-guide.md)). `filterable` turns it into
  a combo the user may type into, which is also what makes it take focus; a plain
  select must not, or the keyboard covers the list it just opened.
- **The arrow is boxed at 40 × 40 (`_arrowBox`).** Flutter builds it as a bare
  `IconButton` with a 48 × 48 tap target, which pushes the field to 56 while every
  text field in the app is a dense 48: in a form holding both, the select stood
  8 px taller. `suffixIconConstraints` is routed straight to that button
  (`dropdown_menu.dart`). 40 is a *ceiling*, not a preference: the button sits in
  a `Padding(all: 4)` the caller cannot reach, so 40 + 8 is the most a 48-tall
  field has room for. That is under the 48 dp target an accessibility audit looks
  for, and it costs nothing because the arrow is a duplicate affordance: the
  field's own `onTap` opens the menu whenever the select is enabled (the inner
  `TextField`), filterable or not, so the real target is the whole field.
- **`dashAnyOrOne`** is a `dashCombo` whose first row means "no filter". **Null is
  the any-row**, which is why `T` is bound to a non-null type: the picker's value
  type is `T?`, so a filter's two states need no sentinel (`-1`, `''`) between
  them. A `DropdownMenu` does hold a null row and names it at
  `initialSelection: null`. Labels are names people gave things, so they stay out
  of the diagnostic id: the any-row records as `<id>.any` and **every** value row
  as `<id>.option`.
- **`dashPickerField`** opens a picker instead of taking typed input. `value` null
  or empty means nothing is picked and `placeholder` shows in tertiary ink: that is
  the whole of how the two are told apart. A value that *is* the word "none" is
  still a value; pass it as `value`, not as the placeholder, or a deliberate "use
  nothing here" reads as an empty field. `clear` is one record rather than two
  parameters so a call site cannot give the callback and forget the id: both ids
  come from the call site, because a shared control that tags itself reports every
  use under the first one's name.

## Async state (`dash_async.dart`)

- **`AsyncFlag.orFalse`: unresolved is off.** A name rather than a spelling,
  because `!= false` says the opposite and looks just as reasonable at the call
  site. Every one of these gates a control, so loading, an error and a refusal
  must all read the same way, or a control flashes into a screen and out again, or
  leads to a route the server does not have. A gate that would rather show its
  control while the answer loads belongs on the other side of the question, in
  `ObservedCapability.whenUnknown`.
- **`offer` / `pending`**: on screen but not pressable, because nothing has
  answered yet. A button the user is waiting to press reads better greyed out for
  a moment than absent and then suddenly there. Only for a widget that **watches**
  the answer (one that cannot rebuild would sit greyed for as long as it is on
  screen), and only while there is nothing to say: a control left disabled for good
  owes the user a line saying why, next to it.
- **`dashAsync`** writes the two branches every screen words identically (the
  spinner and "could not load it, try again") and leaves the data branch to the
  caller. A screen that needs different words for a failure (the photo view, which
  explains that *this print* has no picture) still writes its own `when`. Both skip
  flags are on by default: a list already on screen should not blink back to a
  spinner because it is being refreshed underneath.
- **`dashAsyncStrip`** is the same for a section inside a screen. One `padding`
  for both states on purpose, since a section that pads its spinner differently
  from its failure line makes the page jump as the answer arrives. `height` gives
  the waiting and failed states the height the content will have, so a chart's slot
  does not collapse and spring back (the history sheets). `failureBuilder` is for a
  section that already has its own way of saying "nothing here".

## Optimistic removal (`restoredPositionOf`, `withRowRestored`)

When a row is removed before the server has answered and the request fails, it has
to go back **into the list as it is now**, never into the snapshot it was removed
from. Restoring the snapshot is the bug these exist to stop: swipe A, swipe B, A's
request fails, and the rollback puts B back on screen, undoing whatever a refresh
landed in between. Only the row that failed goes back.

Its place is read off the rows that were around it, **never off the index it used
to sit at**. An index is wrong as soon as a second removal is in flight: delete A
then B from `[A, B, C]` and both remember index 0 (B was at 0 once A had gone), and
when both fail, both are put back at 0 and the list comes back as `[B, A, C]`, two
rows swapped although neither was deleted. Neighbours survive that: the row goes
after the last row that was above it. `before` is the list as it stood when the row
was still in it. With nothing above it left, the row goes in front of the first row
that was below it, so a row the server added meanwhile keeps its place.
`withRowRestored` returns `now` itself when something has already restored the row,
so a caller can assign the result unconditionally and a no-op stays a no-op. The
queue does its own insertion (`QueueNotifier` pins printing rows on top) but reads
its position from the same function.

## Refetching when the server returns (`_WhenServerReturns`)

It rebuilds on `ServerReachability` and asks its screen to fetch again the moment
the server comes back. Without that, only the dashboard recovered by itself (it is
the one screen that polls); every other tab kept the failure it had collected in
flight mode until the user pulled it down by hand, though the app knew the
connection was back. **Only a connection failure is retried**: a 500 or a refusal
is the server's answer, and asking again the moment the radio comes back would be
a request per screen for a state nothing has changed about. `_waitingOnTheServer`
is false while a request is still in the air: it may well be the one that brings
the server back, and a second alongside it means two requests and a race over which
answer the provider keeps. Whatever it ends as reaches `didUpdateWidget`, which is
where a late failure is picked up.
