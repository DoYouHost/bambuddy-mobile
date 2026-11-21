# Dependency upgrades that need more than a version bump

Most of `pubspec.yaml` moves with `flutter pub upgrade --major-versions` and a
green CI run. The entries below do not: each one is held down by something a
bump alone does not solve. This file says what, and what unblocks it; the last
section is about the shared `app-shared` packages and how a release of them reaches
this repo.

## flutter_secure_storage 11 — pending, and it must not be rushed

**State:** the app is on **10.3.4** (since 2026-09-17), one major behind.

**Why not 11 yet.** Version 11 drops the ciphers that version 9 wrote with. An
install that goes from a build on 9 straight to a build on 11 cannot read its
own saved credentials — no migration runs, the entries are simply unreadable.
Version 10 is the bridge: it re-encrypts v9 entries on the first read
([lib/core/auth/credentials_store.dart](../lib/core/auth/credentials_store.dart)
configures that migration with `resetOnError: false` and
`migrateWithBackup: true`).

**So 11 may only ship in a release that follows one which ran 10 long enough to
migrate the installed base.** The release that first carried 10 is the one on
Play as of 2026-09-17; the longer it sits there before 11 goes out, the fewer
users skip the bridge. Whoever takes the jump decides how long is long enough —
it is a judgement about the update habits of the installed base, not a number
this file can fix.

Users who skip the bridge anyway are not silently broken: the dashboard raises
the `SignInReason.credentialsMissing` dialog and sends them to sign in again.
That is a lost session, not lost data, and it is the failure mode to weigh when
picking the moment.

**What else is waiting on it — the win32 knot.** secure_storage 10 still pins
`win32 ^5`; only 11 moves to `^6`. `share_plus` 13, `package_info_plus` >=10.1
and `device_info_plus` 13 all want `win32 ^6`, so pub resolves none of them
while secure_storage sits at 10. They move as one block, after 11. (Windows is
not a target of this app — the constraint still binds, because pub resolves the
whole dependency graph regardless of platform.)

## file_picker stops at 10

11 replaced `FilePicker.platform.x()` with static methods and 13 dropped
`withData`. Both are call-site rewrites, in
[lib/features/common/device_files.dart](../lib/features/common/device_files.dart) and in
`app_report_ui` over in app-shared — so the bump is two repos, not one.

## Built-in Kotlin waits on five plugins

Every build warns that plugins "apply Kotlin Gradle Plugin (KGP)" and that a
future Flutter will refuse them. The app itself is already migrated (no
`kotlin-android`, a `kotlin { compilerOptions }` block); what is left is
`android.builtInKotlin=false` in `android/gradle.properties`. Most plugins on the
list — patrol, home_widget, mobile_scanner, flutter_file_dialog — apply KGP only
*because* that flag is false, and stop on their own once it is true.

