# How a notification gets its content and its buttons

The rules for *when* to alert are in [notification-rules.md](notification-rules.md).
This is what happens to an alert once it exists: the contract of
`NotificationService`, the finish photo that arrives after it, the buttons on
it, and which HMS faults count at all. The code keeps one line per rule.
`lib/core/notifications/`.

## The alert contract (`NotificationService`)

- **`showOngoing`** draws one ongoing notification with a progress bar. A null
  `progress` means "running, position unknown" (heating, levelling, anything
  before the first percent) and draws the *indeterminate* bar; that is not
  `clearOngoing`, which is for nothing printing at all. It takes no diagnostic
  arguments: the record is written by `PrintMonitor._updateOngoing`, the only
  place that holds printer, percentage, ETA and print count as separate values;
  here they are baked into a title and body that never enter a log.
  `LocalNotificationService.showOngoing` is a no-op on purpose: the only
  production monitor runs in the background isolate against
  `FgsNotificationService`, whose ongoing notification *is* the foreground
  service's, and a second one on another channel would be a duplicate. The method
  stays only so the class still satisfies the interface.
- **`showAlert`** takes `event` and `printerId` for the diagnostic log and
  *requires* them, so the compiler refuses a new notification without a name.
  Neither can be recovered from the other arguments: `title` and `body` are the
  user's own file and printer names, which never enter a log, and `id` is a
  one-way hash for HMS alerts. `LocalNotificationService` ignores them; the log
  wraps the service from outside (`LoggingNotifications`).
- **`picture` marks an update of an alert already on screen**: the finish photo
  lands after the print-finished alert, never with it, so it re-posts silently
  (same `id`, no second sound or buzz, on the phone and a paired watch alike).
  `quiet` says the same for an update without a picture (the outcome buttons
  added to a finished alert). `onlyAlertOnce` follows from either.
- **`AlertPicture`**: both paths are files on *this* device, read at post time;
  the plugin decodes them and puts the bitmaps inside the notification. That is
  what lets the photo survive the trip to a paired watch, which mirrors the
  notification but cannot open a phone file path. The thumbnail is the collapsed
  state's; expanded, the photo is already there and a large icon would take room.
- **`isAlertActive`** is false for one the user swiped away: re-posting it to add
  a photo would resurrect it. A platform that will not answer reads *true*:
  treating the notification as gone would drop the photo for everyone on that
  device.
- **Action buttons**: `opensApp` brings the app up instead of running the action
  where it was tapped (stopping a print cannot be taken back, and the app is the
  only place a confirmation can be shown); `dismisses` false keeps the
  notification for an answer that may fail, and the handler removes it once the
  answer landed. Android's shade lays out **three** and drops what follows
  without a word.
- **Channel health**: app-level permission is not the whole story. A user can
  mute the one alerts channel and keep everything else, which looks like a
  granted permission and delivers nothing; `alertsChannelImportance` reads it
  (`Importance.none` is 0). `notificationsEnabled` *asks* instead of requesting,
  so it is safe in the background where prompting is impossible.

## The finish photo (`FinishPhotoNotifier`)

The alert goes out when the printer reports the print over; the server's photo
exists a minute or so later. The notifier finds the alert the print left behind
(`FinishAlertMemory`) and re-posts it, same id, with the picture. Android replaces
it in place and a paired watch gets the update over the same bridge. Nothing here
is load-bearing: no alert, a notification already swiped away, a download that
failed, each ends quietly and leaves the text-only one as is.

- **Two ways in, because the server announces only one.** An `archive_updated`
  frame with `photo_added` is sent from exactly one place
  (`main.py::_upgrade_finish_photo_from_timelapse`), reached only when a print
  recorded a timelapse whose video was still in transit. The ordinary capture
  (every other finished print) is written straight to `archive.photos` with
  nothing on the wire, which is why `poll` has to go looking while an alert is
  live; the frame is the fast path for the case it does cover.
- **`poll` reads the work list from `FinishAlertMemory`**, not from a callback on
  the alert, so an app opened mid-window takes the search over from the
  background service that started it: the entry outlives the isolate.
- **`runForAlert`** is never "the first of `recent`": the server orders by
  `created_at`, which a reprint leaves on the original print because it reuses
  the archive row. `completed_at` moves with the run, so it is the one to match,
  and requiring it near the alert is what puts *no* photo, not a wrong one, on a
  notification when nothing here belongs to this print.
