# Contributing to bambuddy-mobile

Thanks for wanting to help. This is a small project run by one maintainer, so a
little process up front saves everyone a wasted pull request.

## Start with an issue

1. **Open an issue, or comment on an existing one**, describing what you want to
   change and why.
2. **Wait for a maintainer to agree** on the approach before you write code.
3. Then open the pull request and link the issue.

A pull request without an agreed issue may be closed, even if the code is good:
the same problem may already be solved on an unreleased branch, or the app may
have made a deliberate choice you could not see from outside.

Two choices worth knowing before you propose them:

- The app supports **exactly one server**. Multi-server is not planned.
- Changes to **security or compatibility** need an explicit yes in the issue
  first: TLS and certificate trust, permissions, where tokens are stored, deep
  links, `applicationId`, anything that could break an existing install.

## Setup

```sh
git clone https://github.com/YOUR_USERNAME/bambuddy-mobile.git
cd bambuddy-mobile
just hooks          # once per clone: refuses a commit message in the wrong format
flutter pub get
```

Use the Flutter version pinned in
[.github/workflows/ci.yml](.github/workflows/ci.yml). The app has two Android
flavors, `mobile` and `wear`: **every** `flutter run` / `flutter build` needs
`--flavor`, and the watch build also needs `--target lib/wear/main_wear.dart`.

The layout and the reasoning behind it are in [AGENTS.md](AGENTS.md) and
[docs/](docs/); read the doc for the area you touch before you change it.

## Making changes

- **Branch from `dev` and open the pull request into `dev`**, never `master`.
  `master` only receives release pull requests
  ([docs/branching.md](docs/branching.md)).
- Keep a pull request to one fix or feature.
- Code comments, documentation and commit messages are **English**.
- **Commit messages** are one line, [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
  `fix(auth): stop logging out on 403`. No body, no trailers. The hook from
  `just hooks` enforces it.
- **User-visible text** goes through `AppLocalizations`, never a hardcoded string.
  Add new keys to every `.arb` from one JSON file with `just l10n-add <file>`
  (the format is in the `justfile`), then run `just l10n-check`. Translations you cannot write
  are fine to leave to the maintainer: say so in the pull request.
- **Every new control** (button, field, list tile, sheet) gets a diagnostic id
  (`logTag('area.thing', …)`), see [docs/logging-guide.md](docs/logging-guide.md).
- **Server fields and routes** are copied from the bambuddy server source and the
  web UI, not guessed. See [docs/server-contract-traps.md](docs/server-contract-traps.md).
  A change that reads or writes a new server field also gets a test in
  `test/contract/`, run against a real server (needs Docker):
  `just contract-up`, `just contract-test`, `just contract-down`
  ([docs/dev-environment.md](docs/dev-environment.md#contract-tests-locally)).
- Parse server timestamps with the helpers in
  [lib/core/models/json_utils.dart](lib/core/models/json_utils.dart), not
  `DateTime.parse`.

## Checks

Every pull request into `dev` runs the full CI (format, analyze, the whole test
suite and the APK builds), and it has to be green before it is merged. To find
problems sooner, run the same checks locally:

```sh
dart format lib test tool
flutter analyze
flutter test
flutter build apk --debug --flavor mobile
```

A new feature or bug fix comes with a test, and a test for a fix should fail when
the fix is reverted. A layout change is tested at text scale 1.0, 1.5 and 2.0.

## Reporting bugs and requesting features

- **Bugs:** use *Report a bug* in the app (Printers → ☰ menu). It attaches a
  redacted log that you review before it is sent.
- **Features and changes:** use the issue templates.
- Problems with the bambuddy server itself belong in
  [its own tracker](https://github.com/maziggy/bambuddy/issues).

## License

By contributing you agree that your work is licensed under
[AGPL-3.0](LICENSE), like the rest of the project.
