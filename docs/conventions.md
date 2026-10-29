# Conventions in depth

The short rules are in AGENTS.md ("Conventions"); this file holds the reasoning,
the numbers and the examples behind them. **Read the section before changing the
thing it governs.**

## Copy and localisation

**Copy you add gets spell-checked, and that is not the whole check.**
`just l10n-check` runs the strings this branch changed through LanguageTool
(`app_guards`' checker, configured by `tool/l10n_language.toml`: the files,
the rules this copy overrules, the words no dictionary has);
`LANGUAGETOOL_URL` points it at a self-hosted
instance instead of the rate-limited public API, and `just l10n-check-all`
sweeps every locale file (en, pl, de, fr, es). It finds spelling, agreement and punctuation. It does not
find a phrase that parses and means nothing ("Wysyłek jednocześnie"), a
calque, or a sentence stating something untrue about the hardware — those
have all shipped past a clean run, so read the copy as well.
**A label ending in a value is a noun phrase**, never an imperative or a bare
genitive: "Limit czekania na komorę: 20min", not "Czekaj na komorę najwyżej:".
**A slider also needs a sentence saying what its number changes** — a switch
reads on/off, but "4" on its own tells nobody anything.
**No line ends on a one-letter word, in any language** — the Polish "i"/"w",
the English "a", the French "à": each is glued to the next word with a
no-break space in the .arb itself. Run `just l10n-glue` after editing a
translation; `short_words_test.dart` fails until you do.

**UI copy is terse.** A banner is one line plus a one-word button, a button
label is a verb and maybe a count, and a fact appears once per screen. Before
adding copy, ask what the user would miss without it; explanations belong in a
confirmation dialog or in `docs/`.

## Comments and file shape

**`lib/core/models/` is over the comment-ratio threshold on purpose** (~29%).
What is left is the wire contract — which key the server sends, what `null` means in it, which
unit the number is in, which server file to check — and that description
exists nowhere else in this repo, while the code it sits above is a const
constructor plus a `fromJson`. Judge a model comment by "does this say
anything the declaration does not", never by a generic 20% comment-ratio
threshold. **[lib/core/api/endpoints.dart](../lib/core/api/endpoints.dart) is the
same case** and measures far higher still (~66%): it is a catalogue of route
constants whose comments are the contract around them — which server version
a path arrived in, what an API-key session is answered with, why a caller
probes instead of reading a version number. Cutting those leaves a list of
strings.

