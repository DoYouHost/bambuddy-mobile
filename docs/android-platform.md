# Android platform notes (phone)

Things that live in `android/` or depend on the Android version, device or
renderer, and that the code alone does not explain: the Android 16 Live Update,
the camera stream's ANR history, the home-screen widgets, the overscroll
stutter, a server behind a private CA and one behind mutual TLS. The watch's own platform notes are in [wear-os.md](wear-os.md). Where a
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

## A server behind a private CA (#62)

**Why a CA installed on the phone does not help.** Every request goes through
`dart:io`: Dio, the WebSocket, the MJPEG stream and `Image.network`. `dart:io`
keeps its own copy of the system roots and never reads the Android user store. It
also ignores `network_security_config`. A reverse proxy signed by the user's own
root CA therefore fails with `CERTIFICATE_VERIFY_FAILED` even when Chrome on the
same phone trusts it.

**What we do instead.** Google's guidance for an unknown CA is to trust that one
issuer on top of the system roots (`base-config` with the extra CA plus `system`).
Trusting every user-installed CA is shown only under `debug-overrides`. We follow
the first, at run time, because the CA differs per user. The setup screen imports
one file, PEM or DER (`lib/features/setup/certificate_rows.dart`). `CustomCa.parse`
keeps only its `CERTIFICATE` blocks. The import button sends a file with a private key
to the client certificate instead (below), so a key never reaches the CA slot. The certificate lives in SharedPreferences under `custom_ca`; it is public,
not a secret.

**Where it applies.** `HttpOverrides.global` is per isolate, so each isolate that
talks to the server calls `useTls(ca, cert)` (`lib/core/api/tls_overrides.dart`) before
its first request:

- **UI isolate:** `main()`.
- **Foreground service, notification-button and watch-relay isolates:**
  `buildBackgroundApiClient`. Dio creates its `HttpClient` lazily, so trust set
  there is in time.
- **The watch:** the relay through the phone needs nothing of its own. For the
  direct-REST fallback the phone sends its CA with the server config
  (`WatchConfigCodec`, `caName` and `caPem`), again whenever it changes, and
  `PendingWatchConfig.adopt` stores it; a config without one clears the watch's.
  `main_wear.dart` trusts the stored CA at start. The watch cannot import one
  itself.

**Traps.**

- **A client keeps the trust it was created with.** Changing the CA through
  `tlsIdentityProvider` invalidates `bareDioProvider`, so a retry after importing
  gets a fresh client. Dio does not watch it: that would make every Dio depend on
  preferences. The
  `Image.network` client is one per isolate, so a CA changed while the app runs
  reaches images only after a restart.
- **Dio's error type.** Dio reports an untrusted certificate as a connection
  error. `mapDioException` turns a `HandshakeException` carrying
  `CERTIFICATE_VERIFY_FAILED` into a `NetworkException` with
  `AppErrorCode.badCertificate`. Other handshake failures,
  such as plain http on an https port, stay connection errors.
- **The CA is trusted for every host the app contacts,** as `base-config` would
  be, not only the server. A custom anchor also skips Certificate Transparency.
- **Never add a `badCertificateCallback` that returns true.**

`test/core/api/custom_ca_test.dart` proves the trust against a real TLS server on
127.0.0.1 (fixtures in `test/fixtures/tls/`; the CA's key was discarded).

## A server behind mutual TLS (#65)

A reverse proxy can ask the client for a certificate during the handshake. Android's
KeyChain does not help, for the reason a user CA does not: every request goes through
`dart:io`, which needs the key's bytes, and a KeyChain key is usually held in hardware
and cannot be exported. Using it would mean a native HTTP stack under Dio, the socket,
the camera stream and `Image.network`. So the user imports a file instead: a `.p12` or
`.pfx`, or a PEM holding the certificate and its key
(`lib/features/setup/certificate_rows.dart`, on the setup screen and in app settings).
`ClientCert.parse` loads it into a throwaway `SecurityContext`. A wrong password is told
apart by BoringSSL's `INCORRECT_PASSWORD` in a `.p12`. An encrypted PEM key fails as
"no key found" whatever the password, so there the `ENCRYPTED PRIVATE KEY` or
`Proc-Type: 4,ENCRYPTED` header is what says a password is needed. The dialog asks only
when the file needs one.

**One import button for both.** The file decides: a key or a password makes it the
client certificate, a bare certificate the CA. The client certificate is tried first,
because `CustomCa.parse` takes the certificates out of any PEM, a bundle with its key
included. A file that asked for a password or carries a PEM private key never falls
through to the CA slot: one that fails (a key that does not match, a `.p12` with no key)
says so as a client certificate and leaves the installed CA alone. A certificate PEM
without its key does land as a CA; the proxy then refuses the app with the
client-certificate message, which names the problem. Each
kind has one slot, so the button stays and a new import replaces the old one.

**Storage.** The file and its password are a secret, so they go to
`flutter_secure_storage` under a namespace of their own (`client_cert`). That namespace
keeps them out of the `deleteAll` a sign-out runs: the certificate belongs to the proxy,
not to the account, as the CA does. The flag `has_client_cert` in preferences lets
`loadClientCert` skip secure storage when there is no certificate. Opening the namespace
creates its Keystore key, and every install would otherwise pay for that before its
first frame.

**Where it applies.** It applies wherever the CA does, through the same call: `useTls`
takes both and builds the one `SecurityContext` that carries them. The traps above hold
as written: a client keeps the identity it was made with, and a change invalidates
`bareDioProvider`. The certificate is shown to any host that asks for one, not only the
server.

**The watch** gets the certificate with the rest of its config, beside the password it
already receives (`certName`, `certData`, `certPassword`). It re-parses the certificate
and stores it in its own secure storage. A CA and a certificate both near their 64 KB
caps would overflow the 100 KB Data Layer item; real ones are a few KB, and this is not
checked.

**A refusal says so.** `mapDioException` turns a proxy's refusal into
`AppErrorCode.clientCertRefused` ("The server needs a valid client certificate"). In
TLS that is the alert the proxy sends, received as `…ALERT_CERTIFICATE_REQUIRED` (TLS
1.3, none sent) or `…ALERT_UNKNOWN_CA` (one it does not trust), both recorded against
`openssl s_server -Verify`. Over HTTP it is nginx's 400 page for `ssl_verify_client on`.
TLS 1.2 without a certificate gives only `HANDSHAKE_FAILURE`, which a cipher mismatch
gives as well, so it stays a connection error. A proxy that answers 403 by its own rule
cannot be told apart from bambuddy's 403.

**One state for both** (`tlsIdentityProvider`, a `TlsIdentity` record), because one
context carries both. `setCa`, `setCert` and `setBoth` each make one change: one
`useTls`, one invalidate, one push to the watch. "Remove all" and a watch adopting both
are a single change, not two rebuilds of every client. `customCaProvider` and
`clientCertProvider` are read-only views of it.

**Writes are queued** (`SerialQueue`), and each computes its target from the state as
it is when its turn comes, skipping what is unchanged. Two calls side by side could
otherwise finish in either order. Secure storage is written first, as the write most
likely to throw, and before its flag both ways. A write that throws leaves the key, the
flag, the CA and the state as they were, so there is never a key on disk behind a flag
that says there is none.

**Removing** either one asks first. App settings show both under "Certificates", with
"Remove all" once there are two.

`test/core/api/client_cert_test.dart` proves the handshake against a server on 127.0.0.1
that asks for a certificate. `dart:io` cannot make one mandatory, so the server answers
with the subject it received.
