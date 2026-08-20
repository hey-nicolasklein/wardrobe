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

if [[ "${WEB_ORIGIN:?WEB_ORIGIN must be set}" != "${PUBLIC_WEB_ORIGIN:?PUBLIC_WEB_ORIGIN must be set}" ]]; then
  printf 'WEB_ORIGIN and PUBLIC_WEB_ORIGIN must match for browser CORS.\n' >&2
  exit 1
fi
cors_headers="$(mktemp)"
trap 'rm -f "$cors_headers"' EXIT
curl "${curl_args[@]}" --request OPTIONS --dump-header "$cors_headers" --output /dev/null \
  --header "Origin: $PUBLIC_WEB_ORIGIN" \
  --header 'Access-Control-Request-Method: POST' \
  --header 'Access-Control-Request-Headers: content-type' \
  "$verify_origin/v1/auth/sign-in"
if ! grep --fixed-strings --ignore-case --quiet "access-control-allow-origin: $PUBLIC_WEB_ORIGIN" "$cors_headers" \
  || ! grep --fixed-strings --ignore-case --quiet 'access-control-allow-credentials: true' "$cors_headers"; then
  printf 'Browser credential CORS is not configured for %s.\n' "$PUBLIC_WEB_ORIGIN" >&2
  exit 1
fi

account_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM accounts')"
if (( account_count < 1 )); then
  printf 'Production verification requires at least one administrator account.\n' >&2
  exit 1
fi
source_photo_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM source_photos')"
wardrobe_item_count="$("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --command='SELECT count(*) FROM wardrobe_items')"

mapfile -t object_records < <("${compose[@]}" exec -T postgres psql \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  --tuples-only --no-align --field-separator=$'\t' \
  --command="SELECT object_key, object_version_id, byte_size FROM private_assets WHERE state = 'ready' ORDER BY object_key")
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
  "$verify_origin" "$account_count" "$source_photo_count" "$wardrobe_item_count" "${#object_records[@]}"