- **`finishPhotoIn`** takes the newest shot the server itself took. Neither end of
  the list is the answer (captures and uploads append, the timelapse upgrade
  prepends, a reused row keeps every run's photos); the name each capture path
  builds orders them, `finish_<YYYYMMDD>_<HHMMSS>` sorting chronologically as
  text. Uploads carry no such name and are skipped.
- **The alert is asked about again after the download**, which can run the better
  part of a minute (connect and receive timeouts, plus a retry after a 401). A
  notification swiped away inside that window would be brought back by the post,
  and Android counts a post after a cancel as new, so it would ring again for a
  print already dealt with. The memory entry is **re-read** too: the other
  isolate may have put the outcome buttons on while this one downloaded, and
  re-posting the entry as it was would take them off.
- **`addOutcome`** puts the outcome buttons (#1898) on the same notification and
  answers whether it did (false: the caller asks with a notification of its own).
  It goes through the *same queue* as the photo: both re-post one notification
  and each has to carry what the other added.
- **`dispose` is bounded** (2 s): it is awaited inside
  `PrintMonitorTaskHandler.onDestroy` ahead of the socket's dispose and the
  recording's flush, and a poll against an unreachable server sits on Dio's
  connect and receive timeouts. Whatever is in flight finishes on its own.

## Button taps (`background_api.dart`)

A tap runs in whichever isolate the plugin delivered it to, so nothing can assume
Riverpod or the UI.

- **`backgroundAuthService`** is what the isolates without Riverpod build. A
  rejection noticed out here happens hours before the user next opens the app,
  and the flag left in prefs is the only thing that lets the UI explain the
  silence; both isolates must leave the same mark.
- **`buildBackgroundApiClient`** mirrors `apiClientProvider`. A caller that also
  opens a socket or a token refresher passes its own `credentials` and `auth`:
  silent re-login is single-flight per `AuthService`, so a second instance for
  the REST lane is a second login racing the first against the server's
  failed-attempt budget.
- **`_runAction`** opens the recording first, so everything after it is on the
  record; records the tap; builds a client for the saved server from preferences
  **re-read off disk** (the other isolate may have switched servers since this
  one opened them); and records every failure instead of throwing: the callback
  cannot crash, and a swallowed error is "I pressed it and nothing happened".
  `failedItems` is what the failure record says was still pending when the whole
  handler broke; null where `run` records its items one by one.
- **Outcome buttons** (`handleOutcomeAction`): Good and Reject are recorded from
  here, like "Mark Done": a reject *without* a cause, and never touching one the
  print already carries. The notification body opens the app, so it only arrives
  where the app is coming up and is handed to the shell's sheet, where a reject
  can be given a cause. The buttons do not dismiss the notification themselves
  (the server asks once): it is taken away here once the answer landed, or once no
  retry can land it: a refusal, or a question from a server the app has since been
  switched away from, whose archive id names some other print here.
- **HMS actions** (`handleHmsAction`): stopping a print never runs from a
  notification. A tap that abandons hours of printing has to be confirmed and a
  notification has nowhere to ask, so that button brings the app up and the
  request is parked in `hmsStopRequests` for the shell. **Known gap:** an HMS action
  answered after the user switched servers sends its command to the *new* server's
  printer with the same id, because the action payload carries no server tag (the
  print-outcome notification has one).
- **Maintenance "Mark Done"** rebuilds everything from scratch (prefs, client,
  repository), resets the item counter, removes the items from the dedup set
  (re-arm for future alerts) and dismisses the notification. All errors are
  swallowed: the callback must not throw.

## Which HMS faults count (`hms_catalog.dart`)

- **Description lookup** (`HmsCatalog.describe`): the lossless full code first,
  then the short form for a `print_error` fault from a server too old to send
  `full_code`, then the English sentence a 1.2.5.4+ server attaches, last because
  this table is the localized one. **Never the short form of an `hms[]` code**
  (`hms_errors.py::lookup_fault`): no real one has an error group at or above
  0x4000, where every `print_error` key sits, so the collapse only ever found a
  neighbouring fault's sentence (#2728). A missing or corrupt asset is an empty
  table, which reads every code as unknown and hides the panel rather than filling
  it with raw hex.
- **`hmsIsDisplayable`**: only a fault the client can name: parity with
  bambuddy's `filterKnownHMSErrors`, with one departure. bambuddy keeps an
  uncataloged fault when the firmware offers actions for it; a card headed by a
  bare hex code asks the user to gamble, so it is dropped here. **No "recognized
  severity" escape hatch**, deliberately: before #2728 `severity` was not the HMS
  level. bambuddy derived it as `(attr >> 8) & 0xF`, BambuStudio's `part_id`,
  while the level lives in `code >> 16`. Against the bundled catalog the two agree
  on 39% of codes, and 835 arrive as level 1 ("Fatal") while being nothing of the
  sort, which is where the invented "Fatal · mainboard" label on a healthy X2D
  came from.
- **`displayableHmsErrors`**: **a disconnected printer has none**, whatever its
  `hms_errors` still say. `PrinterStatus.mergedWith` carries the codes through an
  outage on purpose, so the notification path can pause its clear-grace clock on
  them, and this is the one place that answers "last-known, not live".
  `describe` is *required*, not defaulted to `HmsCatalog.instance`: the
  home-screen widget and the notification isolate hold their own catalogue or
  none, and a hidden fallback would hand them the UI isolate's.
  `firstDisplayableHmsError` exists so the walk stops at the first hit: the
  dashboard filter asks it of every printer on every rebuild, the home widget on
  every publish.
- **`hmsIsNotifiable`** is `hmsIsDisplayable` plus bambuddy's level rule
  (`main.py::_hms_fault_counts`). One physical fault makes the firmware emit
  several codes at once, most undocumented, and a described code the card lists
  can still be too quiet to wake anybody for. It reads `HmsError.level`, never
  `severity`: the old `severity >= 2` floor dropped exactly the faults that stop a
  print. A numeric code with no level is Bambu's "invalid" 0; a fault without
  `attr` (the legacy `{code, message}` shape) is left to the text checks. An
  `hms[]` notification without actions ("top cover open", "chamber hot, fan up")
  can stand through a whole print and does not notify; a `print_error` prompt at
  the same level still does, as on the server.
- **Labels**: `hmsLabel` is the server message, else what the catalog resolved,
  else null, never anything composed from `severity`/`module`; the card shows the
  code separately. `hmsHumanText` falls back to the bare code, which only callers
  that bypass `hmsIsDisplayable` can reach.
- **`hmsWikiUrl`**: per-code wiki pages exist for the `hms[]` channel only (its
  16-hex code maps to `hmscode/0500_0500_0001_0007`). A `print_error` fault has no
  page of its own (every URL shape 404s) and its 8-hex `full_code` cannot be
  padded into one: `HmsError.ecode` would compose 16 hex out of a 32-bit value
  that means something else, which is how a link lands on a page about a
  different fault. Those get bambuddy's own answer, the HMS index.

## Testing an alert without printing

- `dart run tool/fake_bambuddy.dart` is a fake REST+WebSocket server with no
  dependencies; its header explains the commands (`finish`, `fail`, `photo`, `go`).
  A phone on the LAN uses `http://<ip>:8099`, or `adb reverse tcp:8099 tcp:8099`.
  **The app must be in the background**, otherwise there is no service and no alert.
- To check only how a watch renders a big picture:
  `adb shell cmd notification post -S bigpicture --picture data:base64,<…>`. Two
  misleading traps: after `adb root` the call fails with `NameNotFoundException: root`
  (use `adb unroot`), and `file:///data/local/tmp/…` fails under SELinux and is
  reported as "not a bitmap". Wear OS 5 renders the picture only once expanded.

## The system 12/24 h setting

The `flutter/settings` channel is sent **only** by an engine that has a view, and
only when the view attaches. Two separate bugs follow from that:

1. **The foreground-service isolate never receives it.** `ForegroundTask` creates a
   bare `FlutterEngine(context)`, so `PlatformDispatcher.alwaysUse24HourFormat` is
   always `false` there — a phone set to 24 h got `ETA 8:29 PM`. The locale does
   arrive (the engine sends it from `Configuration`); the clock does not.
2. **The UI receives it once and never refreshes.** Switching the clock in Android
   settings and returning to the app does not change `MediaQuery` until the process
   dies.

The fix is a native channel (`…/clock` → `DateFormat.is24HourFormat` in
`MainActivity`) asked by `SystemClockSync` (in `MaterialApp.builder`) at start and
**on every resume**. The answer overrides `MediaQuery` for the whole tree and lands
in `DateTimeFormats.rememberSystemClock` and in the `clock_24h` preference, which the
service reads (`onStart`, plus a `BackgroundSync.clock` ping that
`publishSystemClock` sends after writing the preference, when the service is
running). No answer
means the locale convention (the `jm` pattern), never a hard-coded 12 h. **Every
other `MediaQuery` system setting (font scale, brightness) has both problems.**

A 12 h clock makes the ETA about 20 px wider, which stopped the
`remaining / ETA / layers` row on the print card from fitting and let a `Wrap` break
it anywhere. `PrintMetaRow` now measures its text and drops to a two-column grid (or
one column). **Measurement trap:** a `TextPainter` with the widget's own style is not
enough — `Text` merges the style with `DefaultTextStyle` (the theme's `bodyMedium`
has `letterSpacing: 0.25`, about 8 px over the whole row), and an `Icon` scales with
the font only when `IconTheme.applyTextScaling` is set. Measure with the `.merge()`d
style, add slack, and put the element in a `Flexible` proportional to the
measurement, so an error ends in an ellipsis rather than overflow stripes.
