#!/usr/bin/env bash
# Verification stack for FORM: an API (and optionally the paid worker) on the
# disposable form_fixtures database, plus a dedicated "FORM Verify" simulator.
#
#   stack.sh up [--paid]   reset form_fixtures, seed dev@form.local, start API on :4144
#                          --paid also starts the worker, which calls OpenAI
#   stack.sh paid          start the worker on the running stack, without a reset
#   stack.sh app          build the dev app against :4144, reinstall it fresh on the sim
#   stack.sh doctor        read-only: is this instance worth driving?
#   stack.sh shot <name>   screenshot path inside the current evidence dir
#   stack.sh collect       logs, wardrobe rows and OpenAI spend into the evidence dir
#   stack.sh down          stop what `up` started and shut the sim down; evidence stays
#
# Never touches the dev database `form` or the API on :4143.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$root"
run=.verify/run
port=4144
sim_name="FORM Verify"
bundle=de.nicolasklein.form.dev
dev_email=dev@form.local

fixture_env() {
  set -a
  # shellcheck disable=SC1091
  source .env.services.local
  set +a
}

psql_fixtures() {
  (fixture_env && psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 "$@")
}

alive() { # alive <name>: the pid we recorded still runs our entry file
  local pid
  [[ -f "$run/$1.pid" ]] || return 1
  pid="$(cat "$run/$1.pid")"
  ps -o command= -p "$pid" 2>/dev/null | grep -q "apps/$1/src/index.ts"
}

start() { # start <api|worker>
  local name="$1"
  (
    fixture_env
    export API_PORT="$port" DEV_SIGN_IN=true
    nohup node --env-file="apps/$name/.env.local" --import tsx "apps/$name/src/index.ts" \
      >"$run/$name.log" 2>&1 &
    echo $! >"$run/$name.pid"
  )
}

sim_udid() {
  xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$sim_name' and d['isAvailable']:
            print(d['udid']); sys.exit()"
}

evidence_dir() {
  [[ -f "$run/id" ]] || { echo "No run. Start one with: stack.sh up" >&2; exit 1; }
  local dir=".verify/evidence/$(cat "$run/id")"
  mkdir -p "$dir"
  echo "$root/$dir"
}

