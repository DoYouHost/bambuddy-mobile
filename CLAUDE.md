@AGENTS.md

# Claude Code only

[AGENTS.md](AGENTS.md) above is the shared set of rules every coding agent reads.
This file adds what only holds for Claude Code. Anything that is true for any
agent belongs in AGENTS.md, not here.

## Running as the GitHub Action

Running as the GitHub Action you are allowed `flutter analyze`, `flutter test`,
`flutter pub get`, `flutter gen-l10n`, `dart run build_runner build`, the
read-only `gh run/pr/issue view`, `WebSearch` and `WebFetch` on pub.dev and
wiki.bambuddy.cool — **run them, do not ask for them.** APK builds are not on
that list on purpose; the CI run is what proves those.

The bambuddy server source is already checked out for you at
`/tmp/bambuddy-server-ref`; read it with Read and Grep. Do not clone it yourself
— the bash sandbox has no network egress, so the clone fails there and the
workflow does it before you start. Do not delete it either; the workflow
removes it.

## Skills

`.claude/skills/` holds the project skills — `/log-coverage` (unnamed controls
in the diagnostic log), `/reference-update` (triage of server changes),
`/run-app-emulator` and `/humanizer`. Prefer the skill over redoing its steps by
hand.
