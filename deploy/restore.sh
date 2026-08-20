#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env.production ]]; then
  printf 'Missing .env.production. Restore must run from the deployment checkout.\n' >&2
  exit 1
fi

if [[ "${FORM_RESTORE_CONFIRMED:-}" != "true" ]]; then
  printf 'Restore stops the production stack and replaces its data. Set FORM_RESTORE_CONFIRMED=true to continue.\n' >&2
  exit 1
fi

backup_dir="${1:?Usage: FORM_RESTORE_CONFIRMED=true ./deploy/restore.sh /path/to/backup/timestamp}"
postgres_dump="$backup_dir/postgres.dump"
object_archive="$backup_dir/object-storage.tar.gz"

if [[ ! -f "$postgres_dump" || ! -f "$object_archive" ]]; then
  printf 'Backup must contain postgres.dump and object-storage.tar.gz: %s\n' "$backup_dir" >&2
  exit 1
fi

archive_entries="$(tar -tzf "$object_archive")"
if [[ -z "$archive_entries" ]] \
  || ! grep --extended-regexp --quiet '^object-storage(/|$)' <<< "$archive_entries" \
  || grep --extended-regexp --quiet '(^|/)\.\.(/|$)' <<< "$archive_entries" \
  || grep --extended-regexp --invert-match --quiet '^object-storage(/|$)' <<< "$archive_entries"; then
  printf 'Media archive must contain only the object-storage directory.\n' >&2
  exit 1
fi
docker run --rm -v "$backup_dir:/backup:ro" postgres:17-alpine \
  pg_restore --file=/dev/null /backup/postgres.dump

set -a
# shellcheck disable=SC1091
source .env.production
set +a

data_dir="$(realpath -m "${FORM_DATA_DIR:?FORM_DATA_DIR must be set in .env.production}")"
case "$data_dir" in
  /|/home|/volume1|/volume1/docker)
    printf 'Refusing unsafe FORM_DATA_DIR: %s\n' "$data_dir" >&2
    exit 1
    ;;
esac
if [[ "$data_dir" != /* || "$(basename "$data_dir")" == "." ]]; then
  printf 'FORM_DATA_DIR must resolve to a dedicated absolute directory: %s\n' "$data_dir" >&2
  exit 1
fi

compose=(docker compose --env-file .env.production -f compose.production.yaml)
recovery_dir="${data_dir}.before-restore.$(date -u +%Y%m%dT%H%M%SZ)"
data_parent="$(dirname "$data_dir")"
data_name="$(basename "$data_dir")"
recovery_name="$(basename "$recovery_dir")"

"${compose[@]}" down
docker run --rm \
  -e DATA_NAME="$data_name" \
  -e RECOVERY_NAME="$recovery_name" \
  -v "$data_parent:/data-parent" \
  -v "$backup_dir:/backup:ro" \
  alpine:3.22 sh -euc '
    mkdir -p "/data-parent/$RECOVERY_NAME"
    for directory in postgres object-storage; do
      if [ -e "/data-parent/$DATA_NAME/$directory" ]; then
        mv "/data-parent/$DATA_NAME/$directory" "/data-parent/$RECOVERY_NAME/$directory"
      fi
    done
    mkdir -p "/data-parent/$DATA_NAME/postgres"
    tar -xzf /backup/object-storage.tar.gz -C "/data-parent/$DATA_NAME"
  '

"${compose[@]}" up -d --wait postgres object-storage
postgres_ready=false
for _ in $(seq 1 60); do
  # The command expands inside the container, where PostgreSQL runs as PID 1.
  # shellcheck disable=SC2016
  if "${compose[@]}" exec -T postgres sh -c \
    'test "$(cat /proc/1/comm)" = postgres && psql --dbname="$POSTGRES_DB" --username="$POSTGRES_USER" --command="SELECT 1" >/dev/null 2>&1'; then
    postgres_ready=true
    break
  fi
  sleep 2
done
if [[ "$postgres_ready" != "true" ]]; then
  printf 'PostgreSQL did not finish initialization within 120 seconds.\n' >&2
  exit 1
fi
"${compose[@]}" exec -T postgres pg_restore \
  --no-owner --clean --if-exists \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  < "$postgres_dump"
"${compose[@]}" up -d --wait

printf 'Restored %s. Previous data is recoverable at %s\n' "$backup_dir" "$recovery_dir"