up() {
  local paid=false
  [[ "${1:-}" == "--paid" ]] && paid=true
  if alive api || alive worker; then
    echo "A verification stack is already running. Use it, or run: stack.sh down" >&2
    exit 1
  fi
  if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $port is taken by a process this script did not start. Not touching it." >&2
    exit 1
  fi
  mkdir -p "$run"
  rm -f "$run"/*.pid
  date +%Y%m%d-%H%M%S >"$run/id"
  echo "$paid" >"$run/paid"

  npm run services:up
  if ! curl -sf http://127.0.0.1:9100/minio/health/live >/dev/null; then
    echo "MinIO runs but :9100 is not forwarded to the host (a Colima flake). See Gotchas in SKILL.md." >&2
    exit 1
  fi
  npm run fixtures:reset
  (fixture_env && node --import tsx packages/service/src/cli/seed-dev.ts "$dev_email")
  # Spend and new items count from here, so the seed rows stay out.
  date -u +%Y-%m-%dT%H:%M:%SZ >"$run/started"

  start api
  $paid && start worker

  for _ in $(seq 60); do
    if curl -sf "http://localhost:$port/health/ready" >/dev/null; then break; fi
    alive api || { tail -20 "$run/api.log" >&2; exit 1; }
    sleep 1
  done
  curl -sf "http://localhost:$port/health/ready" >/dev/null || {
    echo "API did not become ready. See $run/api.log" >&2; exit 1; }

  printf '{\n  "FORM_API_BASE_URL": "http://localhost:%s/",\n  "APPLE_SIGN_IN": false\n}\n' \
    "$port" >"$run/app-env.json"
  echo "Ready: API on :$port against form_fixtures, worker $($paid && echo on || echo off)."
  echo "Evidence: $(evidence_dir)"
}

paid() {
  alive api || { echo "No verification stack. Start one with: stack.sh up" >&2; exit 1; }
  alive worker && { echo "Worker already running."; return; }
  start worker
  echo true >"$run/paid"
  sleep 2
  alive worker || { tail -20 "$run/worker.log" >&2; exit 1; }
  echo "Worker on: detection and catalog images now call OpenAI."
}

app() {
  local udid
  udid="$(sim_udid)"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$sim_name" "iPhone 17 Pro")"
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # Pushing twice duplicates the photos in the library, so do it once per sim.
  if [[ ! -f ".verify/photos-$udid" ]]; then
    scripts/sim-example-photos.sh push "$udid"
    touch ".verify/photos-$udid"
  fi
  (cd apps/mobile && fvm flutter build ios --simulator --debug --flavor development \
    --dart-define-from-file "$root/$run/app-env.json")
  # Reinstalling drops the app's cached session and wardrobe from earlier runs.
  xcrun simctl uninstall "$udid" "$bundle" || true
  xcrun simctl install "$udid" apps/mobile/build/ios/iphonesimulator/Runner.app
  echo "Installed $bundle on $sim_name ($udid). Launch it with agent-device: open $bundle"
}

doctor() {
  local ok=true
  check() { if eval "$2" >/dev/null 2>&1; then echo "ok    $1"; else echo "FAIL  $1"; ok=false; fi; }
  check "API process we started is running" "alive api"
  check "API on :$port is ready" "curl -sf http://localhost:$port/health/ready"
  check "port $port belongs to our API" \
    "[[ \$(lsof -tiTCP:$port -sTCP:LISTEN) == \$(cat $run/api.pid) ]]"
  check "object storage on :9100 reachable" "curl -sf http://127.0.0.1:9100/minio/health/live"
  check "database is form_fixtures" \
    "[[ \$(psql_fixtures -Atc 'select current_database()') == form_fixtures ]]"
  check "$dev_email is seeded" \
    "[[ \$(psql_fixtures -Atc \"select count(*) from accounts where email = '$dev_email'\") == 1 ]]"
  if [[ "$(cat "$run/paid" 2>/dev/null)" == true ]]; then
    check "worker is running (paid run)" "alive worker"
  else
    echo "info  worker off: detection and catalog images stay queued"
  fi
  local udid
  udid="$(sim_udid)"
  check "$sim_name simulator exists" "[[ -n '$udid' ]]"
  [[ -n "$udid" ]] && check "app installed on $sim_name" \
    "xcrun simctl get_app_container $udid $bundle"
  $ok
}

collect() {
  local dir
  dir="$(evidence_dir)"
  cp "$run"/*.log "$dir/" 2>/dev/null || true
  local since
  since="$(cat "$run/started")"
  psql_fixtures -c "
    select i.name, i.category, i.status, i.state, i.created_at
    from wardrobe_items i join accounts a on a.id = i.account_id
    where a.email = '$dev_email' and i.created_at >= '$since' and i.deleted_at is null
    order by i.created_at" >"$dir/new-items.txt"
  psql_fixtures -c "
    select 'detection' as kind, count(*) as attempts,
           round(coalesce(sum(cost_microunits), 0) / 1e6, 4) as usd
    from detection_attempts where created_at >= '$since'
    union all
    select 'catalog image', count(*), round(coalesce(sum(cost_microunits), 0) / 1e6, 4)
    from generation_attempts where created_at >= '$since'" >"$dir/spend.txt"
  cat "$dir/spend.txt"
  echo "Evidence in $dir"
}

down() {
  local name pid
  for name in worker api; do
    if alive "$name"; then
      pid="$(cat "$run/$name.pid")"
      kill "$pid"
      echo "Stopped $name ($pid)."
    fi
    rm -f "$run/$name.pid"
  done
  local udid
  udid="$(sim_udid)"
  [[ -n "$udid" ]] && xcrun simctl shutdown "$udid" 2>/dev/null || true
  echo "Evidence kept in .verify/evidence/."
}

case "${1:-}" in
  up) up "${2:-}" ;;
  paid) paid ;;
  app) app ;;
  doctor) doctor ;;
  shot) echo "$(evidence_dir)/$(date +%H%M%S)-${2:?name}.png" ;;
  collect) collect ;;
  down) down ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
