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
curl_args=(--fail --silent --show-error)
if [[ -n "${FORM_VERIFY_RESOLVE:-}" ]]; then
  curl_args+=(--resolve "$FORM_VERIFY_RESOLVE")
fi
"${compose[@]}" up -d --wait
"${compose[@]}" ps --status running --services | sort > "${TMPDIR:-/tmp}/form-running-services"

expected_services=$'api\nobject-storage\npostgres\nweb\nworker'
if [[ "$(<"${TMPDIR:-/tmp}/form-running-services")" != "$expected_services" ]]; then
  printf 'Not every production service is running.\n' >&2
  "${compose[@]}" ps >&2
  exit 1
fi

curl "${curl_args[@]}" "$verify_origin/health/ready" \
  | grep --quiet '"status":"ready"'
curl "${curl_args[@]}" --head "$verify_origin" >/dev/null

sign_in_body="$(mktemp)"
session_body="$(mktemp)"
trap 'rm -f "$sign_in_body" "$session_body"' EXIT

verify_email="${FORM_VERIFY_EMAIL:?Set FORM_VERIFY_EMAIL for the administrator login check}"
verify_password="${FORM_VERIFY_PASSWORD:?Set FORM_VERIFY_PASSWORD for the administrator login check}"
verify_email_normalized="$(
  "${compose[@]}" exec -T api node -e \
    'process.stdout.write(process.argv[1].trim().toLowerCase())' "$verify_email"
)"
sign_in_request="$("${compose[@]}" exec -T api node -e '
  process.stdout.write(JSON.stringify({ email: process.argv[1], password: process.argv[2] }))
' "$verify_email_normalized" "$verify_password")"
curl "${curl_args[@]}" --output "$sign_in_body" \
  --header 'Content-Type: application/json' \
  --data "$sign_in_request" \
  "$verify_origin/v1/auth/sign-in"
session_token="$("${compose[@]}" exec -T api node -e '
  process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")).session.nativeToken ?? "")
' < "$sign_in_body")"
if [[ -z "$session_token" ]]; then
  printf 'Administrator sign-in did not return a session token.\n' >&2
  exit 1
fi
curl "${curl_args[@]}" --output "$session_body" \
  --header "Authorization: Bearer $session_token" \
  "$verify_origin/v1/auth/session"
if ! grep --fixed-strings --quiet "\"email\":\"$verify_email_normalized\"" "$session_body"; then
  printf 'The restored session does not match %s.\n' "$verify_email" >&2
  exit 1
fi

active_account_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM accounts WHERE disabled_at IS NULL')"
if (( active_account_count < 1 )); then
  printf 'Production verification requires at least one active administrator account.\n' >&2
  exit 1
fi
source_photo_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM source_photos')"
wardrobe_item_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM wardrobe_items')"

object_rows="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --field-separator=$'\t' \
  --command="SELECT object_key, object_version_id, byte_size FROM private_assets WHERE state = 'ready' ORDER BY object_key")"
object_records=()
if [[ -n "$object_rows" ]]; then
  mapfile -t object_records <<< "$object_rows"
fi
for object_record in "${object_records[@]}"; do
  IFS=$'\t' read -r object_key object_version_id expected_size <<< "$object_record"
  # These variables expand inside the storage container.
  # shellcheck disable=SC2016
  actual_size="$("${compose[@]}" exec -T object-storage sh -euc '
    mc alias set verify http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
    mc cat --version-id "$3" "verify/$1/$2"
  ' _ "${S3_BUCKET:?S3_BUCKET must be set}" "$object_key" "$object_version_id" | wc -c | tr -d ' ')"
  if [[ "$actual_size" != "$expected_size" ]]; then
    printf 'Private object size mismatch for %s: expected %s, received %s.\n' \
      "$object_key" "$expected_size" "$actual_size" >&2
    exit 1
  fi
done

printf 'Production deployment is ready at %s with %s account(s), %s source photo(s), %s wardrobe item(s), and %s verified private object(s).\n' \
  "$verify_origin" "$active_account_count" "$source_photo_count" "$wardrobe_item_count" "${#object_records[@]}"
