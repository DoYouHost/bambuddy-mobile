# The Wear OS app: structure, launch, startup and text input

How the watch app is put together and the traps that are specific to it. The
round-face layout is in [wear-geometry.md](wear-geometry.md), the poll and the
Ongoing Activity in [wear-fleet-poll.md](wear-fleet-poll.md), the phone↔watch
relay in [wear-relay.md](wear-relay.md), and Google's Wear checks (`WO-*`) in
[play-compliance.md](play-compliance.md). Measurements say on what setup they were
taken.

## Scope

- **No WebSocket and no QR scanner on the watch.** Alerts reach it as the phone's
  notifications, bridged by Wear OS itself (ongoing notifications are not bridged).
  The fleet view is a poll, which runs in the background only for an Ongoing
  Activity (WO-V4), through `WearOngoingService`
  ([wear-fleet-poll.md](wear-fleet-poll.md#background)).
- **The watch is not standalone** (`com.google.android.wearable.standalone` is
  `false`): the server and its credentials arrive from the phone, because nothing
  may be typed on the watch (WO-P6). The setup screen offers to install the phone
  app when it is missing.
- **One engine per process.** Swipe-to-dismiss on the root screen is the system's
  back-to-home (`TYPE_RETURN_TO_HOME`): it finishes the activity without calling
  Flutter's `popSystemNavigator` or `onWindowDismissed` (both checked on a
  device), so an engine owned by the activity died with it. `wearEngine()` (in
  the `wear` source set) hands `MainActivity` one engine through
  `provideFlutterEngine`; the phone flavor returns null and keeps an engine per
  activity. Because that engine outlives the activity, `cleanUpFlutterEngine`
  clears every channel handler that points back at it.
- **`wear*` strings are short on purpose.** The phone's sentence does not fit one
  line on a watch (`wearClearPlate` "Clear plate" against `plateClearAction` "Mark
  plate as cleared"). Never unify the copy; word a new watch label for one line.

## Flavors and the source sets

- `mobile` and `wear` share one `applicationId` (one store listing, and the Data
  Layer delivers only to the same package). The watch manifest adds
  `uses-feature android.hardware.type.watch` as required, `minSdk` is 30, and its
  `versionCode` is the phone's plus `1_000_000_000`
  ([release.md](release.md)). Every `flutter build` and `flutter run` needs
  `--flavor`; the watch also `--target lib/wear/main_wear.dart`.
- **Both flavors compile `src/main`.** Anything in it that touches a watch-only
  dependency must not name it: the call sits behind a function that each flavor's
  source set defines, a real one in `src/wear/kotlin/` and a no-op twin in
  `src/mobile/kotlin/` (`installBrandedLaunch`, `wearEngine`, `serveWearOngoing`,
  `serveWearPhoneApp`). The library itself is a `wearImplementation` dependency
  (`core-splashscreen`, `wear-ongoing`, `wear-remote-interactions`).
- **The watch APK drops what it cannot reach**: phone-only permissions,
  components, widgets and providers are removed in `src/wear/AndroidManifest.xml`,
  and `tool/check_wear_apk.py` (CI, and a release build) checks what is left.
- **A watch-only plugin cannot be shared.** `wear_plus` was tried for the round
  shape and rejected: its `WearPlugin` references `WearableActivityController`,
  which exists only in the Wear shared library (the plugin declares it
  `compileOnly`). In the phone APK the reflective `NoClassDefFoundError` is caught
  by the embedding and plugin registration stops silently at that plugin, so every
  plugin after it alphabetically, `webview_flutter_android` among them, is never
  registered. The shape is the app's own `wear_shape` channel
  (`Configuration.isScreenRound`, `MainActivity.kt`). A per-flavor plugin set would
  need a second Flutter module.
- **`watch_connectivity` sends every message on one hard-coded `MessageClient`
  path** (`watch_connectivity`, taken from the plugin's own channel name), so
  request and response are told apart by a `kind` field
  ([wear-relay.md](wear-relay.md)). Nested maps off its `EventChannel` come back as
  `Map<Object?, Object?>`; `deepSanitize` normalises them.

### Rotation lock

`android:screenOrientation="nosensor"` on `.MainActivity` in the wear manifest.
`portrait` is not enough on a square screen: the display kept rotating 90 degrees
though `requestedOrientation` was portrait. And no
`SystemChrome.setPreferredOrientations`: it overrides the manifest at runtime. A
watch **on its charger always rotates** (dock mode ignores every lock), so check
off the charger, with `dumpsys window | grep mCurrentRotation`.

### Release builds and the Dart snapshot

An incremental release build has packed a stale Dart snapshot (same APK size, old
UI). The `just` build recipes clean `build/app` and `.dart_tool/flutter_build`
first (`_clean-artifacts`); for a manual build do that yourself and check with
`grep -a "<a string you just added>" lib/*/libapp.so` in the unpacked APK. This
is also why a release build is the only one that can answer whether code survived
tree shaking.

### Devices and emulators

- **A real Galaxy Watch 5 (SM-R910) reported `armeabi-v7a` only, no arm64**
  (`adb shell getprop ro.product.cpu.abilist`). A build for it must contain
  `armeabi-v7a`: `just build-wear` passes no `--target-platform`, which is right;
  `--target-platform android-arm64` alone installs nowhere on that watch (CI uses it
  for its debug builds only because it never installs them).
- A watch's screen sleeps within seconds: send `KEYCODE_WAKEUP` right before
  `screencap`.
- AVDs: `wear_round` (Wear OS 5, API 34, x86_64, 384x384, 512 MB) and
  `wear6_round` (Wear OS 6.1, API 36.1, 454x454). `just test` runs
  `patrol_test/wear_app_test.dart` on both (`_test-wear` in the `justfile`, which
  also turns off ambient mode and sleep for the run). Wear system images ship no
  Play Store (`PlayStore.enabled=no`). The API 30 image has its own limits:
  [dev-environment.md](dev-environment.md).

## Branded launch (WO-V15)

Play rejected a watch build for "Missing app icon in splash screen" (WO-V15: the
icon at 48x48 dp on black during startup). The build already carried a launcher
theme of its own, with a black `windowBackground` and `@mipmap/ic_launcher` at
48 dp: **a custom launch theme did not satisfy the reviewer.** Two causes together:

1. `@mipmap/ic_launcher` is an adaptive icon, and drawn in a 48 dp box it is
   masked to two thirds: a ~32 dp circle around a ~22 dp glyph, nearly black on
   black.
2. Wear OS 3 (API 30) has no system splash at all, and Google's Wear splash guide
   says to use `androidx.core:core-splashscreen` rather than a theme of one's own.

What ships (`android/app/src/wear/`):

- `WearLaunchTheme` extends `Theme.SplashScreen` with
  `windowSplashScreenBackground` (black), `windowSplashScreenAnimatedIcon` and
  `postSplashScreenTheme` (`WearNormalTheme`). No `android:` prefix: the library
  backports them and maps them onto the platform attributes from API 31.
- `installSplashScreen()` in `BrandedLaunch.kt`, called **before**
  `super.onCreate`, because `FlutterActivity` swaps the window to its `NormalTheme`
  in its own `onCreate`. `WearNormalTheme` is also what the manifest names as the
  `NormalTheme`, so the two agree.
- The icon is `wear_splash_icon.xml`, composed by hand: the launcher's background
  colour as an oval at the full 48 dp, with `ic_launcher_foreground` on top at
  **40 dp**. The launcher's own 16% inset exists only to cancel the adaptive mask,
  which this drawable does not have; the foreground layer is drawn edge to edge, so
  at 48 dp the filament strand nearly touched the rim.
- `compliance_test.dart` checks the theme's attributes.

Checked on both paths: on API 34 (platform splash) the circle sat on black until
the first frame, about 2.3 s on a cold start; on API 30 (the library's backport,
the `wear30x86` AVD) a cold-start screenshot measured pixel by pixel put the icon's
bounding box at 96x96 px at density 320, which is exactly 48.0 dp, centred, with
pure `#000000` at the edges. (That check was before the foreground was reduced to
40 dp inside the same 48 dp circle; the circle's size is unchanged.)

## Cold start

Measured on the `wear_round` AVD (x86_64, 4 cores, 512 MB, API 34, 384x384) with a
**debug** build: seven runs of `am force-stop` then `am start -W`, median
`TotalTime`.

| | median | range |
|---|---|---|
| baseline | 1342 ms | 1297-1402 |
| without `MlKitInitProvider`, `PrintFileProvider`, `ShareFileProvider` | 1259 ms | 1208-1320 |

The 83 ms (6.2%) is an effect, not noise: the ranges barely overlap. The whole
window before `FlutterJNI: Beginning load of flutter` is about 199 ms including
ART's bootstrap, so the pre-Flutter phase was never the main cost. Those providers
are removed in the watch manifest (it carries the same numbers); the Gradle
dependencies stay, because the phone flavor compiles the same sources.

**To A/B a component without rebuilding**: `pm disable-user` is refused
(`SecurityException: Shell cannot change component state`), but after `adb root`
`pm disable <package>/<component>` works. Undo with `pm enable` and `adb unroot`;
that leaves the component "explicitly enabled" rather than "default", with
identical behaviour.

**What this emulator cannot measure, which matters more than what it can:**

- **The wait for data.** The AVD's profile is `http://demo`, which runs in-process
  (`HybridWearTransport.restOnly`) with no phone paired, so the relay (4 s
  timeout, 15 s after the phone's ack) never starts. That wait, not the engine, is
  what the spinner is made of.
- **Dart-phase timing.** A debug build is JIT, so `main()`'s time is inflated and
  does not transfer.
- **Watch silicon.** The AVD runs on desktop cores; any multiplier to a real
  watch is a guess.

A release APK cannot replace the debug one on the AVD: the signatures differ,
`adb install -r` refuses, and a reinstall clears the AVD's profile.

## Text input

The watch has no text field today (WO-P6: the phone hands over the server, never a
typed value); an earlier native text-input path was removed with it. What was
learned while debugging it applies to any field that is added:

- **`MediaQuery.viewInsets.bottom` stays 0 on Wear even while the keyboard is up.**
  The watch keyboard is its own fullscreen window and the app is never told. So
  `viewInsets` is useless as a "did the keyboard open" probe (a sweep of eight
  `TextInputType`s all read as none while the system reported `onShown`), and
  `windowSoftInputMode="adjustResize"` does nothing there: no layout work can lift
  a field clear of the keyboard.
- **`ImeTracker` is the instrument that works** (Android 14+):
  `adb logcat -v time -s ImeTracker:V InputMethodManager:V` traces each show request
  from `onRequestShow` to `onShown` or `onFailed at PHASE_*`, which is the only way
  to tell "the keyboard refused" from "it is up but invisible".
- **The AVD cannot settle Gboard-for-Wear questions.** Its image has no Play Store,
  so the keyboard is the image's own `LatinIME`, which raises a keyboard for every
  input type, `url` and `number` included, both of which were dead on a real Pixel
  Watch 3. A clean run on the emulator does not clear a keyboard bug reported from a
  real watch.
- Upstream: [flutter/flutter#24001](https://github.com/flutter/flutter/issues/24001)
  (open since 2018): the engine puts `IME_FLAG_NO_FULLSCREEN` in every
  `EditorInfo` with no Dart-side opt-out.
