# Foreground service, wakelocks and Android vitals

Why the background monitor is a `connectedDevice` foreground service that holds no
wakelock, and what to re-check when the target SDK moves. **Read it before
touching the FGS type, `allowWakeLock`, `background_monitor.dart` or the manifest's
permissions.**

## The two limits that both applied

1. **A wakelock held ≥ 2 h cumulative per day marks a session as bad**; 5% bad
   sessions over 28 days is Google's threshold. A lock held during a foreground
   service counts exactly like one held in the background — the FGS is no loophole.
   Only wakelocks taken through the audio and location APIs and *user-initiated*
   JobScheduler jobs (UIDT) are exempt; plain WorkManager is not, but it holds the
   lock for seconds.
2. **A `dataSync` FGS gets 6 h per day** from targetSdk 35. `flutter.targetSdkVersion`
   is 36 on Flutter 3.44, so this was already in force: background monitoring died
   after 6 h unnoticed. The counter resets **only** when the app comes to the
   foreground. Types **without** a timeout: connectedDevice, specialUse, location,
   mediaPlayback, health, camera, microphone, phoneCall, mediaProjection,
   remoteMessaging.

Android vitals showed 6.38% of sessions with "excessive partial wakelocks" against
the 5% threshold. Only a minority was hit because **Doze ignores wakelocks**: the
lock kept the CPU awake only where Doze does not run — users who had exempted the app
from battery optimisation themselves (the app does not request the exemption, see
[play-compliance.md](play-compliance.md)) and phones on a charger. The lock worked
exactly for the users who were penalised for it and did nothing for the rest.

## What the app does

- `allowWakeLock: false` in `lib/main.dart`. The plugin took `acquire()` **without a
  timeout**, `setReferenceCounted(false)`, released only in `stopForegroundService()`.
- FGS type **`connectedDevice`** (manifest and `serviceTypes` in
  `background_monitor.dart` — they must agree, or `startForeground` throws).
  Permissions: `FOREGROUND_SERVICE_CONNECTED_DEVICE` plus `CHANGE_NETWORK_STATE`
  (the type needs one qualifying permission, and it accepts a network connection,
  not only BT/USB).
- `test/core/notifications/foreground_service_declaration_test.dart` pins the
  manifest↔Dart pair, the permissions, the stripping on wear and that nobody goes
  back to `allowWakeLock: true`.
- The foreground-service type declared in Play Console must say `connectedDevice`
  ([play-compliance.md](play-compliance.md)).

## Why dropping the lock is safe

The path from a WebSocket frame to `show()` is **entirely synchronous**
(`print_monitor.dart` has no `await`), and the CPU does not sleep while it has a
runnable thread. An incoming packet wakes the device by itself — the radio raises a
kernel wakeup source — and Google states that listening on a socket needs no app
wakelock.

The safety net: **the server sends a full snapshot of every printer's status on each
WebSocket connect** (`api/routes/websocket.py`, "Send initial status of all
printers"). After a CPU suspend the watchdog (`idleTimeout`, 60 s) forces a
reconnect and the snapshot replays the missed edge. What is lost is **latency**, not
the **event**.

## Verified on an emulator (Android 15 / API 35)

Demo with an active print, `mobile` flavor, app minimised:

- `dumpsys activity services` → `isForeground=true types=0x00000010`
  (`FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE`, 16): the type is enforced, no exception.
- `dumpsys power` → **`Wake Locks: size=0`** right after start and after 40 s. The
  only locks touching the package are the system's
  `NotificationManagerService:post:<pkg>` (uid 1000, ~200 ms per notification).
- The isolate lives: the FGS notification progressed 42% → 44% in the background,
  from its own WebSocket.
- `Background started FGS: Allowed`, reason `ACTIVITY_VISIBILITY_GRACE_PERIOD`: a
  start from `onPause` fits the grace period and **does not depend on the battery
  optimisation exemption**. The exemption matters only for restarting the service
  from an alarm. Returning to the foreground stops the service correctly.

Not covered: real Doze and socket expiry over hours, a hard process kill by an OEM
killer, real-device policies.

## Dead end: the FGS isolate has no platform channels from `MainActivity`

Those channels are attached to the activity's engine (`configureFlutterEngine`),
while the service creates its own `FlutterEngine(context)` in which
`GeneratedPluginRegistrant` registers **only pub plugins**. So `battery`, `clock`
and `wear_input` are unavailable there. If the isolate ever needs native code of our
own, there are two ways: a local plugin package in `packages/` (registers itself in
every engine), or `FlutterForegroundTaskPlugin.addTaskLifecycleListener` from
`onEngineCreate` — the latter needs an `Application` class, because after the service
is restarted by `RestartReceiver` `MainActivity` may never have started.

## Trap ahead: `ACCESS_LOCAL_NETWORK` (Android 17)

Android 17 gates local-network access behind the runtime permission
`ACCESS_LOCAL_NETWORK` (NEARBY_DEVICES group). Opt-in on Android 16, **mandatory from
targetSdk 37**: without it a TCP connection to a LAN address **times out** and UDP
fails with EPERM, by IP and by host name alike (DNS on port 53 is exempt).

The app targets 36, so nothing hurts today. **When a Flutter upgrade raises the
default target to 37, the permission must be declared and requested at runtime**, or
the app stops working for everyone with a server on the LAN (most users). Users
connecting through a public domain are unaffected. A new permission is a maintainer
decision — see "Stop and ask: security" in AGENTS.md.

Related: [notification-delivery.md](notification-delivery.md),
[server-contract-traps.md](server-contract-traps.md).
