#!/usr/bin/env bash
# Filter one bambuddy server-reference range down to what can move our contract.
#
# Between two `dev` commits two weeks apart the server changed 324 files and
# +44876/-2567 lines; the directories that define the API held 20 files and
# +1779/-295. Everything else is frontend, tests and migrations. So the model
# never reads the raw range: it reads the briefing this script writes, which is
# the filtered diff plus the mechanical facts about our side of it.
#
#   tool/server-ref-diff.sh --from 7c117dc6 [--to origin/dev] [--out DIR]
#
# The exit status is 0 whether or not anything moved — a quiet week is not a
# failure. Whether the model is worth waking is in $OUT/drift ("yes" / "no").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FROM=""
TO="origin/dev"
OUT=""
FETCH=1

# The interactive clone the maintainer already keeps (git-excluded, full
# history); CI points BAMBUDDY_REF at the runner's persistent cache instead.
REF="${BAMBUDDY_REF:-$REPO_ROOT/reference/bambuddy}"

# Where a contract can hide. `api` and `schemas` are the contract itself; the
# core modules gate who may call what; the two services are where the WebSocket
# payloads are built, which no schema file describes. CHANGELOG.md is here
# because the server's author explains each change at length, including which
# new fields default to null for older clients.
CONTRACT_PATHS=(
  backend/app/api
  backend/app/schemas
  backend/app/core/websocket.py
  backend/app/core/permissions.py
  backend/app/core/compat.py
  backend/app/core/auth.py
  backend/app/core/config.py
  backend/app/services/printer_manager.py
  backend/app/services/print_scheduler.py
  CHANGELOG.md
)

# A whole range of raw diff would drown the briefing; these caps keep it
# readable, and the briefing prints the command that shows what was cut.
MAX_DIFF_LINES_PER_FILE=400
MAX_CHANGELOG_LINES=600

usage() {
  echo "usage: $0 --from <sha> [--to <ref>] [--out DIR] [--ref DIR] [--no-fetch]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$FROM" ]] || usage
[[ -d "$REF/.git" ]] || { echo "no server reference clone at $REF" >&2; exit 1; }

OUT="${OUT:-$REPO_ROOT/.server-drift}"
mkdir -p "$OUT"
BRIEFING="$OUT/briefing.md"

ref_git() { git -C "$REF" "$@"; }

# Only ever writes the remote-tracking ref: the clone's own checkout stays where
# the maintainer left it.
if [[ "$FETCH" == 1 ]]; then
  ref_git fetch --quiet origin "+dev:refs/remotes/origin/dev"
fi

FROM_SHA="$(ref_git rev-parse --verify "$FROM^{commit}")" || {
  echo "unknown commit $FROM in $REF (a shallow clone cannot diff two commits)" >&2
  exit 1
}
TO_SHA="$(ref_git rev-parse --verify "$TO^{commit}")"

# A range that reads backwards is worse than no range at all: every route the
# server added would be reported as one it removed, i.e. as a regression alarm
# on code that is perfectly fine. It happens for real — the maintainer's clone
# fast-forwards its local `dev` from FETCH_HEAD, which leaves origin/dev sitting
# a hundred commits in the past until something fetches it.
if ! ref_git merge-base --is-ancestor "$FROM_SHA" "$TO_SHA"; then
  echo "error: ${FROM_SHA:0:8} is not an ancestor of ${TO_SHA:0:8} — this range reads backwards." >&2
  echo "       Fetch the reference (drop --no-fetch), or pass --to with the newer commit." >&2
  exit 1
fi

CHANGED="$(ref_git diff --name-only "$FROM_SHA" "$TO_SHA" -- "${CONTRACT_PATHS[@]}" || true)"

if [[ -z "$CHANGED" ]]; then
  echo "no" > "$OUT/drift"
  {
    echo "# Server reference: no contract drift"
    echo
    echo "\`${FROM_SHA:0:8}\` → \`${TO_SHA:0:8}\`, $(ref_git rev-list --count "$FROM_SHA..$TO_SHA") commits,"
    echo "none of them touching a path that can move the API contract."
  } > "$BRIEFING"
  exit 0
fi

echo "yes" > "$OUT/drift"

# ---- the server side: routes and schema fields, extracted at both revisions ----

