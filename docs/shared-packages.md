# Shared packages (`DoYouHost.app-shared`)

What lives in the shared repository, the seams `app_diagnostics` expects this app
to fill, and how a release of the shared packages reaches this repo's `pubspec.yaml`.
**Read it before touching `pubspec.yaml` refs, `lib/core/diagnostics/` or
`report_config.dart`.**

## Why diagnostics were extracted

The diagnostic-log files in this app and in lubelogger-mobile were 69–91% identical,
and the differences were mostly comment prose. Each app had learned something the
other lacked: lubelogger had `logSurface` / `LogSurface` and
`LogSummary.sessionFacts`; bambuddy had `loggablePath`, `startAction` and `WsProbe`.
`app_diagnostics` holds the core — session, record, disk mirror, isolate merge,
review summary, tap/route/http/error/lifecycle probes — next to `app_report_client`.

## The six seams the app must fill

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

## Traps that cost time

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

## What stays in this repo

`report_config.dart` (redactor dictionary, limits, probe config, decomposer),
`ws_probe`, `notif_probe`, `auth_probe`, `filament_material`, `log_tag_material.dart`
(the filament wrapper), `loadSessionFacts` / `sessionSecrets`, `startActionRecording`
(was `DiagnosticRecorder.startAction`) and all of `features/bug_report/`. Tests split
the same way: those that ask about *this* app stay — the `Endpoints` guard in
`log_path_test`, four filament tests, the router contract, the `startAction` group,
all of `http_probe_test`.

Other extraction candidates: `docs/candidates.md` in the shared repo (lubelogger has
not yet adopted `app_report_client` — 1265 lines of copy).

- **Since v0.14.0 every UI package is on Google's standalone `material_ui`**, and
  so is this app (`dart fix --apply --code=migrate_design_widgets`). Material's
  localizations come from `material_ui`'s `GlobalMaterialLocalizations.delegates`,
  never from a generated `*.localizationsDelegates`: `gen-l10n` still fills that
  list from `flutter_localizations`, whose in-framework `MaterialLocalizations` no
  `material_ui` widget finds — "No MaterialLocalizations found" at runtime, nothing
  at analysis.

## What else the shared repo ships

`app_guards` (source-scan guards and bundled scripts run as
`dart run app_guards:<tool>`, with per-app TOML configs in `tool/`:
`l10n_language.toml`, `log_coverage.toml`, `play.toml`), `app_test_kit` (the generic
half of `test/helpers.dart`, re-exported there), and `dash_kit` / `dash_ui` /
`app_util` (widgets and helpers formerly in this repo). A brand can be generated
with `DashBrand.fromSchemes` from a Material `ColorScheme` pair; how the app uses it
is in [appearance.md](appearance.md).

## Verifying against unreleased packages

**Never add `pubspec_overrides.yaml` to the apps.** Verify against unreleased
packages on a scratch copy and release a normal tag at the end. A git-excluded
`pubspec_overrides.yaml` swaps packages for local paths and `pub get` does it
silently — move it aside before verifying the way CI counts.

## Releasing the shared packages

One commit in the shared repo where every `ref:` in `packages/*/pubspec.yaml` already
names the NEW tag, plus a `version:` bump of the changed package. The tag goes on that
commit (tags are annotated and signed, so `git tag -m`), master and the tag are
pushed, then every app-shared ref in this repo's `pubspec.yaml` moves to the same tag
(`app_report_client` stays on its own `v0.2.0`). A push to master bypasses the PR
rule, so do it only when the maintainer explicitly says so.
