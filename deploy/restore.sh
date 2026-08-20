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

tar -tzf "$object_archive" >/dev/null
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
"${compose[@]}" exec -T postgres pg_restore \
  --no-owner --clean --if-exists \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  < "$postgres_dump"
"${compose[@]}" up -d --wait

printf 'Restored %s. Previous data is recoverable at %s\n' "$backup_dir" "$recovery_dir"
