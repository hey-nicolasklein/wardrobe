#!/usr/bin/env sh
# Rolls the production stack on stargate and stamps a fresh version.
#
# The stamp is the whole point: an open PWA polls /version.json and reloads
# itself when the string changes. Building without FORM_VERSION bakes the
# literal "dev" every time, so clients never notice a deploy and keep running
# whatever app.js they started with.
#
#   deploy/ship.sh              # web + api + worker
#   deploy/ship.sh api worker   # those, plus web for the version stamp
set -eu

cd "$(dirname "$0")/.."

services="${*:-web api worker}"
# web carries version.json, so it always rebuilds — otherwise a deploy of just
# the API would leave every open client on the previous front end.
case " $services " in
  *" web "*) ;;
  *) services="web $services" ;;
esac

FORM_VERSION="$(git rev-parse --short HEAD)$(git diff --quiet || printf -- -dirty).$(date -u +%H%M%S)"
export FORM_VERSION

printf 'Shipping [%s] as %s\n' "$services" "$FORM_VERSION"
# shellcheck disable=SC2086
docker compose --env-file .env.production -f compose.production.yaml up -d --build $services

port="$(sed -n 's/^FORM_WEB_PORT=//p' .env.production)"
: "${port:=18081}"
n=0
while [ "$n" -lt 40 ]; do
  served="$(curl -fsS "http://127.0.0.1:$port/version.json" 2>/dev/null || true)"
  case "$served" in
    *"$FORM_VERSION"*)
      printf 'Live on https://stargate.stork-platy.ts.net:8443 — %s\n' "$served"
      exit 0
      ;;
  esac
  n=$((n + 1))
  sleep 1
done
printf 'version.json never reported %s (last saw: %s)\n' "$FORM_VERSION" "${served:-nothing}" >&2
exit 1
