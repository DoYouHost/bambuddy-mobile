# Android platform notes (phone)

Things that live in `android/` or depend on the Android version, device or
renderer, and that the code alone does not explain: the Android 16 Live Update,
the camera stream's ANR history, the home-screen widgets and the overscroll
stutter. The watch's own platform notes are in [wear-os.md](wear-os.md). Where a
number is a measurement it says on what setup it was taken; none of them was
re-run when this file was written.

## The print progress as an Android 16 Live Update

`OngoingNotificationHost.kt` puts a progress bar on the foreground service's
notification and, on Android 16, asks the system to promote it to a Live Update
(status-bar chip with the percent, lock-screen card). What the notification says
and which printer it names is in
[notification-rules.md](notification-rules.md#the-ongoing-notification); this is
the platform side.

- **It edits the plugin's notification instead of building its own.**
  `flutter_foreground_task` owns the notification and takes a title and a text
  only. The host recovers the one it posted (`Notification.Builder.recoverBuilder`)
  and re-posts it under the service's own id, which is the call the plugin makes
  to update itself. That keeps the plugin's content and delete intents without
  copying them. `lastPosted` is the recovery source once there is one: Android 14+
  lets the user swipe a foreground-service notification away without stopping the
  service, and then there is nothing in `activeNotifications` to recover from.
  Any failure returns false and the Dart side posts through the plugin, which has
  no bar: a notification without a bar beats a service without one.
- **Every branch sets every field any branch touches** (style, short critical
  text, promotion request). The recovered builder carries the previous style and
  extras forward, so a finished print's bar, chip and promotion would otherwise
  stay on the idle "monitoring" notification, which Android 16 would go on
  promoting. The chip says the percent, not the ETA: the ETA is a clock time
  whose 12/24-hour format is resolved in Dart.
- **Live Updates need API 36.1 (the Android 16 minor release), not 36.0.**
  `POST_PROMOTED_NOTIFICATIONS`, `Builder.setRequestPromotedOngoing` and
  `Notification.EXTRA_REQUEST_PROMOTED_ONGOING` exist only from 36.1. `compileSdk`
  is 36, so the typed call does not compile and the extra is written by hand
  (`android.requestPromotedOngoing`, `EXTRA_REQUEST_PROMOTED_ONGOING`); on a 36.0
  device the request is simply ignored. Measured on a 36.1 emulator: the chip next
  to the clock and the lock-screen indicator both appear.
- **The permission is a normal one** (no runtime prompt, no Play declaration) and
  a request is only a request: the user can switch promotion off per app. It is in
  the main manifest and stripped from the watch's
  ([play-compliance.md](play-compliance.md)).
- **One UI 8.5 grants the flag and draws nothing.** Measured with `adb` during a
  print on a Galaxy S25 Ultra (Android 16): the system sets the
  `PROMOTED_ONGOING` flag, `ProgressStyle` and the short critical text are on the
  notification, and there is no status-bar chip and no lock-screen card. Ruled out
  by measurement: the channel's importance, AppOps (One UI adds its own `appop`
  gate that AOSP lacks, and allowing it changes nothing) and the permission. What
  is left is a Samsung-side allow-list (`settings system` keys of the form
  `key_now_bar_<package>`) that no app can enter. One UI 8.5 reports `sdk=36` with
  no minor version yet carries the 36.1 notification stack, so the version check
  cannot tell it apart. The promotion code stays: it works fully on stock 36.1,
  and on Samsung the bar in the shade still works.

## Camera stream and the ANR history

`lib/features/camera/mjpeg_frames.dart` cuts the byte stream into JPEG frames and
`mjpeg_view.dart` draws them, replacing `flutter_mjpeg` (no longer a dependency).

