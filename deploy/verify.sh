#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env.production ]]; then
  printf 'Missing .env.production. Verification must run from the deployment checkout.\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env.production
set +a

compose=(docker compose --env-file .env.production -f compose.production.yaml)
verify_origin="${FORM_VERIFY_ORIGIN:-${PUBLIC_WEB_ORIGIN:?PUBLIC_WEB_ORIGIN must be set}}"
"${compose[@]}" up -d --wait
"${compose[@]}" ps --status running --services | sort > "${TMPDIR:-/tmp}/form-running-services"

expected_services=$'api\nobject-storage\npostgres\nweb\nworker'
if [[ "$(<"${TMPDIR:-/tmp}/form-running-services")" != "$expected_services" ]]; then
  printf 'Not every production service is running.\n' >&2
  "${compose[@]}" ps >&2
  exit 1
fi

curl --fail --silent --show-error "$verify_origin/health/ready" \
  | grep --quiet '"status":"ready"'
curl --fail --silent --show-error --head "$verify_origin" >/dev/null

account_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM accounts')"

printf 'Production deployment is ready at %s with %s account(s).\n' "$verify_origin" "$account_count"