**The comment-ratio threshold is a signal, not a target** (`/comment-ratio`,
20%). Cut restatement, history (`git log`'s job) and copies of what a doc
already says; reasoning that spans a module belongs in `docs/` —
[test-harness](test-harness.md),
[notification-rules](notification-rules.md),
[notification-delivery](notification-delivery.md),
[wear-fleet-poll](wear-fleet-poll.md), [wear-relay](wear-relay.md),
[providers](providers.md), [ui-primitives](ui-primitives.md). Files
over 20% are expected: what remains is the per-declaration contract. **Repositories (`lib/data/`), `lib/providers.dart` and
`lib/core/api/` are the same case as models** — the comment says which route,
which status, what an older server does, what `null` means — and a short file
reaches 40% on one honest paragraph. Judge a comment by "does it say anything
the declaration does not", and do not delete or compress one to move a number.
When a comment grows past a paragraph, or the reasoning is about several files,
it goes to `docs/`, leaving one line and the section name. A comment that
states a *condition* ("only when…", "never…", "an older server drops it") owes
a test you have watched fail with the guard removed; one that merely restates
the code owes nothing and should go.

**No file for one to ten lines of code.** A constant, a typedef or a one-line
helper goes in the module that uses it, or — where nothing does — in
[lib/core/app_context.dart](../lib/core/app_context.dart), which holds the demo
account, the locale outside the widget tree, the server-version line and the
detached-flow handles. `comment-ratio` ranks such files first (a 1-line file
measures 83%) because a file that small is a structure problem, not a comment
problem.

**`dart format` is the style, and CI enforces it** (`dart format
--output=none --set-exit-if-changed lib test tool`). Run `dart format lib
test tool` before pushing and never hand-tune spacing to fight it. The whole
tree was formatted in one go once, so there is no longer a "bulk reformat
would bury the diff" cost to avoid — that commit is in
`.git-blame-ignore-revs`, so `git blame` skips it.
Note the one wart: the tall style splits an 80-column `if (…) stmt;` onto two
lines, which then trips `curly_braces_in_flow_control_structures`. Fix those
with `dart fix --apply --code=curly_braces_in_flow_control_structures`, not by
shortening the line.

## Layout and widgets

**Yes/no confirmations go through `confirmDialog`** (in the `dash_kit`
package, not this repo): both answers are filled buttons sharing the width,
stacked full-width when a label no longer fits; the confirm one is red when
`destructive: true`. It returns a plain `bool` (barrier and back answer
`false`), tags both buttons in the diagnostic log (`<id>.cancel` /
`<id>.confirm`) and records the answer as a `confirm` record. A hand-built `AlertDialog` is for bodies that
are a **form or a choice** (text field, colour picker, checkbox that changes the
outcome) — not for a plain question.

**Spacing goes through `DashSpace`** — and, on the watch, through
`WearSpace` for the roles Wear Material 3 names (a button's 14/6 inset, the
list gaps: in a group, between groups, title to content, between sections)
— both in the `dash_ui` package, not this repo. `DashSpace` is the 4 dp
scale `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`, plus `gutter` for the
left/right inset of anything meeting the screen, sheet or drawer edge, and
`fabClearance` for a list under a FAB. No number typed into an `EdgeInsets`,
a gap `SizedBox`, a `spacing:` or a `Divider` indent —
`spacing_scale_test.dart` refuses it. A value that is a size rather than
spacing (room for a 38 dp gauge, centring a knob) gets a named constant
next to the widget it measures. There are no per-screen exceptions: a
screen that "looks better at 10" gets 12.

**Sizes go through the scales in `dash_ui`, like spacing.** Icons are
`DashIcon` (`xs 12 · sm 16 · md 20 · lg 24 · xl 32`), corner radii `DashRadius`
(`sm 8 · md 12 · lg 16 · xl 20`), a progress bar `DashBar` (`thin 4 · thick 8`),
a tint `DashAlpha` (`wash`, `outline`, `scrim`, `cover`), a line height
`DashLeading` and an upper-case label's spacing `DashTracking`. Text sizes are
the `DashTokens` styles (`micro 11 · label 12 · body 13 · titleSm 14 · titleMd
16 …`), never a `fontSize:`. A touch target is `kMinInteractiveDimension`, and
"large text" is `dashLargeText(context)`, one threshold for every screen. All
of them sit on the 4 dp grid with no two steps under 4 dp apart, so 12, 12.5
and 13 cannot sit side by side. A layout size that is none of these (a strip
height, a panel width) is a named constant that says what it is for and is a
multiple of 4. **State of the migration:** the lines the `test/a11y-guidelines`
branch touched use the scales; the rest of `lib/` still has about 147 icon sizes,
201 radii (14, 18, 10 and 6 among them, which are off the scale), 40 font sizes
and 147 alphas typed by hand, and no test refuses them yet. Moving them is a
visible change (a card's 14 becomes 12 or 16), so it is the maintainer's call.

**A `Wrap` that sets `spacing` also sets `runSpacing`.** `spacing` is the gap
inside a run; the gap between runs defaults to zero, so the row looks right
until it wraps — at a narrow width or a larger system text size — and then the
children touch. `wrap_run_spacing_test.dart` scans `lib/` for the omission.

**Layout that depends on whether a label fits in one line must measure with the
`textStyle` and `padding` of the same `ButtonStyle` the button renders with**
(`FilledButtonTheme.of(context).style` and friends) — never with constants or
`textTheme.labelLarge`. The theme overrides buttons (horizontal padding 20,
Manrope w700) while `labelLarge` is w500, so constants underestimated the width
by ~11 px: invisible at normal text size, wrong at system text size "small"
(`font_scale 0.85`) on a 360 dp screen. Add ~10 px of slack — collapsing early
looks fine, a wrapped label does not. **Two buttons beside each other go
through `ButtonPair`**
(`ButtonPair` in the `dash_kit` package, not this repo),
which owns that measurement and stacks them full-width when they no longer
fit; a `Wrap` there gets it wrong twice over — no gap between the rows, and
each button left at its own content width. Related: `showModalBottomSheet`
without `isScrollControlled` is capped at 9/16 of the screen height.

## Tests

**A finder never spells out the app's own copy.** `find.text(pl.cancel)`, not
`find.text('Anuluj')` — `pl` is the Polish `AppLocalizations` exported by
[test/helpers.dart](../test/helpers.dart), so a copy change (a no-break space, a
reworded label) touches the `.arb` and no test. Text that is a plural or takes
a parameter is `pl.key(3)` or `pl.key('name')`; a copy fragment next to server
data is composed (`'${pl.nextAvailableLabel}X1C Warsztat'`) — the scan skips
interpolated literals.
Server data (printer names, HMS text, fixture bodies) stays literal.
`finder_strings_test.dart` refuses a literal that equals an `.arb` value,
fits one of its templates or carries a Polish diacritic; the few exceptions
sit in its `notAppCopy` set, each with its source.

**Every function that parses user input** (URLs, paths, formats) gets tests for
the basic path, missing input and odd input, written with it. A mocked
transport does not exercise network behaviour: the http/https/WS bug passed a
fully green suite because `normalizeBaseUrl` and `wsUrlFor` had no test of
their own and the mocked adapter never performs a real redirect. Extract the
input logic into a pure function and cover it directly.
