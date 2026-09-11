#!/usr/bin/env bash
# Read-only check: is a FORM fixture instance worth driving?
# Verifies the disposable services and the fixture web server on :18444.
# Exits non-zero and prints the first unmet precondition.
set -uo pipefail

BASE="${FORM_VERIFY_BASE:-http://127.0.0.1:18444}"
fail() { echo "DOCTOR FAIL: $1" >&2; exit 1; }

for pair in "PostgreSQL 127.0.0.1 55432" "MinIO 127.0.0.1 9100"; do
  set -- $pair
  timeout 2 bash -c "exec 3<>/dev/tcp/$2/$3" 2>/dev/null \
    || fail "$1 port $3 not answering (run: npm run services:up)"
done

code=$(curl -s -o /tmp/form-doctor-ready.json -w '%{http_code}' "$BASE/health/ready" 2>/dev/null)
[ "$code" = "200" ] || fail "$BASE/health/ready returned $code (fixture server not launched)"
grep -q '"status":"ready"' /tmp/form-doctor-ready.json \
  || fail "readiness not ready: $(cat /tmp/form-doctor-ready.json)"

# The fixture server pins the personal account, so writes need no auth.
items=$(curl -s "$BASE/v1/wardrobe-items" | grep -o '"id"' | wc -l)
[ "$items" -ge 1 ] || fail "no wardrobe items returned; fixtures not seeded"

echo "DOCTOR OK: services up, $BASE ready, $items wardrobe items seeded"
