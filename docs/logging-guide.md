# Instrumenting a feature for the diagnostic log

[diagnostics-log.md](diagnostics-log.md) is the policy: what the recorder keeps,
what it refuses, and why. This file is the other half — what *you* have to do
when you add a screen, a call, a notification or a background path, so that a
bug report filed against it still explains anything.

Most of it is automatic. The work is in the five places it is not.

## What you get for free

| lane | hook | you touch it when |
|---|---|---|
| `http` | `HttpProbe`, a dio interceptor wired into `createBareDio()` | the endpoint should also contribute a **sample** (§2) |
| `ws` | `lib/core/api/ws_client.dart` | a new frame field belongs to the printer, not the user (§6) |
| `ui` route | `GoRouter` observers in `lib/router.dart` — one `ModalObserver` per `Navigator`, root **and** every shell branch | you add a shell branch; without its own observer, sheets opened from that tab are not logged (§5) |
| `ui` tap | `InteractionProbe`, a global entry in `pointerRouter` resolved against the semantics tree | always — an untagged control records as `role=button` and nothing else (§1) |
| `err` | `FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded` in `lib/main.dart` | never |

So a new screen that calls the existing API client already logs its navigation,
its requests and its crashes. What it does not log is which control the user
touched, whether a refusal reached them, and anything that happens in another
isolate.

## 1. Name every control

An identifier is `area.thing`: lowercase, dots, never localized, **no data in
it**. The area is a screen or a sheet (`inventory`, `spool_form`, `queue_edit`,
`printer_files`, `setup`). All rows of a list share one id — `inventory.spool`,
not `inventory.spool.42`; which row it was is not what a report needs. A third
level is for buttons inside a dialog (`swatch_delete.confirm`) or menu entries
(`stats.range.month`).

Ids are **wire values**. The summarizing Action groups by them, so renaming one
breaks logs already sitting in an issue. Pick the name once.

Never interpolate: `'card.$name'` is not caught by anything. The redactor
deliberately leaves an `id` alone when it has the shape `\w+(\.\w+)*` — a server
named `printer` was otherwise turning `setup.demo` into `setup.[HOST]` — which
means an interpolated file name would ship intact.

| situation | how |
|---|---|
| ordinary widget | `logTag('area.thing', widget)` or `widget.tagged('area.thing')` (postfix, for long trees where wrapping would re-indent) |
| confirmation dialog | `confirmDialog(context, id: 'area.what_it_confirms_confirm', …)` names both buttons |
| `PopupMenuItem` | cannot be wrapped (`Semantics` is not a `PopupMenuEntry`) — the tag goes on its `child:` |
| hand-built `AppBar` (camera, G-code, QR) | `loggedAppBar(AppBar(…))` from `lib/core/theme/dash_theme.dart`, or the back button is nameless |
| you also need an a11y label | `Semantics(identifier: …, label: …)` directly — the scanner understands it |
| the control is one of a set and currently the chosen one | `logTag(id, w, selected: …)` / `.tagged(id, selected: …)` — **not** a `Semantics(selected:)` wrapper of its own |
| filament material | `logTagMaterial` / `.taggedMaterial` — the one on-screen value allowed into a log, and only from `FilamentMaterial.known` |

**A11y state belongs on the tagged node, not beside it.** A segment or a preset
chip says which one is current by its fill alone, so it needs
`SemanticsFlag.isSelected` — and that flag has to sit on the *same* node as the
identifier. Measured, not assumed: `Semantics(selected: …)` wrapped around a
tagged control annotates a different node, and the reader is told nothing at all
while the id moves. Hence the parameter on `logTag`. Nothing about the state
reaches the log; the probe reads the identifier only. `MergeSemantics` is safe
next to this — a merged node carries the identifier of the control inside it,
and the probe stops at a merged subtree by design. Both facts are pinned in
`interaction_probe_test.dart`.

**A shared widget must not tag itself.** A control used from several places takes
its `id` as a **required parameter** from the call site; a tag written into its
`build` makes every use report under the first one's name. Really happened: "Off"
and "Apply" in the temperature sheet both logged `temperature.apply`, so the log
claimed the user applied a temperature they had switched off. A required
parameter is what stops the compiler from letting the next nameless call site
through. When several tiles of one kind exist (nozzle / nozzle 2 / bed, three
fans), the **server's own key** goes into the id: `printer.temperature_nozzle_2`,
`printer.fan_aux` — the same vocabulary as the WS frame.

Target state: `python3 .claude/skills/log-coverage/log_coverage.py` (or
`/log-coverage`) reports **zero** unnamed controls. More than before your change
is a regression.

## 2. Decide whether the endpoint is sampled

Every request records method, reduced path, status and duration. A **content**
endpoint also contributes its record count plus one record in full, because a
200 hiding twenty rows and a 200 with nothing in it look identical otherwise.

That list is `_sampledPaths` in `http_probe.dart` — an **allowlist**: forgetting
an endpoint costs a diagnosis, forgetting one in a denylist costs a secret.
`_neverSampled` (`token|api-keys`) is checked first and wins. Add your route when
"the screen is empty / shows the wrong thing" is a question reports will ask
about it.

If a route interpolates user text into the path, `loggablePath` masks the
segment. Do not add a special case for it — the rule is measured against every
route in `Endpoints` by a test, so an endpoint written in a style the rule eats
fails CI instead of leaking into a report.

## 3. Record the refusal the user was shown

The error response is already an `http` record. What it cannot say is whether
anybody was *stopped*. `recordActionFailure` writes that, and it is reached
through the two shapes of caller:

