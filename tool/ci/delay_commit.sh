#!/usr/bin/env bash
# Makes a running bambuddy container commit its database session one second
# AFTER the handler returns, the way maziggy/bambuddy#3320 reproduces the bug,
# then restarts it and waits for /health.
#
#   delay_commit.sh <container> <base-url>
#
# With a server that commits before it responds (1.3.1+) the write's answer is
# merely one second late. With one that commits after, the row is not there yet
# when the answer arrives. commit_before_response_contract_test.dart reads that
# difference. Last step of a run: the restart touches every file's server.
set -euo pipefail

container="${1:?container name}"
base="${2:?base url}"

docker exec -i -u root "$container" python3 - <<'PY'
import re
path = "/app/backend/app/core/database.py"
source = open(path).read()
start = source.index("async def get_db(")
commit = source.index("await session.commit()", start)
if "asyncio.sleep(1)" in source[start:commit]:
    raise SystemExit("get_db already delays its commit")
indent = re.search(r"\n( *)$", source[:commit]).group(1)
source = source[:commit] + "await asyncio.sleep(1)\n" + indent + source[commit:]
open(path, "w").write(source)
PY

docker restart "$container" >/dev/null
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "${base%/}/health" >/dev/null 2>&1; then
    echo "$container commits one second late"
    exit 0
  fi
  sleep 2
done
echo "$container did not come back after the restart" >&2
exit 1