- **The 0.14.1 ANR was `flutter_mjpeg`.** The Play Console report (one event, an
  Android 16 phone): the main thread in the Dart GC (`Heap::AllocateOld`,
  concurrent marking), the allocation coming from the package's
  `_StreamManager.updateStream` growing a `List<int>` byte by byte on the UI
  isolate. The package had no cap on a frame that never ends and created a new
  uncached `MemoryImage` per frame. Since 0.15.0 the view uses a `BytesBuilder`
  with an 8 MB cap (`defaultMaxFrameBytes`, after which it drops the frame and
  resynchronises on the next SOI), scans each chunk once, and evicts the previous
  frame's image from the cache when the next one replaces it.
- **If a camera ANR shows up on 0.15+**, look at the frame splitter first. An
  earlier version re-joined the whole buffer for every chunk, which is quadratic
  (`1ebfaaef` made it a single linear pass); a regression would show up as the
  same GC stack.
- **A second report on 0.15.0 is not actionable.** A MIUI device, one user, one
  event: "Input dispatching timed out (No focused window)" with the main thread
  idle in `nativePollOnce` and no app frame on any visible thread. The paste was
  cut before the UI thread's stack. Watch for repeats; without that stack there is
  nothing to fix.

## Home-screen widgets

Two App Widgets on `home_widget` and `RemoteViews` (not Glance; the Glance
components that `home_widget` pulls in are removed from the watch APK): the single
printer `BambuddyWidgetProvider` and `BambuddyMultiWidgetProvider` (up to three
rows plus a "+N more" line). Kotlin is in `android/app/src/main/kotlin/…`, the
publishers in `lib/core/widget/`. `updatePeriodMillis` is 0 because the app pushes
the data; the receivers are declared in the manifest, which is also what keeps R8
from removing them.

### RemoteViews traps

Each of these cost a render from scratch; the launcher's only symptom is a generic
"could not load widget".

- **`<Space>` and `<View>` are not supported.** A filler is an empty `<TextView>`
  with `layout_weight` (or an `ImageView`, where the layout comments say so).
- **A shape as an `ImageView`'s `src` does not render** (no intrinsic size). A
  chip, outline or pill is the *background* of a view, with the colour set through
  `setBackgroundResource` per status (`widget_chip_*`).
- **Do not derive sizes from `OPTION_APPWIDGET_*` in Kotlin.** `MIN_HEIGHT` is the
  landscape variant and understates; upright the real height is closer to
  `MAX_HEIGHT`. Sizes come from weights in the layout instead: the meta line and
  the progress bar (`wrap_content`) claim their room first and the thumbnail
  (`0dp` with weight) takes what is left, on any density and launcher.
- **Responsiveness is gated on width, not height.** Both providers read
  `OPTION_APPWIDGET_MIN_WIDTH` and swap to the compact layout below
  `COMPACT_MAX_WIDTH_DP = 190` (a 2x2 reports roughly 110-150 dp, a 3x2 roughly 210
  dp and up); `onAppWidgetOptionsChanged` re-renders after a resize. The compact
  ring (`WidgetGauge.kt`) is a Canvas bitmap; the percent and the label are
  `TextView`s on top of it, so they stay sharp and localizable.
- **A fixed-width element pushes its neighbour off the edge.** The name and status
  sit in an inner `LinearLayout` with `weight=1` and the scan button outside it
  (`wrap_content`), or the icon is clipped.

### Publishing

- **Two publishers write the same widget.** The foreground
  `PrinterStatusesNotifier` publishes after every change (`_publishWidget` in
  `ws_providers.dart`) and the foreground service's isolate publishes from its
  `ws.statuses` listener (`print_monitor_task_handler.dart`). With the app closed
  the isolate is the only live source, so everything the widget needs (the HMS
  description, the cover) has a variant that works without Riverpod and is handed
  in as a callback (`describeHms`, `fetchCover`).
- **The cover** is fetched with the media credential, retried on 401
  (`widget_cover_cache.dart`), cached per isolate by URL, written to one fixed file
  by write-then-rename (two isolates write it with no lock between them), and
  decoded natively with a downsample to about 512 px to stay inside the
  `RemoteViews` transaction limit.
