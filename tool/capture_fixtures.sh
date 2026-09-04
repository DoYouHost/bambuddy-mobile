#!/usr/bin/env bash
# Capture API fixtures from a live bambuddy server.
#
# test/fixtures/README.md asks for captured JSON rather than payloads rebuilt
# from the server's Pydantic schemas — a fixture written from the schema tests
# our reading of the contract, not the contract. This is the tool that closes
# that gap.
#
# The key never reaches a shell history or a transcript: it is read from a file
# you own, and only curl ever sees it.
#
#   printf '%s' 'bb_yourkey' > ~/.bambuddy-fixture-key
#   chmod 600 ~/.bambuddy-fixture-key
#   tool/capture_fixtures.sh https://your.server
#
# Lists are trimmed to --max records (default 8): a fixture exists to pin the
# shape of a record, and a hundred of them only makes the diff unreadable.
set -euo pipefail

KEY_FILE="${BAMBUDDY_KEY_FILE:-$HOME/.bambuddy-fixture-key}"
MAX=8
OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/captured"

usage() {
  echo "usage: $0 <base-url> [--max N] [--out DIR]" >&2
  echo "  reads the API key from $KEY_FILE (override with BAMBUDDY_KEY_FILE)" >&2
  exit 2
}

[ $# -ge 1 ] || usage
BASE="${1%/}"
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --max) MAX="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -r "$KEY_FILE" ] || { echo "no readable key file at $KEY_FILE" >&2; exit 1; }
KEY="$(tr -d '\r\n' < "$KEY_FILE")"
[ -n "$KEY" ] || { echo "$KEY_FILE is empty" >&2; exit 1; }

mkdir -p "$OUT"

# name:path pairs. Every one of these is an endpoint the app renders a screen
# from — the same list the diagnostic log samples bodies for.
ENDPOINTS=(
  "printers_list:/api/v1/printers/"
  "printer_status:/api/v1/printers/1/status"
  # `model` is required — without it the server answers 422 and the entry is
  # skipped. X2D because that is what the app is developed against; change it
  # for a different fleet.
  "available_filaments:/api/v1/printers/available-filaments?model=X2D"
  "archives_list:/api/v1/archives/"
  "archive_stats:/api/v1/archives/stats"
  "print_log:/api/v1/print-log/"
  "inventory_spools:/api/v1/inventory/spools"
  "smart_plugs:/api/v1/smart-plugs/"
  "maintenance_overview:/api/v1/maintenance/overview"
  "projects_list:/api/v1/projects/"
  "library_files:/api/v1/library/files"
  "queue_all:/api/v1/queue/"
  "queue_pending:/api/v1/queue/?status=pending"
)

for entry in "${ENDPOINTS[@]}"; do
  name="${entry%%:*}"
  path="${entry#*:}"
  body_file="$(mktemp)"
  # -H is the only place the key appears, and curl does not echo it. The
  # fallback stays outside the substitution: curl's own -w already writes 000
  # when it cannot connect, and an `|| echo 000` inside would append a second.
  code="$(curl -sS -o "$body_file" -w '%{http_code}' \
    -H "X-API-Key: $KEY" "$BASE$path")" || code=000

  if [ "$code" != "200" ]; then
    # The server's own reason, clipped: a 422 names the missing query parameter
    # and a 403 names the permission the key is short of, and guessing between
    # those two costs more than one line of output.
    echo "skip $name — HTTP $code: $(head -c 200 "$body_file")" >&2
    rm -f "$body_file"
    continue
  fi

  # Trimming and scrubbing live in scrub_fixtures.py, which is also runnable on
  # its own — a capture taken by hand deserves the same treatment.
  python3 "$(dirname "$0")/scrub_fixtures.py" \
    "$body_file" "$OUT/$name.json" --max "$MAX"
  rm -f "$body_file"
done

echo
echo "Captured into $OUT — review before committing:"
echo "  git status --short test/fixtures/"
echo "IP addresses and serials are replaced; file, project and printer names are"
echo "not — they are what makes a record readable, and they are yours to keep."