- a screen holds a `BuildContext` → `showApiFailure(…, action: 'area.thing')`;
- a notifier does not → `ActionOutcome.failed(…, action: 'area.thing')`, worded
  later by a widget.

Pass `action:` in the `logTag` vocabulary — `action_tag_vocabulary_test.dart`
keeps the two in step. Pass `shown: false` where the message was built and then
not delivered (the screen was left while the request was in flight); absent means
it landed.

Do not move the recording into `localized` or into a constructor: about twenty
call sites there are error-state builders, and a widget stuck on an error
rebuilds — the run would sweep the ring buffer clean.

## 4. Notifications and background isolates

`showAlert` takes `event` and `printerId` as **required** parameters, so a new
notification cannot be added without a name in the log (an HMS `nid` is a
one-way hash, so the decorator could not work the printer out by itself). A
notification the app decides *not* to post records as `suppressed` with a reason
— and must collapse: one record for a run, not one per frame.

In a fresh isolate `DiagnosticRecorder.active` is null, and each isolate writes
its own file:

- **FGS** — a strict continuation of the UI stream. The session id travels
  through `SharedPreferences`, the header is the UI's re-tagged, so both files
  share one clock and the merge is a no-shift. **No readable UI header ⇒ the
  isolate does not record at all** — there would be nothing to merge into.
- **an isolate woken for one job** — the notification action engine
  (`handleMaintenanceAction`, `handleHmsAction`, registered in three isolates)
  and the watch-relay engine (`wear_relay_engine.dart`, started by
  `WearRelayListenerService` when the app's process is dead). One guard, not
  one per path: **call `DiagnosticRecorder.startAction()`** — it writes into
  the store that already exists where there is one, and otherwise opens a
  standalone `-act` stream for the caller to close. It cannot throw, which on
  these paths matters more than the record: the caller is carrying out the
  user's tap.

Two rules for anything you add on those paths: write the record **before** the
`await` that tears the isolate down (a closed `LogFileSink` drops lines
silently), and never let the recorder throw — the service's `onStart` runs
through a channel that swallows a Dart exception and reports success, so a
recorder that throws leaves a service that says "monitoring" and monitors
nothing.

## 5. Two traps in the navigation lane

Both are covered by tests; both were live bugs first.

- **The screen name comes from `router.state.matchedLocation`, not from
  `currentConfiguration.uri`.** Nearly every screen here opens with `context.push`,
  and the uri stays on the screen underneath — so the log names the wrong screen
  for exactly the navigation style the app uses.
- **One `NavigatorObserver` belongs to one `Navigator`.** Flutter asserts
  `observer.navigator == null`, so the root and every shell branch get their own
  `ModalObserver()`. Share one and the app crashes in debug; give the branches
  none and sheets opened from a tab are never logged.

## 6. Adding a field or a whole record

- **Whose is the value?** Everything the printer or the server owns goes in
  (states, stages, temperatures with targets, fans, slots, HMS codes, AMS). The
  user's own text — file, model, printer, spool and colour names — never does.
  "Is it worth the line" is the wrong question; it produced a first version that
  logged a third of a frame and left the rest to guess.
- **The field's name is behaviour.** `LogRedactor` blanks by key name
  (`token|api_key|key|secret|password|authorization|access_code|serial|cookie|username`),
  so a boolean called `cookie` ships as `"[REDACTED]"` whatever it held — caught
  live on the 2FA probe, where the record existed to tell two cases apart and
  told nothing apart. Name the flag beside the list (`binding`), and pin a test
  that it survives the redactor readably.
- **Collapse bursts into a count.** `ErrorProbe`, `WsProbe` and
  `InteractionProbe` each do this; a widget throwing in `build` throws sixty
  times a second.
- Use `LogStore.add(..., at:)` when the moment being recorded is not now — a
  button's handler runs before the probe sees the pointer lift, so a tap stamped
  at write time lands after the route change it caused.

## Before you ship

1. `flutter analyze` && `just test`.
2. `/log-coverage` → 0 gaps.
3. After bulk tagging, check **where** each tag landed: a misplaced `logTag`
   wraps a `ButtonStyle` or an `Icon` and still type-checks, so the analyzer says
   nothing. Same for `confirmDialog` — line the `id:` up against the `title:`,
   twice they were off by one and the log claimed the user had confirmed
   something else.
4. A live recording (the user runs it — see the run-app-emulator skill). Every
   `role` without an `id` is a control the scanner counted as covered on trust.
5. Read the report preview: no user text, no host, no key.

## Ceilings, so a truncated report reads right

A session ends on whichever comes first and the closing record says which —
`limit_reached`, not `recording_stopped`. **30 minutes** (`recordingLimit`) or
**20 MB** (`recordingSizeLimit`, ~30× what a busy half hour produces). The ring's
own caps — 20 000 records, 4 MB — are runaway guards, not budgets: the report is
read back from the file, which nothing evicts from.

## Test patterns already in the repo

`log_store_test` (ceilings), `log_file_sink_test` (store + sink on a temp dir),
`ws_probe_test` (recorder with `resolveDirectory: () async => null`),
`background_recording_test` (background stream, rejected headers, clock run
backwards), `log_merge_test` (`iso`, three-way merge), `redaction_lanes_test` and
`log_redactor_test` (assertions against the **raw** JSONL that a model or printer
name appears nowhere), `notif_probe_test` (suppression collapsing),
`action_tag_vocabulary_test` (`action:` strings match real tags).
