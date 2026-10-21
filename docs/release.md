# Release pipeline

How a version leaves this repository, and the traps behind each recipe in the
`justfile`. Read it before touching `ship`, `ship-dev`, `release-publish`,
`play-internal` or the version scheme.

## `just ship X.Y.Z`

Bumps the version in `pubspec.yaml`, runs the tests, builds the phone and watch
APKs and publishes a GitHub Release with the APKs as assets. Users update through
Obtainium. `origin` is `DoYouHost/bambuddy-mobile` on GitHub; the recipes call
`gh --repo`, not `tea`, and nothing is released from Codeberg any more.

- **`versionCode` is derived from the version:**
  `(major*10000 + minor*100 + patch) * 20 + 2_000_000` (1.2.3 → 2_204_060); the
  watch adds `+1_000_000_000`. The 2 M offset exists because narrowing the
  multiplier from ×1000 to ×20 alone would have produced codes **lower** than the
  ones already installed. Obtainium updates only when `versionCode` rises — a tag
  or a `versionName` is not enough.
- **The server creates the tag.** Never push a tag separately. `release-publish`
  pushes the commit, then `gh release create vX.Y.Z --target <SHA>` creates tag
  and release atomically. Use the SHA, not the branch name: the tip can move
  between the push and the call. Pushing a tag and referring to it at once is a
  race, and it caused about six failed ships.
- **A release goes out from the checked-out branch, not from `master`.** `_branch`
  (one definition shared by both recipes) reads `git symbolic-ref` and refuses a
  detached HEAD. `_bump` rebases onto `origin <that branch>`; it skips the rebase
  only when `ls-remote` returns **2** (no such branch on origin) and aborts on 128
  (origin unreachable). `release-publish` pushes `HEAD:refs/heads/<that branch>`.
- **`gh` takes one item per call** in `release delete` / `delete-asset` (unlike
  `tea`), hence the loops in `purge-assets` and `purge-releases`.
- **Capture `gh` output into a variable, then filter it.** `gh … | grep -q` under
  `set -o pipefail` deadlocks on SIGPIPE (141) and takes the wrong `if` branch.
- `just` passes no arguments to dependencies, so `ship` calls `_bump`, `test` and
  the builds by hand. In a shebang recipe the shebang must be the first line.
- The release keystore sits outside the repository and is referenced from
  `android/key.properties` (gitignored). The release build runs R8, so ML Kit
  needs its keep rules.
- Do not write manual-setup instructions ("make the repo public", "enable Pages")
  into code or workflows without checking the state through the API or asking.

## `just ship-dev [X.Y.Z | X.Y.Z-dev.N]`

Publishes a prerelease `vX.Y.Z-dev.N` with `--generate-notes`, no AAB and **no
commit**: the version travels as `--build-name` / `--build-number`, so `-dev`
never sits on a branch. `versionCode = code(X.Y.Z) - 20 + N`, so dev builds live in
the 19 slots **below** their target. `N` counts the target's builds (the first is
`dev.1`), read from the tags; a tag already on HEAD is reused.

It refuses a dirty tree (untracked files included), `N=0`, `N>19`, a target that
is not newer than the last tag, and an unpushed HEAD. `just purge-dev-tags [5]`
cleans up. A bug report's log header carries `0.12.1-dev.7+1200007`, so an issue
from a dev build points at a commit.

## Frozen `applicationId`

`page.codeberg.morganmlgman.bambuddy_mobile` stays **forever**, together with the
`namespace` and the MethodChannel and widget provider names. It is the identity of
the Play listing: changing it makes a different app and loses every install.
Never "tidy" these strings and never report them as an inconsistency; only links
are replaced.

## Google Play

- The maintainer presses Publish themselves, on purpose. Wear OS goes on its
  **own Wear OS track**, not in the phone release (a Play rule since 2023).
  Before any upload go through [play-compliance.md](play-compliance.md).
- **Play API.** The service-account key lives outside the repository (path in
  `tool/play.toml`). `just play-tracks` is read-only; `just play-internal
  [--dry-run]` uploads both AABs to internal testing in one edit
  (`dart run app_guards:play internal`, which skips versionCodes already on a
  track). The key can also write listing images; only `en-US` holds images and the
  other listings inherit them. `app_guards:play` has no images or listing command,
  so such a change is a one-off API edit. Every commit passes `changesNotSentForReview=true`
  (see AGENTS.md).
- **Store page and privacy policy** are served by GitHub Pages from `site/` on
  `master` (`.github/workflows/pages.yml`):
  `https://doyouhost.github.io/bambuddy-mobile/privacy.html`. Pages does not work
  on a private repository in an organisation on the free plan, so the repository
  must stay public — a dead policy URL is a policy problem on a live listing.
- **Data Safety lesson.** An automated check once found an undisclosed **email
  address**: the only place is the Bambu cloud login, sent to the user's own
  server. For Play, "off the device" means off the device. The declaration is
  Personal info → Email addresses, collected, not shared, optional, purpose = app
  functionality; "encrypted in transit" is **no** (`usesCleartextTraffic`).
- **`WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="29"` stays** — approved, do not
  ask again; the reason is in [play-compliance.md](play-compliance.md).
- The store name is **"Bambuddy"** (capital B, lower-case b in the middle).
