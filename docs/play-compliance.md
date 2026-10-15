# Google Play compliance — what the app must meet before it ships

Every requirement Google publishes for this app, and what checks it. Gone through
**before every Play upload** (`just ship`, `just ship-dev`, `just play-internal`).
A Play rejection names a rule from one of the sources below, and the Wear build
was rejected under WO-V4 (2026-10-14) for a rule that had been on the Wear
quality page all along — this list exists so the next one is caught here first.

Sources (re-read them when Google announces a change, and update this file):

- [Wear OS app quality](https://developer.android.com/docs/quality-guidelines/wear-app-quality) — `WO-*`
- [Core app quality](https://developer.android.com/docs/quality-guidelines/core-app-quality) — the phone
- [Play Developer Policy Center](https://play.google.com/about/developer-content-policy/)
- [Target API level](https://developer.android.com/google/play/requirements/target-sdk)

Status: **test** — a test fails when it breaks; **device** — the on-device tests
in `patrol_test/` (run by `just test` where an emulator is installed);
**manual** — a person checks it before the upload; **open** — known not to be
met, decision pending; **n/a** — does not apply to this app.

## Before an upload

1. `just test` on a machine with the emulators (host tests, phone and watch
   device tests on Wear OS 5 and 6).
2. Compare the permissions of the built APKs with the table below:
   `aapt2 dump badging build/dist/app-{mobile,wear}-<version>.apk | grep uses-permission`
   (`aapt2` is in `~/Android/Sdk/build-tools/<newest>/`). Plugins add
   permissions the source manifest never names; a new one needs a row here and
   a reason before it ships.
3. Go through every **manual** and **open** row below.

## Permissions

`compliance_test.dart` reads this table: every permission a source manifest
declares must have a row with source `manifest`, and the watch column must say
what the watch manifest leaves in. Rows with source `plugin` come from merged
plugin manifests and are compared by hand (step 2 above).

| Permission | Source | Phone | Watch | Why |
|---|---|---|---|---|
| `INTERNET` | manifest | yes | yes | The server is the whole app. |
| `WRITE_EXTERNAL_STORAGE` | manifest | yes | no | Saving a file on Android ≤ 9 (`maxSdkVersion` 29). |
| `POST_NOTIFICATIONS` | manifest | yes | yes | Print alerts; the watch's Ongoing Activity. |
| `POST_PROMOTED_NOTIFICATIONS` | manifest | yes | no | Android 16 Live Update for the print in progress. |
| `FOREGROUND_SERVICE` | manifest | yes | yes | Background print monitor; the watch's Ongoing Activity. |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | manifest | yes | yes | The service type; declared in Play Console. |
| `CHANGE_NETWORK_STATE` | manifest | yes | yes | Qualifies the `connectedDevice` type. |
| `CHANGE_WIFI_MULTICAST_STATE` | manifest | yes | no | mDNS discovery of the server on the LAN. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | manifest | yes | no | See "Battery optimisation exemption" — **open**. |
| `CAMERA` | manifest | yes | no | QR / spool scanner, print photos. |
| `WAKE_LOCK` | plugin | yes | yes | flutter_local_notifications, WorkManager. |
| `RECEIVE_BOOT_COMPLETED` | plugin | yes | no | Rescheduling notifications after a reboot. |
| `VIBRATE` | plugin | yes | yes | Notification vibration. |
| `ACCESS_NETWORK_STATE` | plugin | yes | yes | Connectivity checks. |
| `READ_EXTERNAL_STORAGE` | plugin | yes | no | file_picker on Android ≤ 9 (`maxSdkVersion` 29). |

## Wear OS app quality

| ID | Requirement | Status | Checked by |
|---|---|---|---|
| target SDK | API 34+ for Wear | test | `compliance_test.dart` |
| 64-bit | Support 64-bit devices (from 2026-09-15) | test | `compliance_test.dart` (no ABI filter); the AAB ships `arm64-v8a` |
| WO-V1 | Follow the user's font size; nothing overlaps or is cut off | manual | widget tests use the default scale only |
| WO-V2 | Touch targets ≥ 48×48 dp where they are pressed (a curved list shrinks rows near the rim, as Wear OS's own lists do) | test + device | `compliance_wear_test.dart`, `patrol_test/wear_app_test.dart` |
| WO-V3 | Swipe to close from almost every screen | device | `patrol_test/wear_app_test.dart` (root and inner screen) |
| WO-V4 | Long-running operation → Ongoing Activity | device | `patrol_test/wear_app_test.dart` (home, back, swipe) |
| WO-V5 | Preserve state when leaving and coming back | device | `patrol_test/wear_app_test.dart` (same screen after `openApp`) |
| WO-V6 | Launcher icon and name correct | manual | |
| WO-V8 | Scroll bar while scrolling | test | `wear_scroll_view_test.dart` |
| WO-V9, V10 | Tiles | n/a | the app has no tile |
| WO-V13 | Black background | test | `compliance_wear_test.dart` |
| WO-V14 | ≥ 12 sp essential text, ≥ 10 sp the rest | **open** | `WearText.small` is 11 sp and carries essential text — see below |
| WO-V15 | 48 dp icon on black at startup, same as the launcher icon | test | `compliance_test.dart` (the splash theme) |
| WO-V16 | Fits the round face, nothing overlaps or is cut off | test | `wear_scroll_view_test.dart`, `expectOnGlass` in the wear tests |
| WO-P1 | Play's target API level | test | `compliance_test.dart` |
| WO-P2 | Installs, launches, completes tasks without crashing | device | `patrol_test/wear_app_test.dart` |
| WO-P5 | Companion app connects | manual | the phone → watch handoff |
| WO-P6 | No username or password typed on the watch | **open** | the manual setup has a login form — see below |
| WO-P3, P7, P8, P10, G4, G6, G9–G12 | Watch faces | n/a | |
| WO-G1 | Play policies | manual | the Play policy section below |
| WO-G2 | Listing: main features, no "Android Wear", localised in every app language | test | `compliance_test.dart` |
| WO-G3 | Listing icon follows the spec | manual | `docs/store-assets/play-icon-512.png` |
| WO-G5 | ≥ 1 Wear screenshot, current, 1:1, no frames or extra graphics | test + manual | `compliance_test.dart` checks 1:1; currency and content by hand |
| WO-G7 | Same package and signing key as the phone | manual | one `applicationId` in Gradle; one upload key |
| WO-G8 | Login credentials in Play Console for paid features | n/a | no paid features |

## Core app quality (phone)

Only the rows that apply; audio, video, messaging, foldable-only and WebView
asset rows are n/a.

| ID | Requirement | Status | Checked by |
|---|---|---|---|
| Target_SDK_Version | Target Play's current level (API 35+ since 2025-08-31) | test | `compliance_test.dart` |
| Compile_SDK_Version | Latest SDK | test | `compliance_test.dart` (compileSdk ≥ targetSdk) |
| Back_Button_Nav, Back_Gesture_Nav | System back, no on-screen back prompts | manual | |
| State_Preservation, App_Switcher | Survive background and return | manual | |
| Notification_Quality | Relevant, not promotional | manual | `docs/notification-rules.md` |
| Touch_Target_Size | ≥ 48 dp | manual | |
| Content_Description | Every control described | manual | `log-coverage` names controls for the log, not for accessibility |
| Runtime_Permissions | Asked when the feature is used | manual | notifications at onboarding, camera at the scanner |
| Graceful_Degradation | Works on a denied permission | manual | |
| Sensitive_Data_Storage | Secrets in internal storage | manual | `flutter_secure_storage` only (AGENTS.md "Stop and ask: security") |
| Sensitive_Data_Logging | No personal data logged | manual | `docs/diagnostics-log.md` |
| Component_Export | `android:exported` set explicitly | test | `compliance_test.dart` |
| Network_Security_Traffic | All traffic over TLS | **deliberate** | `usesCleartextTraffic="true"`: self-hosted servers on plain HTTP in a LAN (AGENTS.md) |
| Background_Service_Optimization, Power_Management | No needless long services; Doze-friendly | manual | `wakelock-and-fgs` history in `lib/main.dart`, no wake lock held |
| Play_Content_Policies, Play_Content_Rating | Content, rating | manual | copy stays within PEGI 16 (AGENTS.md) |
| Play_Device_References, Play_Misleading_Content | Screenshots honest, no other devices | manual | `docs/store-assets/screenshots/` |

## Play policy

| Policy | Status | Notes |
|---|---|---|
| Foreground service declaration | manual | Play Console declares `connectedDevice` with a video; the watch now runs one too (WO-V4) — the video may need the watch. |
| Battery optimisation exemption | **open** | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is allowed only where Doze breaks the core function and the app is one of: messaging without FCM, safety, task automation, peripheral companion keeping a device online. A print monitor fits loosely at best; Play has accepted it so far. |
| Data safety form | manual | `docs/privacy-policy.md`; the bug report sends a log only on the user's tap. |
| Account deletion | n/a | the app creates no accounts; they live on the user's own server. |
| Target API deadline | test | see above |

## Open — decisions pending

- **WO-P6** (#50): the watch's manual setup offers username + password
  (`lib/wear/screens/wear_setup_screen.dart`, `_manualSection`). Google: "must
  not ask the user to input a username or password directly on the Wear OS
  device". The phone handoff and the API key already cover sign-in.
- **WO-V14** (#52): `WearText.small` (11 sp) carries essential text — the printer
  state on the list, error lines, the setup body. Essential text needs 12 sp.
- **Battery optimisation exemption** on the phone, above (#53).