- **Language follows the system** (`systemAppLocalizations()`), not the app's own
  setting.
- **Which printer:** the first one actively printing, otherwise the first by `id`.
- **Offline never carries an HMS error.** The publisher drops the top HMS error
  when the status is offline: an error carried forward by `mergedWith` across a
  disconnect would show ERROR where the printer is simply gone, the same rule as
  the notifications ([notification-rules.md](notification-rules.md)).
- **A long error does not fit the chip.** The chip gets a short "Error" label and
  the full sentence goes to its own `error_text` in a `weight=1` strip, with the
  file row and the quip hidden. The "no printer" branch must clear `error_text`.
- **The tour's demo is never published**: the foreground path returns early while
  `tourBeaconProvider` is set.

### The scan button

The button fires `HomeWidgetLaunchIntent` with `bambuddy://widget?action=scan`;
`app.dart` listens to `HomeWidget.widgetClicked` **and** reads
`initiallyLaunchedFromHomeWidget` (cold start), then goes to `/inventory` and runs
`scanSpoolFlow`. **`_scanInFlight` is required**: a cold start delivers the URI
twice, once from each.

### Idle and offline quips

In place of the preview the widget shows a line from the `widget_idle_quips`
string array, chosen by a 15-minute time bucket (stable across refreshes, rotates
over time). The two sets (`values/` and `values-pl/`) are written independently,
not translated: humour does not carry over. The tone rule is the PEGI 16 one in
`AGENTS.md`. The offline path cannot be forced from outside
(`am broadcast APPWIDGET_UPDATE` is a protected broadcast), so it is exercised only
by a real outage.

## Overscroll stutter on Impeller

**Cause.** `StretchingOverscrollIndicator` draws through `StretchEffect`, which
uses `ImageFiltered(ImageFilter.shader)` where Impeller supports it. Each time a
stretch **starts**, the raster thread allocates an offscreen target the size of the
scrollable (the drawer: 37.2 + 4.8 + 37.2 MB; a full-width list: 58 + 7.4 + 58 MB)
and that frame takes 28-42 ms, against about 1.5 ms for a normal raster frame. The
Dart side was never the bottleneck (frame callback under 0.5 ms). Mid-list
scrolling had no slow frames and no allocations.

Measured on a Galaxy S25 Ultra (Android 16, 1440x3120 at 120 Hz), a release build,
Flutter 3.44 with Impeller on Vulkan. Not re-measured on later Flutter versions.

**Why the drawer is the worst case.** Its list overflows by only about 100 dp, so
almost every swipe is an overscroll: 4-5 hitches a second. A long list only hitches
at its ends.

**What was ruled out.** The dashboard rebuilding under the open drawer on every
status frame: the trace showed no main-thread load. Turning the stretch *down*:
frames during a running stretch take about 1.4 ms, only the start is expensive, and
that does not depend on intensity.

**Decision.** The stretch stays app-wide and is off only in the drawer list
(`ScrollConfiguration(...copyWith(overscroll: false))` around the `ListView` in
`_AppDrawer`, `dashboard_screen.dart`). `ListView` does not forward
`scrollBehavior`, only `CustomScrollView` does, hence the wrapper. Still open: the
old-style `Transform` stretch for every list, and an upstream Flutter report (none
found that matched).

**How to measure it again.** Wireless `adb` (pair first: the `_adb-tls-connect`
service refuses an unpaired host), then
`atrace -t 20 -b 96000 -a <package> gfx view input sched freq -o <file>` on the
device, pull and parse: a raster frame is `AcquireNextImageKHR` to
`QueuePresentKHR` on the `1.raster` thread, and the interesting count is the
`vkAllocateMemory` calls inside it. On this setup Dart ran on the process's main
thread (no `1.ui`), and a second `N.raster` in the process is the foreground
service's engine. Release builds emit no Flutter trace events, but the
Android/Vulkan markers are enough.