# A route's full path is the api prefix, plus the prefix its APIRouter was
# constructed with, plus the decorator's own path. The prefix is read from the
# first `prefix="…"` in the file, which is how every route module in this server
# is written; a module that ever splits the constructor across lines would need
# a real parser, and the briefing would show its routes with an empty prefix.
routes_at() {
  local rev="$1" file
  while read -r file; do
    [[ "$file" == *.py ]] || continue
    # A file that is new at one end of the range does not exist at the other;
    # with pipefail a missing blob would abort the whole run.
    { ref_git show "$rev:$file" 2>/dev/null || true; } | awk '
      prefix == "" && match($0, /prefix[[:space:]]*=[[:space:]]*"[^"]*"/) {
        seg = substr($0, RSTART, RLENGTH)
        sub(/^prefix[[:space:]]*=[[:space:]]*"/, "", seg)
        sub(/"$/, "", seg)
        prefix = seg
      }
      match($0, /@router\.(get|post|put|patch|delete)\("[^"]*"/) {
        d = substr($0, RSTART, RLENGTH)
        verb = d; sub(/^@router\./, "", verb); sub(/\(.*$/, "", verb)
        p = d; sub(/^[^"]*"/, "", p); sub(/"$/, "", p)
        print toupper(verb) " " prefix p
      }
    '
  done < <(printf '%s\n' "$CHANGED" | grep '^backend/app/api/routes/' || true)
}

# Every attribute of a Pydantic model, as Class.field. Four spaces of indent and
# a type annotation is what a field looks like in every schema module here.
fields_at() {
  local rev="$1" file
  while read -r file; do
    [[ "$file" == *.py ]] || continue
    { ref_git show "$rev:$file" 2>/dev/null || true; } | awk '
      /^class [A-Za-z_]/ { cls = $2; sub(/[(:].*$/, "", cls); next }
      cls != "" && /^    [a-z_][a-z0-9_]*[[:space:]]*:/ {
        f = $1; sub(/:.*$/, "", f)
        print cls "." f
      }
    '
  done < <(printf '%s\n' "$CHANGED" | grep '^backend/app/schemas/' || true)
}

# Compare shapes, not spellings: the server writes {printer_id}, we write $id.
normalize_path() { sed -e 's/{[^}]*}/{}/g' -e 's#//*#/#g'; }

routes_at "$FROM_SHA" | normalize_path | sort -u > "$OUT/routes.from"
routes_at "$TO_SHA"   | normalize_path | sort -u > "$OUT/routes.to"
fields_at "$FROM_SHA" | sort -u > "$OUT/fields.from"
fields_at "$TO_SHA"   | sort -u > "$OUT/fields.to"

comm -13 "$OUT/routes.from" "$OUT/routes.to" > "$OUT/routes.added"
comm -23 "$OUT/routes.from" "$OUT/routes.to" > "$OUT/routes.removed"
comm -13 "$OUT/fields.from" "$OUT/fields.to" > "$OUT/fields.added"
comm -23 "$OUT/fields.from" "$OUT/fields.to" > "$OUT/fields.removed"

# ---- our side: what dev actually calls and parses, right now ----

# Endpoints.dart is the single place every path the app touches is written, so
# "do we call this route" is a grep, not a judgement.
grep -ohE "'\\\$apiPrefix[^']*'" "$REPO_ROOT/lib/core/api/endpoints.dart" \
  | sed -e "s/^'//" -e "s/'\$//" -e 's/\$apiPrefix//' \
  | sed -e 's/\$[A-Za-z_][A-Za-z0-9_]*/{}/g' \
  | normalize_path | sort -u > "$OUT/app.endpoints"

# Every JSON key the app reads anywhere — the generated fromJson code and the
# hand-written parsers alike. A key absent here is a field nothing consumes.
grep -rohE "\['[a-z0-9_]+'\]" "$REPO_ROOT/lib" \
  | tr -d "[]'" | sort -u > "$OUT/app.keys"

app_has_route() { grep -qxF "$1" "$OUT/app.endpoints"; }
app_has_key()   { grep -qxF "$1" "$OUT/app.keys"; }

# A bare yes/no on a key lies by omission: `description`, `id` and `status` are
# read in dozens of unrelated models, so "already read in lib/" would quietly
# pass off a field we have never seen as one we handle. Naming the files that
# read it turns the answer back into evidence — one plausible file is a real
# hit, thirty scattered ones mean the key is simply a common word.
app_key_evidence() {
  local key="$1" files count list
  files="$(grep -rlF "['$key']" "$REPO_ROOT/lib" 2>/dev/null || true)"
  count="$(printf '%s\n' "$files" | grep -c . || true)"
  list="$(printf '%s\n' "$files" | sed -n '1,3p' | xargs -r -n1 basename | paste -sd, - | sed 's/,/, /g')"
  (( count > 3 )) && list="$list, …"
  printf '%d file(s): %s' "$count" "$list"
}

# ---- the briefing ----

DEV_SHA="$(git -C "$REPO_ROOT" rev-parse dev 2>/dev/null || git -C "$REPO_ROOT" rev-parse HEAD)"

{
  echo "# Server reference drift briefing"
  echo
  echo "- server range: \`${FROM_SHA:0:8}\` → \`${TO_SHA:0:8}\` ($(ref_git rev-list --count "$FROM_SHA..$TO_SHA") commits)"
  echo "- contract files changed: $(printf '%s\n' "$CHANGED" | wc -l)"
  echo "- our baseline: \`dev\` at \`${DEV_SHA:0:8}\`"
  echo
  echo "Facts below are mechanical — greps over \`lib/core/api/endpoints.dart\` and"
  echo "over every JSON key \`lib/\` reads. They say what exists, never whether it is"
  echo "wired to anything a user can see; that part is yours to judge from the code."
  echo

  echo "## Routes removed or renamed server-side"
  echo
  if [[ -s "$OUT/routes.removed" ]]; then
    while read -r route; do
      path="${route#* }"
      if app_has_route "$path"; then
        echo "- **[WE CALL THIS]** \`$route\` — present in endpoints.dart"
      else
        echo "- \`$route\` — not in endpoints.dart"
      fi
    done < "$OUT/routes.removed"
  else
    echo "_none_"
  fi
  echo

  echo "## Routes added server-side"
  echo
  if [[ -s "$OUT/routes.added" ]]; then
    while read -r route; do
      path="${route#* }"
      if app_has_route "$path"; then
        echo "- \`$route\` — already in endpoints.dart"
      else
        echo "- \`$route\` — **not in endpoints.dart**"
      fi
    done < "$OUT/routes.added"
  else
    echo "_none_"
  fi
  echo

  echo "## Schema fields removed"
  echo
  if [[ -s "$OUT/fields.removed" ]]; then
    while read -r field; do
      key="${field#*.}"
      if app_has_key "$key"; then
        echo "- **[WE PARSE THIS]** \`$field\` — \`$key\` read in $(app_key_evidence "$key")"
      else
        echo "- \`$field\`"
      fi
    done < "$OUT/fields.removed"
  else
    echo "_none_"
  fi
  echo

  echo "## Schema fields added"
  echo
  if [[ -s "$OUT/fields.added" ]]; then
    while read -r field; do
      key="${field#*.}"
      if app_has_key "$key"; then
        echo "- \`$field\` — \`$key\` read in $(app_key_evidence "$key")"
      else
        echo "- \`$field\` — **\`$key\` read nowhere in lib/**"
      fi
    done < "$OUT/fields.added"
  else
    echo "_none_"
  fi
  echo

  echo "## CHANGELOG additions"
  echo
  echo "The server author's own account of the range. It is a claim, not evidence:"
  echo "check anything you act on against the diff below."
  echo
  echo '```'
  ref_git diff "$FROM_SHA" "$TO_SHA" -- CHANGELOG.md \
    | grep '^+' | grep -v '^+++' | sed -n "1,${MAX_CHANGELOG_LINES}s/^+//p" || true
  echo '```'
  echo

  echo "## Filtered diff"
  echo
  printf '%s\n' "$CHANGED" | while read -r file; do
    [[ "$file" == "CHANGELOG.md" ]] && continue
    echo "### $file"
    echo
    echo '```diff'
    ref_git diff "$FROM_SHA" "$TO_SHA" -- "$file" | sed -n "5,$((MAX_DIFF_LINES_PER_FILE + 4))p"
    total="$(ref_git diff "$FROM_SHA" "$TO_SHA" -- "$file" | wc -l)"
    if (( total > MAX_DIFF_LINES_PER_FILE + 4 )); then
      echo "... truncated at $MAX_DIFF_LINES_PER_FILE lines of $total"
    fi
    echo '```'
    echo
  done

  echo "## Reading past the truncation"
  echo
  echo '```sh'
  echo "git -C $REF diff $FROM_SHA $TO_SHA -- <path>"
  echo '```'
} > "$BRIEFING"

echo "$FROM_SHA" > "$OUT/from_sha"
echo "$TO_SHA" > "$OUT/to_sha"
echo "$DEV_SHA" > "$OUT/dev_sha"

echo "briefing: $BRIEFING"
