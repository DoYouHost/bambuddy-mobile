# Appearance: accent colour, Material You, light and dark

What the phone app lets a user change about its look, and the reasons behind each
piece. The watch and the home-screen widgets do not follow the choice yet (see the
end).

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

- **Watch:** `WatchConfigCodec` gets an optional `accentSeed`; the phone pushes it
  on profile and appearance change, and `wearTheme(seed)` replaces the fixed green.
  A missing key means green, so old and new phone/watch pairs keep working.
- **Widgets:** the Dart publisher writes the resolved palette through `home_widget`
  and Kotlin reads it, with `R.color.*` as the fallback. The FGS isolate publishes
  too, so it must read `appearance_prefs` in its own `onStart`.
