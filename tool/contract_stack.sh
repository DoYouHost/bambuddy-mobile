#!/usr/bin/env bash
# The contract-test stack of .github/workflows/contract-tests.yml on this
# machine: a stand-in printer's broker, a bambuddy image, the fake WLED and
# Spoolman, seeded the way CI seeds them.
#
#   tool/contract_stack.sh up [tag] [port]   # tag: daily | latest | 1.2.5 ...
#   tool/contract_stack.sh down [tag]
#
# `up` writes build/contract-<tag>.env, which `just contract-test` reads.
# The label printer and Manyfold are left out (slow to build); their tests skip.
#
# The server is published on the docker bridge's gateway, as in CI, and every
# stand-in is a container: on a host whose firewall drops container-to-host
# traffic (NixOS by default) the server could not reach a process on the host.
set -euo pipefail

cmd="${1:-}"
tag="${2:-daily}"
port="${3:-18000}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
# Container names carry the user, so a CI-like run of another session or user
# on the same host is not torn down by this one.
prefix="contract-${USER:-local}-${tag//[^a-zA-Z0-9]/_}"
broker="$prefix-broker"
server="$prefix-server"
wled="$prefix-wled"
spoolman="$prefix-spoolman"
envfile="$repo/build/contract-$tag.env"

down() {
  docker rm -f "$broker" "$server" "$wled" "$spoolman" >/dev/null 2>&1 || true
  rm -f "$envfile"
}

ip_of() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

up() {
  down
  local gateway certs
  gateway="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')"
  [ -n "$gateway" ] || { echo "the docker bridge reports no gateway" >&2; exit 1; }

  certs="$repo/build/contract-certs"
  if [ ! -f "$certs/server.crt" ]; then
    mkdir -p "$certs"
    local subj=/CN=fake-bambu
    if command -v openssl >/dev/null; then
      openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout "$certs/server.key" \
        -out "$certs/server.crt" -subj "$subj" >/dev/null 2>&1
    else
      docker run --rm --user "$(id -u):$(id -g)" -v "$certs:/certs" alpine/openssl \
        req -x509 -newkey rsa:2048 -nodes -days 30 -keyout /certs/server.key \
        -out /certs/server.crt -subj "$subj" >/dev/null 2>&1
    fi
    chmod -R a+rX "$certs"
  fi

  docker create --rm --name "$broker" eclipse-mosquitto:2 >/dev/null
  docker cp "$repo/tool/ci/mosquitto.conf" "$broker":/mosquitto/config/mosquitto.conf
  docker cp "$certs" "$broker":/mosquitto/certs
  docker start "$broker" >/dev/null

  docker create --rm --name "$wled" python:3.13-slim python /fake_wled.py >/dev/null
  docker cp "$repo/tool/ci/fake_wled.py" "$wled":/fake_wled.py
  docker start "$wled" >/dev/null

  docker run -d --rm --name "$spoolman" ghcr.io/donkie/spoolman:latest >/dev/null

  docker pull --quiet "ghcr.io/maziggy/bambuddy:$tag" >/dev/null
  docker run -d --rm --name "$server" -p "$gateway:$port:8000" \
    -e DATA_DIR=/app/data -e TZ=Europe/Warsaw "ghcr.io/maziggy/bambuddy:$tag" >/dev/null

  local base="http://$gateway:$port"
  local broker_ip
  broker_ip="$(ip_of "$broker")"
  for _ in $(seq 1 90); do
    curl -sf "$base/api/v1/updates/version" >/dev/null 2>&1 && break
    sleep 2
  done
  curl -sf "$base/api/v1/updates/version" >/dev/null || {
    echo "bambuddy never answered on $base" >&2
    docker logs "$server" 2>&1 | tail -30 >&2
    exit 1
  }

  bash "$repo/tool/ci/seed_bambuddy.sh" --base-url "$base" \
    --broker-ip "$broker_ip" --broker-container "$broker" \
    --admin-user ci-admin --admin-pass 'CiTest!2026x' >/dev/null

  mkdir -p "$(dirname "$envfile")"
  cat >"$envfile" <<ENV
BAMBUDDY_CONTRACT_URL=$base
BAMBUDDY_CONTRACT_USER=ci-admin
BAMBUDDY_CONTRACT_PASS=CiTest!2026x
BAMBUDDY_CONTRACT_BROKER=$broker
BAMBUDDY_CONTRACT_BROKER_IP=$broker_ip
BAMBUDDY_CONTRACT_SPOOLMAN_URL=http://$(ip_of "$spoolman"):8000
BAMBUDDY_CONTRACT_WLED_URL=http://$(ip_of "$wled")
TZ=Europe/Warsaw
ENV
  echo "bambuddy:$tag $(curl -s "$base/api/v1/updates/version") at $base"
  echo "env: $envfile — run: just contract-test $tag"
}

case "$cmd" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down [tag] [port]" >&2; exit 64 ;;
esac
