# The watch's fleet poll

`lib/wear/wear_providers.dart`. The watch has no WebSocket and no background
service (deliberate: battery); its view of the printers is a poll that runs only
while a screen watching `wearFleetProvider` is mounted. The code keeps one line
per rule; the reasons are here. Tests: `test/wear/`.

## Transport (`wearTransportProvider`)

- Relay through the phone (Data Layer / Bluetooth) first, direct REST as the
  fallback. REST needs a configured profile; a relay-only watch has none (the
  repositories cannot even be built, `apiClientProvider` throws), so `rest()` is
  only called on a branch that has one.
- **Not `autoDispose`.** Callers only `read` it, and an `autoDispose` provider
  with no listeners is disposed right after creation, which cancelled the relay's
  reply listener while a request was in flight (the command ran on the phone, the
  watch reported a timeout). It also has to keep `HybridWearTransport.lastMode`
  across polls for the adaptive cadence.
- **Demo is REST only.** Demo runs entirely in this process (the API client swaps
  in the fake backend), so there is nothing for the phone to answer, and asking
  it would return the real fleet from the real server it is configured for. Demo
  is itself a profile, which is how REST is there to take the relay's place.

## Adopting a pushed config (`PendingWatchConfig.adopt`)

`adopt` persists the config, clears the offer and re-reads the profile so the app
re-routes. It **rethrows** what secure storage threw: whether that becomes a red
line, a spinner coming back or nothing at all is the screen's business, and only
the screen knows whether it is still alive; a notifier cannot check somebody
else's `mounted`. A failure leaves the offer standing, so the button that
started it can try again.

The profile is invalidated **only when it actually changed**. Invalidating
rebuilds the transport too, which disposes the relay's reply listener under any
request already on the bridge; the phone pushes the same config on every launch,
so every cold start used to pay a relay timeout for its first poll. A refreshed
secret needs no invalidate: `authHeaders` reads the store on each request.

## `WearFleetNotifier`: three flags and an epoch

- **`_epoch`** says which run is the current one. Riverpod builds the notifier
  once and keeps the instance across every rebuild, while still running the
  `ref.onDispose` the previous build registered. A one-way `_disposed` latch
  therefore stayed set from the first rebuild on, and the watch adopts the
  config the phone pushes at every launch, which is a rebuild: every later poll
  dropped its answer and the cold-start frame stayed dimmed, buttons off,
  waiting for a state that could no longer arrive. The epoch is bumped by every
  build *and* every poll, so an answer belonging to an earlier one is recognised.
- **`_alive`** is whether the notifier is mounted at all (false once the provider
  is gone, and for the instant a rebuild takes). The epoch cannot answer that
  alone: a disposed notifier's epoch still equals itself.
- **`_paused`** is set while the app is in the background. Every relay poll wakes
  the phone over Bluetooth and a screen nobody looks at has nothing to update.
  It is checked in `_scheduleNext`, not only at `stopPolling`, because a fetch
  already in flight when the app goes away would otherwise come back and re-arm
  the timer the pause had just cancelled.

## `build`

- The profile is **watched, not read**: switching the server on the watch has to
  empty the state, not leave the old server's printers on screen until a poll
  replaces them. The rebuild resets the state and re-reads the cache, which is
  keyed by base URL and so answers nothing for the new server.
- A cached fleet is painted at once and refreshed underneath, through a
  **zero-length timer**, not a direct call: the poll may only start once `build`
  has returned, and `refresh` bows out while there is no value. The timer is also
  already the field `onDispose` cancels, so a screen left before the first poll
  takes it along. Not while paused: a rebuild reaches here in the background too
  (the phone pushes its config on every launch) and would restart the poll behind
  a dark screen; the resume hook starts it instead.
- **No cache: fetch even while paused.** `build` owes its caller a fleet, and the
  alternatives are worse than the one poll it costs: an empty frame says "no
  printers", and waiting for the resume hook hangs the screen on a spinner if it
  never comes. Only reachable with no cache, i.e. a server switch pushed while
  the app is away.
- A superseded fetch still returns its fleet (what `build` answers is assigned
  by Riverpod, not by this method) but arms no timer, which would cancel the
  current run's.

## `_fetch`

The profile is read **before** the request: `ServerProfileNotifier` changes its
state synchronously, so a poll answering in the same turn as a server switch
would file the old server's fleet under the new one's URL. (`_epoch` covers the
ordinary case, where the rebuild has run first.) The cache write is not awaited
and never fatal, and is skipped once superseded: the answer is not this run's,
and past a real dispose `ref` throws.

## Cadence (`_scheduleNext`)

Every relay poll wakes the phone, so it backs off to **30 s** when nothing is
printing or paused; direct REST, or an active print, keeps **5 s**. An unknown
fleet (the fetch failed) polls fast to recover. The second reason to slow down
arrived with the cold-start cache: a poll that failed while something is still
on screen. Before the cache a failed first fetch left the provider in its error
state and `_scheduleNext` was never reached, so an unreachable phone cost
nothing; keeping the frame means keeping the timer, and 5 s of it only wakes the
bridge for an answer that is not coming.

## `refresh`

- It is also the way out of `stopPolling`: every caller (resume hook, pull to
  refresh, the tick after a command) means the screen is watched again.
- **Nothing may outrun a build.** Whatever refresh wrote would be wiped when the
  build's own fetch answered, because Riverpod assigns what `build` returns
  regardless of what the notifier did meanwhile, so the newer frame would be
  replaced by the older one, or by its error (the 15 s relay timeout a resume can
  easily beat). The guard is `isLoading` alone, because the two kinds of rebuild
  do not look alike: an invalidate drops the value (`hasValue` false), a
  dependency change keeps it and only sets `isReloading`. Testing for the missing
  value would have covered the first cold start and left the server switch, the
  one rebuild with no cache and a real fetch to lose. Nothing else sets loading
  here, since refresh only ever assigns a settled state.
- The tick is cancelled **before** anything else: one armed earlier would mature
  while this request is out (a relay call can be out for 15 s waiting on a phone
  whose engine is booting) and put a second identical RPC on the bridge. Every
  path back in re-arms it on the way out.
- A tick that had already fired cannot be cancelled, so two polls can be out at
  once; bumping the epoch makes the older one give way instead of answering last
  and putting the older fleet on screen.
- `unconfirmed` is whether what is on screen has ever been confirmed by this run.
  A frame restored from the cache has not.
- **A failure keeps confirmed data** (one bad tick should not blank a screen that
  was right a moment ago). Everything else, the never-confirmed frame included,
  goes through as an error: a failed connection has to read as one, and the cache
  buys a first frame, not a licence to keep showing last run's printers while
  nothing can be reached. `WearHome` then offers its retry.
- After an error nothing is scheduled: the retry invalidates the provider, whose
  `build` starts the poll again. Left running it would wake the bridge every few
  seconds behind an error the user is already at.

## `WearFleetView.drawable`

Riverpod keeps the previous value when the state is set to an error, so
`valueOrNull` still answers with the fleet that was on screen. A screen switching
on the variant (`WearHome`'s `when`) never sees that; a body reading `valueOrNull`
would draw last run's printers under a dead bridge. An error is therefore always
the answer, never the old frame: the notifier only sets one where the data on
screen has not been confirmed, and a `build` that fails after a server switch
must not leave the previous server's printers up either.