Flipping it today fails the build: AGP 9 refuses `kotlin-android` outright, and
five plugins still apply it unconditionally. `device_info_plus`,
`package_info_plus` and `share_plus` are migrated in their latest majors, which
wait on the win32 knot above; `file_picker` is migrated in 13, which waits on
its own rewrite below; `nsd_android` 2.2.0 is not migrated at all
(sebastianhaberey/nsd#88). Once all five move, set the flag to true.

## flutter_riverpod is at 3

Migrated from 2.6.1 to 3.4.3 together with `app_report_ui` in app-shared, the only
shared package that depends on it. What the migration changed, so a later bump does not
rediscover it:

- `AutoDispose*` and `Family*` notifier bases are gone: one `AsyncNotifier` / `Notifier`,
  `.autoDispose` stays a modifier on the provider, a family's argument comes through the
  notifier's constructor (`GroupDetailNotifier(this.arg)`), not through `build`.
- `valueOrNull` is `value`; `Override` and `ProviderListenable` live in
  `package:flutter_riverpod/misc.dart`, `StateProvider` in `legacy.dart`.
- **Automatic retry** (ten attempts, growing delay, for any `Exception`) would hold every
  failed read on a spinner; `neverRetry` in `lib/providers.dart` is passed to every root
  scope and container. A new root must pass it too.
- `copyWithPrevious` is internal; see [riverpod-traps.md](riverpod-traps.md) §5.
- Out-of-view listeners are paused (they follow `TickerMode`): a provider watched only
  by a screen that is not on top stops until it is back.
- A `Ref` used after an `await` in a provider that was disposed meanwhile throws
  (`ref.mounted` guards it).

## Shared packages (app-shared)

`DoYouHost.app-shared` holds the packages this app shares with lubelogger-mobile
(the list is under "What else the shared repo ships"). **Read this section before
touching `pubspec.yaml` refs, `lib/core/diagnostics/` or `report_config.dart`.**

### The six seams the app must fill

1. `LogSource` / `LogStream` are the **union** of both apps, not a menu; enums
   because three places switch exhaustively. File suffixes are the ones already on
   disk — `''`, `-fgs`, `-act`, `-worker`; renaming one (e.g. to `-wrk`) would
   change file names mid-recording.
2. `LogHeader` has `extra`. `flavor` / `device` / `auth` are no longer fields and
   travel there **flat, as top-level keys**, so `v` stays 1 and the relay needs no
   schema registration. `log_wire_format_test.dart` guards it.
3. Ports: `DiagnosticsSessionStore` (save/load the session id), the `redactor`
   factory, `sessionDuration` / `sessionBytes`. **The limits stay in the app**
   (`report_config.dart`).
4. `DiagnosticSessionListener` instead of the core calling `WsProbe` — lubelogger
   has an `ImageProbe` in the same place, so it is a seam, not a quirk. **It must
   also be passed to `startBackground`**, or the FGS isolate loses the tail of the
   socket history.
5. `HttpProbeConfig` — sampled/never routes, limits, `pathOf`, `fieldsOf`,
   `redactSamples`. By default it **samples nothing**.
6. `SemanticsIdDecomposer` = `({String id, Map fields}) Function(String)` — it must
   decompose, not only add a field, or `inventory.spool@PETG` stays as the id.

### Traps that cost time

- **`scrubSample` measures a long unrecognised string as `<str:500>` before any
  sample ceiling applies.** A record exceeds the limit by being *wide*, not long: a
  trimming test needs many short values.
- **`part of` files have no imports** — `printer_card_details` and
  `inventory_form/tiles/bulk_edit` take their imports from the library file.
- `LogRedactor` requires `ourKeys` on purpose; `LogStore` defaults to
  `LogRedactor(ourKeys: {})`, which scrubs *more*, not less.
- **The `app_report_client` ref in this repo MUST equal the one `app_diagnostics`
  names inside itself — which is one tag OLDER.** Two sources for one package is a
  resolution error (`app_diagnostics from git is forbidden`), and an inner ref can
  never point at the tag that contains it: the pubspec is written before the tag.
  The current refs are in `pubspec.yaml`, each with a comment on which must match
  which. **Does NOT help:** replacing the inner dependency with
  `path: ../app_report_client`. Pub resolves it to the same repo but pins a
  **commit SHA** while the consumer names a **tag** — two different refs again. A
  path works only for a consumer that declares *solely* `app_diagnostics`
  (`app_report_client` then arrives transitively and is importable), but this app
  imports it directly and would get `depend_on_referenced_packages`.

### What stays in this repo

`report_config.dart` (redactor dictionary, limits, probe config, decomposer),
`ws_probe`, `notif_probe`, `auth_probe`, `filament_material`, `log_tag_material.dart`
(the filament wrapper), `loadSessionFacts` / `sessionSecrets`, `startActionRecording`
(was `DiagnosticRecorder.startAction`) and all of `features/bug_report/`. Tests split
the same way: those that ask about *this* app stay — the `Endpoints` guard in
`log_path_test`, four filament tests, the router contract, the `startAction` group,
all of `http_probe_test`.

Further extraction candidates are listed in `docs/candidates.md` of the shared repo.

**Since v0.14.0 every UI package is on Google's standalone `material_ui`**, and
  so is this app (`dart fix --apply --code=migrate_design_widgets`). Material's
  localizations come from `material_ui`'s `GlobalMaterialLocalizations.delegates`,
  never from a generated `*.localizationsDelegates`: `gen-l10n` still fills that
  list from `flutter_localizations`, whose in-framework `MaterialLocalizations` no
  `material_ui` widget finds — "No MaterialLocalizations found" at runtime, nothing
  at analysis.

### What else the shared repo ships

`app_guards` (source-scan guards and bundled scripts run as
`dart run app_guards:<tool>`, with per-app TOML configs in `tool/`:
`l10n_language.toml`, `log_coverage.toml`, `play.toml`), `app_test_kit` (the generic
half of `test/helpers.dart`, re-exported there), and `dash_kit` / `dash_ui` /
`app_util` (widgets and helpers formerly in this repo). A brand can be generated
with `DashBrand.fromSchemes` from a Material `ColorScheme` pair; how the app uses it
is in [appearance.md](appearance.md).

### Verifying against unreleased packages

**Never add `pubspec_overrides.yaml` to the apps.** Verify against unreleased
packages on a scratch copy and release a normal tag at the end. A git-excluded
`pubspec_overrides.yaml` swaps packages for local paths and `pub get` does it
silently — move it aside before verifying the way CI counts.

### Releasing the shared packages

One commit in the shared repo where every `ref:` in `packages/*/pubspec.yaml` already
names the NEW tag, plus a `version:` bump of the changed package. The tag goes on that
commit (tags are annotated and signed, so `git tag -m`), master and the tag are
pushed, then every app-shared ref in this repo's `pubspec.yaml` moves to the same tag
(`app_report_client` included: since v0.14.7 `app_diagnostics` names its own tag for it, not `v0.2.0`). A push to master bypasses the PR
rule, so do it only when the maintainer explicitly says so.
