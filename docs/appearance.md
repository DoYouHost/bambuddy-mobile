# Appearance: accent colour, Material You, light and dark

What the phone app and the watch let a user change about their look, and the
reasons behind each piece. The home-screen widgets do not follow the choice yet
(see the end).

## The three accent sources

`AccentSource` (`lib/core/settings/appearance_prefs.dart`) is stored as one JSON
object under the SharedPreferences key `appearance_prefs`, beside the theme mode.
Missing or unreadable fields read as the look the app had before the choice
existed — the green accent, following the system's light/dark — so no migration is
needed and an older install upgrades without a visible change.

- **Bambuddy green** is `bambuddyBrand` (`lib/core/theme/dash_theme.dart`), a
  hand-tuned brand.
- **Presets** (`accentPresets` in `lib/core/theme/app_brand.dart`) are a seed and a
  Material `DynamicSchemeVariant`, turned into a brand by
  `DashBrand.fromSchemes(ColorScheme.fromSeed(...))`. `graphite` uses `monochrome`:
  `tonalSpot` lifts any seed to a chroma of about 36, so a grey seed would come out
  coloured.
- **System** is the Android 12+ wallpaper palette from `dynamic_color`, read in
  `main()` before `runApp` so the first frame already wears it, and again on every
  resume. Where there is no palette (Android 11 and older, or a device without
  one) `resolveBrand` falls back to the green brand, and the settings list hides
  "System" unless it is the stored choice.

On the API 35 emulator a wallpaper change recreates the activity, and the phone
flavor keeps one engine per activity (`MainActivity.provideFlutterEngine`), so
`main()` runs again and reads the new palette. The resume read is the fallback for
an OEM build that delivers the change without recreating the activity — not
measured on one. `DynamicColorBuilder` is not used: wrapping `MaterialApp.router`
in it only for "System" would change the tree above the router and drop the user
on the dashboard when the accent changes, and its first frame is null, so every
cold start would flash green.

## The watch

The watch's colours are chosen on the phone, under App settings → Watch: a watch
screen is a poor place for settings. Two switches that exclude each other —
"Theme from the watch face" and "Theme from the phone" (the default) — and with
both off a preset picked from the phone's list without "System".
`WatchAppearance` (`watch_appearance`) holds the choice, and `watchTheme` turns
it into what is sent: an accent and a `watchFace` flag.

- **The accent** goes with the server config (`WatchConfigCodec`, optional
  `accentSeed` and `accentVariant`), on launch and whenever the theme or the
  profile changes. `watchAccent` sends nothing for the green brand and for a
  "System" without a palette, and for "System" sends the palette's primary, the
  seed `dynamic_color` builds the phone scheme from. With the face switch on the
  phone's accent is still sent, for a watch whose face gives none. The watch takes
  both from every push, also one for another server that it only offers: the
  colour is the phone's to set whichever server is chosen. It stores them
  (`wear_phone_accent`, `wear_face_colours`) so the first frame already wears
  them. A watch or a phone without these keys keeps the green both always drew.
- **The face**, Google's own source on Wear OS 6 (Wear Material 3
  `dynamicColorScheme`). `WatchFaceColours.kt` reads the roles the way that
  function does: Android 15 or later, and only with `Settings.Global`
  `dynamic_color_theme_enabled` set — without it the system colour resources still
  answer, with defaults unrelated to the face, which is also why the watch does
  not use `dynamic_color`. The phone cannot tell whether the face has colours, so
  the switch is always offered and the watch falls back to the accent.

The face is read before `runApp` and on every resume through the phone's
`systemSchemesProvider` with the reader overridden in `main_wear.dart`. That
re-read keeps the last palette when a read comes back empty (a failed read must
not drop a chosen "System" on the phone), so on the watch switching dynamic
theming off while the app is open is seen only at the next start. The watch draws
on black whatever the source (WO-V13), and roles come from Wear Material 3's
tones, not the phone's (`wearSeedScheme`).

## Why the grounds belong to the brand

A brand carries its own `DashSurfaces` (dash_ui), so "full Material You" means the
backdrop, cards, sheets and scaffold follow the accent too. `fromSchemes` takes them
from the schemes' `surfaceContainer*` roles and never from `surface`: dynamic_color
takes `surface` from the device's neutral palette but the containers from
`fromSeed(primary)`, and mixing the two puts two palettes in one gradient. The dark
grounds stay at tone 10 or below because the muted text inks are fixed in
`DashTokens` and no brand can nudge them.

The accent ink is the HCT tone `Contrast.darker` gives for 4.5:1 on the darkest
surface it can sit on — including its own accent wash at 18 %, the strongest one
dash_ui paints (a selected chip). `dashContrastAudit` measures hue drift in HCT,
Material's own hue, and skips it under chroma 5, MCU's cutoff for a hue worth
theming with.

## Not themed on purpose

- QR scanner chrome (`_kScanTokens`): a camera view, dark whatever the theme.
- The G-code viewer's ground: it mirrors the `--bg` of `assets/gcode/viewer.html`.
- Data colours: heater lines, spool colours, the plate preview's backdrop.
- Launcher icon (has its own `<monochrome>` layer) and notifications.

## Checks

- `test/core/theme/` — every accent passes the audit, "System" without a palette
  is the green brand, graphite is an exact grey, a resume re-reads the palette.
- `test/a11y/rendered_guidelines_test.dart` — Flutter's contrast and touch-target
  guidelines on rendered pixels under three accents × light/dark. The two nodes the
  contrast guideline misreads are excluded with the measurements in the test. The
  rest of the app is covered step by step (local plan
  `docs/plans/a11y-guideline-tests.md`).

## Later stages

- **Widgets:** the Dart publisher writes the resolved palette through `home_widget`
  and Kotlin reads it, with `R.color.*` as the fallback. The FGS isolate publishes
  too, so it must read `appearance_prefs` in its own `onStart`.
