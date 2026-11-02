# Branching and release branches

How code moves from a topic branch to a published version. The recipes behind it
are in [release.md](release.md).

## The model

```
topic ──merge──▶ dev ──merge a SHA──▶ release/X.Y.Z ──PR, merge commit──▶ master
                  ▲                                                         │
                  └──────────────── merge master back ◀─────────────────────┘
```

- **Topic branches** are `feat/…`, `fix/…`, `refactor/…`, `docs/…`, `test/…`. They
  merge into `dev` with a merge commit and are deleted. Nothing runs on them or on
  `dev`: iterate on the tests of what you touched, the full suite runs on the
  release branch.
- **`dev`** is the integration branch. Nothing is released from it and `ship`
  refuses to run on it. `ship-dev` (a prerelease, no commit) still runs anywhere.
- **`release/X.Y.Z`** is cut for every stable version and is the only branch
  `just ship X.Y.Z` runs on; the name must match the version exactly.
- **`master`** only receives release PRs. The `protect-master` ruleset requires a
  pull request, one approval and a green `analyze · test · build`.

## Cutting a release

1. `just release-start X.Y.Z` — branches off `origin/dev`, pushes the branch and
   opens a **draft** PR into `master`. From then on every push to the branch runs
   CI. Pass a base to cut elsewhere: a SHA of `dev` to release only up to it, or
   `origin/master` for a hotfix.
2. Bring in what belongs to the release: `git merge <sha-on-dev>` for everything up
   to a point, `git cherry-pick` for a single fix. A fix lands on `dev` first and
   comes over from there, so the bump commit stays the only commit that exists on
   the release branch alone.
3. Push and **monitor the runs** (`gh run list --branch release/X.Y.Z`, `gh run
   watch <id>`): CI (the draft PR's run) and the contract tests
   (push-only, see its header). Fix what is red on the release branch and carry the
   fix to `dev`.
4. `just ship X.Y.Z` once the runs are green — bumps, tests, builds, publishes the
   GitHub release and the Play internal track, then marks the PR ready. A branch
   that had nothing ahead of `master` at step 1 gets its PR here instead. The bump
   is a new head commit, so wait for its runs to go green too before step 5.
5. Merge the PR with **Merge commit**, never squash or rebase: the release tag
   points at a SHA on the release branch, and a squash leaves that SHA outside
   `master`'s history.
6. `git switch dev && git merge origin/master && git push`. This is not cosmetic:
   `ship-dev` takes its target from `git describe` on `dev`, and until `dev`
   contains the bump commit it still sees the previous tag and numbers its builds
   into a version that has already shipped.

The release is published on GitHub before the PR is merged, so waiting for green
in step 3 is what keeps a red build from reaching Obtainium; `just ship` still runs
`just test` and builds both flavors itself.

## Enforced by the repo

`protect-master` allows only the **Merge commit** method
(`allowed_merge_methods: ["merge"]`), so step 5 cannot be done wrong from the web
UI. It also requires one approval and four checks on the head commit: `analyze ·
test · build` and the three `parse real server responses (latest | daily | 1.2.5)`
jobs. Only a branch named `release/**` gets the contract jobs, so any other PR
into `master` cannot merge. The ruleset's bypass actor (repository admin) can
override all of it; do not.
