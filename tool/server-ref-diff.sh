#!/usr/bin/env bash
# Filter one bambuddy server-reference range down to what can move our contract.
#
# Between two `dev` commits two weeks apart the server changed 324 files and
# +44876/-2567 lines; the directories that define the API held 20 files and
# +1779/-295. Everything else is frontend, tests and migrations. So the model
# never reads the raw range: it reads what this script writes — facts.md, the
# mechanical picture of both sides, and diff.md, the filtered diff behind it.
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
SELF_TEST=0

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

# A whole range of raw diff would drown diff.md; these caps keep it readable,
# and the file ends with the command that shows whatever was cut.
MAX_DIFF_LINES_PER_FILE=400
MAX_CHANGELOG_LINES=600

usage() {
  echo "usage: $0 --from <sha> [--to <ref>] [--out DIR] [--ref DIR] [--no-fetch]" >&2
  echo "       $0 --self-test" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

# Which permissions gate each route, read from the route as it stands at the end
# of the range, with the router prefix it belongs to — the prefix is the surface
# the roll-up below groups by. Only the route's own signature is scanned: a gate
# lives there, and a whole function body would drag in every unrelated
# permission it happens to mention.
route_perms_in() {
  { ref_git show "$1:$2" 2>/dev/null || true; } | gate_scan
}

# The scan itself, over one route module on stdin, so `--self-test` can drive it
# without a git range. Emits `METHOD /path <TAB> PERM,PERM <TAB> /prefix`.
gate_scan() {
  awk '
      function flush() {
        for (i = 1; i <= n; i++) print pending[i] "\t" perms "\t" prefix
        n = 0; perms = ""
      }
      prefix == "" && match($0, /prefix[[:space:]]*=[[:space:]]*"[^"]*"/) {
        seg = substr($0, RSTART, RLENGTH)
        sub(/^prefix[[:space:]]*=[[:space:]]*"/, "", seg)
        sub(/"$/, "", seg)
        prefix = seg
      }
      # A module that declares its gates once at the top and spends them as
      # `_ = _READ` names no permission anywhere near its routes —
      # `location_ha_sensors.py` is written exactly that way, and reading it
      # without this said "no gate found" about four routes no API key can call.
      /^[A-Za-z_][A-Za-z_0-9]*[[:space:]]*=[^=]*Permission\.[A-Z_0-9]+/ {
        alias = $0
        sub(/[[:space:]]*=.*$/, "", alias)
        match($0, /Permission\.[A-Z_0-9]+/)
        aliased = substr($0, RSTART, RLENGTH); sub(/^Permission\./, "", aliased)
        aliases[alias] = aliased
        next
      }
      match($0, /@router\.(get|post|put|patch|delete)\("[^"]*"/) {
        # Several decorators can stack on one function; they share its gate, so
        # they are held until the signature that follows them is read. A
        # decorator arriving after a signature starts a new function instead,
        # and `scanned` is what tells the two apart: keying it on "no permission
        # turned up yet" gave the 57 ungated routes in this server — the
        # token-authorised archive downloads, the auth bootstrap — the gate of
        # whichever route was declared below them.
        if (n > 0 && scanned > 0) flush()
        d = substr($0, RSTART, RLENGTH)
        verb = d; sub(/^@router\./, "", verb); sub(/\(.*$/, "", verb)
        p = d; sub(/^[^"]*"/, "", p); sub(/"$/, "", p)
        pending[++n] = toupper(verb) " " prefix p
        scanned = 0; reading_sig = 1
        next
      }
      n > 0 && reading_sig {
        # `)` at column 0 closes a multi-line signature, `):` at the end of a
        # line closes a one-liner. Reading on past either swept in the decorator
        # below, so a plain GET came back carrying the write gate of the route
        # after it — which reads as "no API key can call this read".
        scanned++
        if (scanned > 40 || /^\)/) { reading_sig = 0; next }
        line = $0
        while (match(line, /Permission\.[A-Z_0-9]+/)) {
          one = substr(line, RSTART, RLENGTH); sub(/^Permission\./, "", one)
          if (index("," perms ",", "," one ",") == 0) {
            perms = perms == "" ? one : perms "," one
          }
          line = substr(line, RSTART + RLENGTH)
        }
        for (a in aliases) {
          # Whole word only: `_READ` must not match `_READ_ALL`.
          if ($0 ~ ("(^|[^A-Za-z_0-9])" a "([^A-Za-z_0-9]|$)")) {
            one = aliases[a]
            if (index("," perms ",", "," one ",") == 0) {
              perms = perms == "" ? one : perms "," one
            }
          }
        }
        if (/\):[[:space:]]*$/) reading_sig = 0
      }
      END { if (n > 0) flush() }
    '
}

# `--self-test`: the gate scan against a module written the way this server
# writes them. It exists because the scan is the one part of this script that
# can be confidently wrong — a route it mis-gates still produces a plausible
# line in facts.md, and the wrong line reads as "no API key can call this",
# which is how a whole feature gets parked. The fixture is the shape of the
# mistakes actually found, not a rewrite of the awk in another language.
self_test() {
  local fixture expected actual failures=0

  fixture=$(cat <<'PY'
router = APIRouter(prefix="/things", tags=["things"])

_READ = RequirePermissionIfAuthEnabled(Permission.THINGS_READ)
_UPDATE = RequirePermissionIfAuthEnabled(Permission.THINGS_UPDATE)


@router.get("/", response_model=list[ThingResponse])
async def list_things(
    db: AsyncSession = Depends(get_db),
    _: User | None = _READ,
):
    """A read must not pick up the write declared below it."""
    if not current_user.has_permission(Permission.THINGS_ADMIN.value):
        raise HTTPException(status_code=403)
    return []


@router.patch("/{thing_id}")
async def update_thing(thing_id: int, _: User | None = _UPDATE):
    return None


@router.get("/{thing_id}/dl/{token}/{filename}")
async def download_thing(thing_id: int, token: str, filename: str):
    """Authorised by the token in the path, gated by nothing."""
    return FileResponse(path)


@router.get("/legacy-alias")
@router.get("/canonical")
async def two_paths_one_gate(
    auth: tuple[User | None, bool] = Depends(
        require_ownership_permission(
            Permission.THINGS_READ_ALL,
            Permission.THINGS_READ_OWN,
        )
    ),
):
    return []
PY
)

  # A one-line signature ends at its own `):`; a multi-line one at the `)` in
  # column 0. Both had to stop the scan before the next decorator.
  expected=$(printf '%s\n' \
    'GET /things/	THINGS_READ	/things' \
    'PATCH /things/{thing_id}	THINGS_UPDATE	/things' \
    'GET /things/{thing_id}/dl/{token}/{filename}		/things' \
    'GET /things/legacy-alias	THINGS_READ_ALL,THINGS_READ_OWN	/things' \
    'GET /things/canonical	THINGS_READ_ALL,THINGS_READ_OWN	/things')

  actual="$(printf '%s\n' "$fixture" | gate_scan)"

  if [[ "$actual" != "$expected" ]]; then
    failures=1
    echo "gate_scan: output does not match." >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") \
      | sed 's/^/  /' >&2 || true
  fi

  # The permission in the body of `list_things` is the trap the 30-line window
  # fell into: it is a branch inside the route, not a gate on it.
  if printf '%s\n' "$actual" | grep -q 'THINGS_ADMIN'; then
    failures=1
    echo "gate_scan: a permission from a route body leaked into its gate." >&2
  fi

  if (( failures )); then
    echo "self-test FAILED" >&2
    exit 1
  fi
  echo "self-test ok: $(printf '%s\n' "$expected" | wc -l) routes scanned as expected"
}

if (( SELF_TEST )); then
  self_test
  exit 0
fi

[[ -n "$FROM" ]] || usage
[[ -d "$REF/.git" ]] || { echo "no server reference clone at $REF" >&2; exit 1; }

OUT="${OUT:-$REPO_ROOT/.server-drift}"
mkdir -p "$OUT"
FACTS="$OUT/facts.md"
DIFF="$OUT/diff.md"

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
  } > "$FACTS"
  exit 0
fi

echo "yes" > "$OUT/drift"

# ---- the server side: routes and schema fields, extracted at both revisions ----

# A route's full path is the api prefix, plus the prefix its APIRouter was
# constructed with, plus the decorator's own path. The prefix is read from the
# first `prefix="…"` in the file, which is how every route module in this server
# is written; a module that ever splits the constructor across lines would need
# a real parser, and facts.md would show its routes with an empty prefix.
route_lines_in() {
  # A file that is new at one end of the range does not exist at the other;
  # with pipefail a missing blob would abort the whole run.
  { ref_git show "$1:$2" 2>/dev/null || true; } | awk '
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
}

# ---- what an API key may do with a route ----
#
# The app recommends an API key as the way to connect (`setup_screen.dart`), so
# "can a key do this?" decides whether a feature is worth building at all — and
# it is not a judgement call: `_APIKEY_SCOPE_BY_PERMISSION` is an allowlist that
# fails closed, so a permission missing from it is a 403 no operator can grant.
# Resolved here rather than left to the reader, because getting it wrong costs a
# whole feature: keep-warm was written and thrown away for want of this line.
apikey_scope_map() {
  { ref_git show "$TO_SHA:backend/app/core/auth.py" 2>/dev/null || true; } | awk '
      # Two blocks, two meanings. The allowlist is the gate; the denylist is the
      # server author saying "this one is administrative on purpose", which
      # tells a reader whether an absence is deliberate or an oversight.
      /_APIKEY_SCOPE_BY_PERMISSION[^=]*=[[:space:]]*\{/ { map = 1; next }
      /_APIKEY_DENIED_PERMISSIONS[^=]*=[[:space:]]*frozenset/ { denied = 1; next }
      map && /^\}/ { map = 0; next }
      denied && /^\)/ { denied = 0; next }
      /^[[:space:]]*#/ { next }
      map && match($0, /Permission\.[A-Z_0-9]+[[:space:]]*:/) {
        name = substr($0, RSTART, RLENGTH)
        sub(/^Permission\./, "", name); sub(/[[:space:]]*:$/, "", name)
        rest = substr($0, RSTART + RLENGTH)
        scopes = ""
        while (match(rest, /"[a-z_]+"/)) {
          one = substr(rest, RSTART + 1, RLENGTH - 2)
          scopes = scopes == "" ? one : scopes "," one
          rest = substr(rest, RSTART + RLENGTH)
        }
        if (scopes != "") print name "\tscope\t" scopes
        next
      }
      denied && match($0, /Permission\.[A-Z_0-9]+/) {
        name = substr($0, RSTART, RLENGTH); sub(/^Permission\./, "", name)
        print name "\tdenied\t"
      }
    '
}

# An unreadable allowlist would otherwise answer "no key scope" for every
# permission in the range — a silent false negative that hides exactly the
# features this resolution exists to surface.
apikey_map_ok() { grep -q $'\tscope\t' "$OUT/apikey.scopes" 2>/dev/null; }
key_scope_of() { awk -F'\t' -v p="$1" '$1 == p && $2 == "scope" { print $3; exit }' "$OUT/apikey.scopes"; }

# The verdict for one permission name: the scope flag that grants it, or why no
# key ever holds it.
key_reach() {
  local perm="$1" row
  if ! apikey_map_ok; then
    echo "**key scope unknown** — \`core/auth.py\` did not parse, resolve by hand"
    return
  fi
  row="$(key_scope_of "$perm")"
  if [[ -n "$row" ]]; then
    echo "key scope \`$row\`"
    return
  fi
  if awk -F'\t' -v p="$perm" '$1 == p && $2 == "denied" { found = 1 } END { exit !found }' "$OUT/apikey.scopes"; then
    echo "**no key scope** (named administrative)"
  else
    echo "**no key scope** (absent from the allowlist)"
  fi
}

routes_at() {
  local rev="$1" file
  while read -r file; do
    [[ "$file" == *.py ]] || continue
    route_lines_in "$rev" "$file"
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
        line = $0
        sub(/^[[:space:]]+/, "", line)
        f = line; sub(/[[:space:]]*:.*$/, "", f)
        ann = substr(line, index(line, ":") + 1)
        sub(/=.*$/, "", ann)
        gsub(/[[:space:]]+/, " ", ann)
        gsub(/^ | $/, "", ann)
        print cls "." f "\t" ann
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

apikey_scope_map > "$OUT/apikey.scopes"

# Route → the permissions gating it and the surface it belongs to, as of the end
# of the range, normalized the same way the route lists are so the two can be
# joined.
: > "$OUT/route.perms"
while read -r file; do
  [[ "$file" == *.py ]] || continue
  # Normalized whole-line, not field by field: `IFS=$'\t' read` treats tab as
  # IFS whitespace, so it collapses the two tabs of an ungated route into one
  # and shifts the router prefix into the permissions column — where every
  # token-authorised download then read as "gated by `/archives`, no key
  # scope". Neither a permission name nor a prefix contains a brace or a
  # doubled slash, so the substitutions cannot touch them.
  route_perms_in "$TO_SHA" "$file" | normalize_path >> "$OUT/route.perms"
done < <(printf '%s\n' "$CHANGED" | grep '^backend/app/api/routes/' || true)

comm -13 "$OUT/routes.from" "$OUT/routes.to" > "$OUT/routes.added"
comm -23 "$OUT/routes.from" "$OUT/routes.to" > "$OUT/routes.removed"
# A field keeps its name and changes its type or its optionality more often
# than it appears or disappears, and that change is exactly the kind that breaks
# a client quietly — so names and annotations are diffed separately.
cut -f1 "$OUT/fields.from" | sort -u > "$OUT/fields.from.names"
cut -f1 "$OUT/fields.to"   | sort -u > "$OUT/fields.to.names"
comm -13 "$OUT/fields.from.names" "$OUT/fields.to.names" > "$OUT/fields.added"
comm -23 "$OUT/fields.from.names" "$OUT/fields.to.names" > "$OUT/fields.removed"

: > "$OUT/fields.changed"
while IFS=$'\t' read -r name ann; do
  old_ann="$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$OUT/fields.from")"
  if [[ -n "$old_ann" && "$old_ann" != "$ann" ]]; then
    printf '%s\t%s\t%s\n' "$name" "$old_ann" "$ann" >> "$OUT/fields.changed"
  fi
done < "$OUT/fields.to"

# A gate, a status code and a ranking function all live inside a route body:
# nothing about them appears in a list of routes or a list of fields, which is
# how a per-key permission that now answers 403, a new 413, and a rewritten
# main-plug ranking all passed the first version of this script unseen. They are
# read from the diff, because what matters is that they moved and where.
route_signals() {
  local file diff gates codes defs perms ours perm
  while read -r file; do
    diff="$(ref_git diff "$FROM_SHA" "$TO_SHA" -- "$file")"

    # A rewritten ranking inside a route we call is our problem; the same
    # rewrite in a route we never call is not, and only endpoints.dart can tell
    # the two apart. Without this line a reader sees a file name and guesses —
    # which is how a server-side plug ranking got filed as "transparent to us"
    # while the app was still picking its own plug from /smart-plugs/.
    ours=""
    if [[ "$file" == backend/app/api/routes/* ]]; then
      ours="$(route_lines_in "$TO_SHA" "$file" | normalize_path | sort -u \
        | while read -r route; do
            if app_has_route "${route#* }"; then echo "$route"; fi
          done | sed -n '1,5p' | paste -sd';' - | sed 's/;/; /g' || true)"
    fi

    # The scope map decides what an API key may do at all, and it moves without
    # touching a route or a field.
    perms="$(printf '%s\n' "$diff" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
      | grep -oE 'Permission\.[A-Z_]+' | sort -u | sed 's/^Permission\.//' \
      | paste -sd' ' - || true)"
    gates="$(printf '%s\n' "$diff" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
      | grep -oE '(Require[A-Za-z_]+|Depends\([a-zA-Z_.]+|Security\([a-zA-Z_.]+)' \
      | sed -E 's/^(Depends|Security)\(//' | sort -u | paste -sd' ' - || true)"
    codes="$(printf '%s\n' "$diff" | grep -E '^\+' \
      | grep -oE '(status_code=|HTTPException\()[0-9]{3}' | grep -oE '[0-9]{3}' \
      | sort -u | paste -sd',' - || true)"
    defs="$(printf '%s\n' "$diff" | grep -E '^[+-][[:space:]]*(async )?def ' \
      | sed -E 's/^[+-][[:space:]]*(async )?def ([a-zA-Z_0-9]+).*/\2/' \
      | sort -u | paste -sd' ' - || true)"
    if [[ -n "$gates$codes$defs$perms$ours" ]]; then
      echo "- \`${file#backend/app/}\`"
      if [[ -n "$ours" ]]; then
        echo "  - **we call routes in this file**: $ours"
      elif [[ "$file" == backend/app/api/routes/* ]]; then
        echo "  - we call none of this file's routes"
      fi
      if [[ -n "$perms" ]]; then
        echo "  - permissions named on changed lines:"
        for perm in $perms; do
          echo "    - \`$perm\` → $(key_reach "$perm")"
        done
      fi
      [[ -n "$gates" ]] && echo "  - gates touched: $gates"
      [[ -n "$codes" ]] && echo "  - error codes on added lines: $codes"
      [[ -n "$defs" ]] && echo "  - functions added or removed: $defs"
    fi
  done < <(printf '%s\n' "$CHANGED" | grep -E '^backend/app/(api/|core/)' | grep '\.py$' || true)
  return 0
}

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

# The gate on one route, and the verdict for it. Matched literally on
# "METHOD path", never as a pattern: a normalized path carries `{}`, which awk
# reads as a quantifier and dies on.
#
# By method as well as path, because a `GET` and a `DELETE` on one path are
# routinely gated apart — read on a scope a key holds, write on one no key ever
# does.
route_key_reach() {
  local route="$1" perms verdicts perm
  perms="$(awk -F'\t' -v r="$route" '$1 == r { print $2; exit }' "$OUT/route.perms")"
  if [[ -z "$perms" ]]; then
    # Either genuinely open (the token-authorised download routes are), or
    # gated in a way this grep does not see. Worth saying which rather than
    # implying a key can use it.
    echo "no gate found on the route — read it before believing a key can call it"
    return
  fi
  verdicts=""
  while IFS= read -r perm; do
    [[ -n "$perm" ]] || continue
    verdicts+="\`$perm\` → $(key_reach "$perm"); "
  done < <(printf '%s\n' "${perms//,/$'\n'}")
  echo "${verdicts%; }"
}

# ---- what an API key can do with a whole surface ----
#
# A per-route verdict answers "can a key call this endpoint". What decides
# whether a feature is worth building is what a key can do with the surface as a
# whole, and those are not the same question: every write on
# `/location-ha-sensors` is SMART_PLUGS_CREATE/UPDATE/DELETE, which no key can
# hold, while every read on it is SMART_PLUGS_READ → `can_read_status`. Read
# alone is the whole feature for us — the app shows a location's temperature and
# humidity, the binding is done in the server's own UI — so rolling that surface
# up to "no key scope" parks something buildable today.

# `yes` when a key can call the route, `no` when it cannot, `unknown` when the
# route declares no gate this grep can see.
#
# Reachable if *any* gating permission resolves, not all of them: this server
# has no route requiring two permissions at once (`RequirePermissionIfAuthEnabled`
# is always called with one), so a route naming two is an either/or —
# `require_ownership_permission(X_ALL, X_OWN)`, or the `USERS_READ` /
# `USERS_READ_SLIM` pair on `GET /users/slim`. Should a real conjunction ever
# appear, the per-route line above still prints every permission and its own
# verdict, which is where a reader would catch it.
route_key_state() {
  local route="$1" perms perm reachable=no
  perms="$(awk -F'\t' -v r="$route" '$1 == r { print $2; exit }' "$OUT/route.perms")"
  if [[ -z "$perms" ]]; then
    echo unknown
    return
  fi
  if ! apikey_map_ok; then
    echo unknown
    return
  fi
  while IFS= read -r perm; do
    [[ -n "$perm" ]] || continue
    if [[ -n "$(key_scope_of "$perm")" ]]; then
      reachable=yes
    fi
  done < <(printf '%s\n' "${perms//,/$'\n'}")
  echo "$reachable"
}

# The router prefix a route belongs to — the module, which is also the feature.
# A module that declares no prefix carries the whole path in its decorators, and
# there the first segment is the closest thing to a surface.
surface_of() {
  local route="$1" path prefix
  path="${route#* }"
  prefix="$(awk -F'\t' -v r="$route" '$1 == r { print $3; exit }' "$OUT/route.perms")"
  if [[ -n "$prefix" ]]; then
    printf '%s\n' "$prefix"
  else
    printf '/%s\n' "$(printf '%s' "${path#/}" | cut -d/ -f1)"
  fi
}

# One markdown block per surface a route was added to, verdict first.
#
# Rolled up over every route the surface has at the end of the range, not only
# the added ones: a single write bolted onto a surface we already read from is
# not a "key: no" feature, it is one more write on a surface whose reads work.
added_surfaces() {
  [[ -s "$OUT/routes.added" ]] || return 0

  local route surface
  : > "$OUT/surfaces.routes"
  while read -r route; do
    [[ -n "$route" ]] || continue
    printf '%s\t%s\n' "$(surface_of "$route")" "$route" >> "$OUT/surfaces.routes"
  done < "$OUT/routes.to"

  while read -r route; do
    [[ -n "$route" ]] || continue
    surface_of "$route"
  done < "$OUT/routes.added" | sort -u | while read -r surface; do
    surface_block "$surface"
  done
}

surface_block() {
  local surface="$1" route state verb
  local reads=0 reads_ok=0 writes=0 writes_ok=0 ungated=0 added=0 listed=0
  local can_call="" read_perms="" blocked_perms="" perm one verdict is_new

  while IFS=$'\t' read -r _ route; do
    state="$(route_key_state "$route")"
    verb="${route%% *}"
    perm="$(awk -F'\t' -v r="$route" '$1 == r { print $2; exit }' "$OUT/route.perms")"
    is_new=no
    if grep -qxF "$route" "$OUT/routes.added"; then is_new=yes; added=$((added + 1)); fi
    # A route with no permission gate is counted apart from both totals rather
    # than as one a key cannot call: `GET /camwall/printers` is authorised by a
    # Cam Wall token and `POST /users/me/change-password` by being signed in, and
    # counting either as unreachable turned its surface into `key: no` — the one
    # verdict that stops a reader from looking further.
    case "$state" in
      yes)
        if [[ "$verb" == GET ]]; then
          reads=$((reads + 1)); reads_ok=$((reads_ok + 1))
          # Only the permission that actually grants the route. An either/or
          # gate names two — `USERS_READ_SLIM` carries a key scope and
          # `USERS_READ` does not — and printing both under "reads on" would
          # credit a key with a permission it never holds.
          for one in ${perm//,/ }; do
            if [[ -n "$(key_scope_of "$one")" ]]; then read_perms+="$one"$'\n'; fi
          done
        else
          writes=$((writes + 1)); writes_ok=$((writes_ok + 1))
        fi
        # Only the new ones get listed. On a surface we already use, the
        # reachable routes number in the dozens and the eight that sort first
        # are not the eight anybody wants — what a reader needs here is what
        # just appeared and can be called.
        if [[ "$is_new" == yes ]]; then
          listed=$((listed + 1))
          if (( listed <= 8 )); then can_call+="\`$route\`, "; fi
        fi
        ;;
      no)
        if [[ "$verb" == GET ]]; then reads=$((reads + 1)); else writes=$((writes + 1)); fi
        blocked_perms+="${perm//,/ }"$'\n'
        ;;
      unknown) ungated=$((ungated + 1)) ;;
    esac
  done < <(awk -F'\t' -v s="$surface" '$1 == s' "$OUT/surfaces.routes")

  # Verdict order matters: `read-only` is the case this roll-up exists for, and
  # it is narrower than `partial` — every read works and no write does.
  if (( reads + writes == 0 )); then
    verdict="**key: unresolved** — no permission gate found on any of its routes"
  elif (( reads_ok + writes_ok == reads + writes )); then
    verdict="**key: full**"
  elif (( reads_ok + writes_ok == 0 )); then
    verdict="**key: no**"
  elif (( reads > 0 && reads_ok == reads && writes_ok == 0 )); then
    verdict="**key: read-only** — a key sees everything here and can change nothing"
  else
    verdict="**key: partial**"
  fi

  echo "- **\`$surface\`** — $verdict — $reads read route(s), $reads_ok reachable; $writes write route(s), $writes_ok reachable — $added new in this range"
  if (( ungated > 0 )); then
    echo "  - $ungated route(s) declare no gate this grep can see — read them before counting on either answer"
  fi
  if [[ -n "$read_perms" ]]; then
    echo "  - reads on: $(printf '%s' "$read_perms" | tr ' ' '\n' | grep . | sort -u | sed 's/^/`/;s/$/`/' | paste -sd, - | sed 's/,/, /g')"
  fi
  if [[ -n "$blocked_perms" ]]; then
    echo "  - out of reach: $(printf '%s' "$blocked_perms" | tr ' ' '\n' | grep . | sort -u | sed 's/^/`/;s/$/`/' | paste -sd, - | sed 's/,/, /g') → no key scope"
  fi
  if [[ -n "$can_call" ]]; then
    if (( listed > 8 )); then
      echo "  - a key can call, of the new ones: ${can_call%, }, and $((listed - 8)) more"
    else
      echo "  - a key can call, of the new ones: ${can_call%, }"
    fi
  elif (( added > 0 && reads + writes > 0 )); then
    echo "  - none of the $added new route(s) resolves to a scope a key can carry"
  fi
  return 0
}

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

# ---- the two documents ----

DEV_SHA="$(git -C "$REPO_ROOT" rev-parse dev 2>/dev/null || git -C "$REPO_ROOT" rev-parse HEAD)"

{
  echo "# Server reference drift — the facts"
  echo
  echo "- server range: \`${FROM_SHA:0:8}\` → \`${TO_SHA:0:8}\` ($(ref_git rev-list --count "$FROM_SHA..$TO_SHA") commits)"
  echo "- contract files changed: $(printf '%s\n' "$CHANGED" | wc -l)"
  echo "- our baseline: \`dev\` at \`${DEV_SHA:0:8}\`"
  echo
  echo "Everything below is mechanical — greps over \`lib/core/api/endpoints.dart\` and"
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
  echo "Each one carries the gate it is declared with and what an **API key** can"
  echo "do about it. A key is how this app is meant to connect, so a route no key"
  echo "can reach is one only a password login could call. That is a fact about a"
  echo "route, not a verdict on a feature — the roll-up below is the verdict, and"
  echo "it is the one to read first."
  echo
  if [[ -s "$OUT/routes.added" ]]; then
    while read -r route; do
      path="${route#* }"
      if app_has_route "$path"; then
        wired="already in endpoints.dart"
      else
        wired="**not in endpoints.dart**"
      fi
      echo "- \`$route\` — $wired — $(route_key_reach "$route")"
    done < "$OUT/routes.added"
  else
    echo "_none_"
  fi
  echo

  echo "## What an API key can do with each added surface"
  echo
  echo "One entry per router prefix a route was added to, counted over **every**"
  echo "route that prefix has at the end of the range — not only the new ones, so a"
  echo "single write bolted onto a surface we already read is not mistaken for a"
  echo "surface out of reach."
  echo
  echo "The verdict to look for is **key: read-only**: a key sees everything the"
  echo "surface holds and can change none of it. That is not a blocked feature, it"
  echo "is a smaller one — the readings can be shown, the binding is done in the"
  echo "server's own UI. \`/location-ha-sensors\` is exactly that shape, and reading"
  echo "its writes alone would have parked a screen that is buildable today."
  echo
  surfaces="$(added_surfaces)"
  if [[ -n "$surfaces" ]]; then
    printf '%s\n' "$surfaces"
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

  echo "## Schema fields changed in place"
  echo
  if [[ -s "$OUT/fields.changed" ]]; then
    while IFS=$'\t' read -r field old new; do
      key="${field#*.}"
      if app_has_key "$key"; then
        echo "- **[WE PARSE THIS]** \`$field\` — was \`$old\`, now \`$new\` — \`$key\` read in $(app_key_evidence "$key")"
      else
        echo "- \`$field\` — was \`$old\`, now \`$new\`"
      fi
    done < "$OUT/fields.changed"
  else
    echo "_none_"
  fi
  echo

  echo "## Route bodies: gates, error codes, functions"
  echo
  echo "Nothing here is a new route or a new field, so none of it shows above."
  echo "A gate that appeared is a request that used to be answered and now may be"
  echo "**403**; a status code that appeared is an error our client has never had"
  echo "to word; a function that appeared is logic inside an existing route that"
  echo "changed its answer without changing its shape."
  echo
  signals="$(route_signals)"
  if [[ -n "$signals" ]]; then
    printf '%s\n' "$signals"
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

  echo "The filtered diff of every file above is in \`$DIFF\`."
} > "$FACTS"

{
  echo "# Server reference drift — the filtered diff"
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
} > "$DIFF"

echo "$FROM_SHA" > "$OUT/from_sha"
echo "$TO_SHA" > "$OUT/to_sha"
echo "$DEV_SHA" > "$OUT/dev_sha"

echo "facts: $FACTS ($(wc -l < "$FACTS") lines)"
echo "diff:  $DIFF ($(wc -l < "$DIFF") lines)"
