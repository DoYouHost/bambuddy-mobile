# Riverpod lifecycle traps

Traps that cost time here and that neither `flutter analyze` nor the rest of the
suite shows. The first two surfaced only in a widget test. **Read it before writing
a provider that is watched from a sheet, seeded from `initState`, or derived from an
async source.** Shape of `lib/providers.dart` itself: [providers.md](providers.md).

## 1. `ref.watch` in a sheet's builder does not work, and does not complain

`dashSheet(context, builder: (ctx) => … ref.watch(x) …)` called from a
`ConsumerState`: the `ref` belongs to the screen and the sheet lives in its own
route, so the subscription registers on the screen and **the sheet never rebuilds**.
Symptom in `file_manager_screen`: the "Run pipeline" row never appeared, even with
the gate resolved to `true` before the sheet opened.

Use `ref.read` in a sheet builder when the value is already known, or **a `Consumer`
of its own** around that fragment when it is still resolving — gates that poll the
server are exactly that. `ref.read` alone is not enough for a `FutureProvider`: for
the first frames it is unresolved and the control would hide on a server that has
the feature.

## 2. Writing to a provider in `initState` throws

"Tried to modify a provider while the widget tree was building" — applies to
`build`, `initState`, `dispose`, `didUpdateWidget`, `didChangeDependencies`. Symptom:
tapping "Run history" on a pipeline card crashed the screen in debug because
`initState` seeded the filter through `notifier.replace(...)`.

Pass the initial value as a **separate seed provider overridden in a `ProviderScope`**
around the screen, not by writing to the notifier. Riverpod then needs an explicit
`dependencies: [...]` on every provider that reads the seed indirectly, or you get
"tried to read X from a place where one of its dependencies were overridden but the
provider is not". Deferring the write to `addPostFrameCallback` works but costs a
first fetch without the filter and a second with it.

## 3. `FutureProvider` reports a loading frame even for a ready answer

The body `(ref) async => …` always returns a `Future`, and Riverpod reports
`AsyncLoading` first for every `Future` — even when the source is already
`AsyncData`. A gate warmed at startup still said "don't know" on the **first** look
at every screen, and `.orFalse` in the consumer turned that into one frame without
the control. Proof: `container.read(gate)` right after `await read(source.future)`
→ `isLoading`.

A value derived from an `AsyncNotifier` is
`Provider<AsyncValue<T>>((ref) => ref.watch(src).whenData(read))`, not a
`FutureProvider`: synchronous, no hop, keeps the previous answer during a refetch
(`AsyncData` with `isLoading: true`) and passes an error through. Two neighbouring
traps:

- a `FutureProvider` that `watch`es *both* the source's `AsyncValue` *and* its
  `.future` **hangs forever without a listener** — a state change invalidates it and
  nobody rebuilds it ("disposed during loading state");
- `ref.read` as a warm-up **does not survive a server profile change** — a provider
  without a listener is only marked stale and fetches at the next read; warm up with
  `ref.listenManual`, not `ref.read`.

## 4. A `FutureProvider` without `autoDispose` defeats the retry underneath it

`ServerVersionService` has a written and tested 5-minute retry window after a
network error — and it was **dead for the drawer**: a kept provider remembers its
first answer for the container's whole life, so a drawer opened once in a lift showed
"unknown version" until the process died. The window ticked, nobody asked again.
Pull-to-refresh on the dashboard did not invalidate it either.

Use **`autoDispose` plus a conditional `ref.keepAlive()` on success**. `autoDispose`
alone swaps one flaw for another: every new `FutureProvider` starts at `AsyncLoading`,
so each reopening of the drawer would flash "Server …" before an answer the service
already holds. The link is taken **before** the `await` (`keepAlive` belongs to the
build; closing a link after dispose is safe, taking one is not) and closed on an
unknown answer:

```dart
if (ref.watch(profile) == null) return null;      // synchronous, no frame
final keep = ref.keepAlive();
return service.read().then((v) { if (v == null) keep.close(); return v; });
```

Two tests, both mutations must fail: (a) after an error and the window's expiry the
next open gets the version — mutation `autoDispose` → plain `FutureProvider`;
(b) after success `container.read(p)` is `AsyncData` at once — mutation removing
`keepAlive`. On dispose: `sub.close()` → `await Future.delayed(Duration.zero)`,
because autoDispose runs only on the next turn.

## 5. `AsyncLoading` and `AsyncError` carry the previous value

Riverpod 2.x does `copyWithPrevious` on refresh, so `switch (v) { AsyncData(:final
value?) => …, AsyncLoading() => '…', _ => 'unknown' }` **blanks a known value** on
every refetch and throws it away on an error. The order must be reversed: first
`v.valueOrNull`, then `v.isLoading`, last "don't know". The test must build the state
with `const AsyncLoading<T>().copyWithPrevious(const AsyncData<T>(x))` — a bare
`AsyncLoading()` passes on both variants.

## Why the tests are shaped this way

The first two are caught only by a widget test that really opens the sheet or the
route; the third by a unit test that **first waits for the source to settle** and
only then reads the derived value — a test that reads at once passes on both
variants.

## 6. `ref` dies with its widget: a flow with an `await` must not read through it

`WidgetRef.read` / `watch` / `listen` call `_assertNotDisposed()`, which throws a
plain `StateError('Cannot use "ref" after the widget was disposed.')` once
`!context.mounted` (flutter_riverpod 2.6.1, `consumer.dart`). It is not a debug
assert, so every `ref.read` after an `await` is a crash waiting for the widget to
leave. The realistic case is not a tab change (the tabs are an `IndexedStack`, so
a screen stays mounted) but a **row disappearing**: queue rows are keyed by item id
and the list rebuilds on every WebSocket refresh.

- **A short flow** (one request): read what the flow needs *before* the `await`,
  next to `ScaffoldMessenger.of(context)`. The plate-clear banner in
  [printer_card_details.dart](../lib/features/dashboard/widgets/printer_card_details.dart)
  does.
- **A long flow** (picker, sheet, dialog, two requests): take
  `detachFrom(context)` ([app_context.dart](../lib/core/app_context.dart)) before
  the first `await`. It returns the app's `ProviderContainer` and the
  `ScaffoldMessengerState`; the container outlives every screen, and each
  `providers.read(...)` stays fresh at the point of use, where a snapshot taken
  before the sheet would be stale. Used by the queue start flow
  (`startQueueItem`, [queue_actions.dart](../lib/features/queue/queue_actions.dart))
  and the other detached flows; do not "fix" one back to `ref`.
- **A helper called after the request returns takes the object, not `ref`**:
  `recordPlateClearRefusal(OfflinePlateClearNotifier, String?)` in
  [plate_clear.dart](../lib/features/common/plate_clear.dart) has nothing to reach
  the widget with.

Two neighbouring traps:

- **`notifier.state` is not readable from outside** (`@protected`,
  `@visibleForTesting`; the analyzer reports it). Read live state with
  `container.read(provider)`, not through a notifier you kept.
- **A kept `autoDispose` notifier moves the crash, it does not remove it.**
  `queueProvider` is `autoDispose` and survives a row vanishing only because the
  tab badge in `RootScaffold` watches it.

The regression test keeps the `ProviderScope` stable (the app's container never
goes away) and removes only the widget; anything else tests something different.
Patterns: "a refusal that lands after the card is gone still counts" in
[printer_card_test.dart](../test/features/dashboard/printer_card_test.dart) and
"start flow outliving the row that began it" in
[queue_screen_test.dart](../test/features/queue/queue_screen_test.dart).
