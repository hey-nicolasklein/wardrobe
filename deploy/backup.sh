#!/usr/bin/env bash
set -euo pipefail

backup_dir="${1:?Usage: ./deploy/backup.sh /path/to/backup-dir}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir/$timestamp"

docker compose --env-file .env.production -f compose.production.yaml exec -T postgres \
  pg_dump --format=custom --no-owner --clean --if-exists \
  --dbname="${POSTGRES_DB:-form}" --username="${POSTGRES_USER:-form}" \
  > "$backup_dir/$timestamp/postgres.dump"

tar --xattrs --acls --numeric-owner -C "${FORM_DATA_DIR:?FORM_DATA_DIR must be set in .env.production}" \
  -czf "$backup_dir/$timestamp/object-storage.tar.gz" object-storage

printf 'Created backup at %s\n' "$backup_dir/$timestamp"
