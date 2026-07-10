#!/usr/bin/env bash
# Collects the raw material for Google Play "What's new" release notes: the
# version range and the Conventional-Commit log between the two most recent
# release tags, split into user-facing vs internal. The agent turns the
# user-facing list into concise bilingual notes (see SKILL.md) — this script
# does NOT write the notes, it only gathers verified facts.
#
# Usage:
#   collect-changes.sh                 # previous tag .. latest tag
#   collect-changes.sh <new>           # previous tag .. <new>   (e.g. HEAD or v0.10.1)
#   collect-changes.sh <new> <old>     # <old> .. <new>
#
# Version tags are lightweight `vX.Y.Z`. Run from anywhere in the repo.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Tags newest-first by semver.
mapfile -t TAGS < <(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$')
if [ "${#TAGS[@]}" -lt 1 ]; then
  echo "No vX.Y.Z tags found." >&2
  exit 1
fi

NEW="${1:-${TAGS[0]}}"
OLD="${2:-}"
if [ -z "$OLD" ]; then
  # First tag that is strictly older than NEW's commit — i.e. skip any tag
  # pointing at the same commit as NEW, then take the next one down.
  new_sha="$(git rev-parse "$NEW^{commit}")"
  for t in "${TAGS[@]}"; do
    [ "$(git rev-parse "$t^{commit}")" = "$new_sha" ] && continue
    OLD="$t"
    break
  done
fi
if [ -z "$OLD" ]; then
  echo "Could not determine a previous tag before $NEW." >&2
  exit 1
fi

PUBSPEC_VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')"

echo "=============================================="
echo " RELEASE NOTES SOURCE"
echo "   pubspec version : $PUBSPEC_VERSION"
echo "   range           : $OLD .. $NEW"
echo "   new tag date    : $(git log -1 --format=%ci "$NEW")"
echo "=============================================="
echo

# feat/fix/perf are the changes users can perceive. Everything else
# (chore/docs/refactor/test/ci/build/style) is skipped — but printed below so
# nothing is silently dropped and the agent can rescue a borderline case.
USER_FACING_RE='^[a-f0-9]+ (feat|fix|perf)(\(.+\))?!?:'

echo "### USER-FACING (turn these into release notes) ###"
echo "# Full subject + body so you can extract the concrete change per commit."
echo
git log --format='%h %s' "$OLD..$NEW" | grep -E "$USER_FACING_RE" || echo "(none)"
echo
echo "--- bodies ---"
# Print hash, subject and body for the user-facing commits (bodies often list
# multiple concrete changes squashed into one commit).
while IFS= read -r sha; do
  git log -1 --format='%n• %h %s%n%w(0,4,4)%b' "$sha"
done < <(git log --format='%H %s' "$OLD..$NEW" | grep -E '^[a-f0-9]+ (feat|fix|perf)(\(.+\))?!?:' | awk '{print $1}')
echo

echo "### INTERNAL (skip — shown for completeness) ###"
git log --format='%h %s' "$OLD..$NEW" | grep -Ev "$USER_FACING_RE" || echo "(none)"
