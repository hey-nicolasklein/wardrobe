#!/usr/bin/env bash
# Nightly production backup, run by cron on stargate:
#
#   30 3 * * * cd ~/dev/wardrobe-studio && ./deploy/backup-nightly.sh >> ~/backups/form-production/nightly.log 2>&1
#
# Writes one full backup through backup.sh, so restore.sh can use it as is, and
# keeps only the newest FORM_BACKUP_KEEP (default 3). It skips the run when the
# volume has less than FORM_BACKUP_MIN_FREE_GB (default 20) free, so backups
# never fill the disk.
set -euo pipefail

cd "$(dirname "$0")/.."

target="${FORM_BACKUP_DIR:-$HOME/backups/form-production/nightly}"
keep="${FORM_BACKUP_KEEP:-3}"
min_free_gb="${FORM_BACKUP_MIN_FREE_GB:-20}"
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

mkdir -p "$target"
free_gb="$(df -Pk "$target" | awk 'NR == 2 { print int($4 / 1024 / 1024) }')"
if (( free_gb < min_free_gb )); then
  printf '%s skipped: %s GB free, needs %s GB\n' "$(stamp)" "$free_gb" "$min_free_gb" >&2
  exit 1
fi

# A run that failed halfway leaves a folder without both files. It must not
# count as one of the backups we keep.
for dir in "$target"/*/; do
  [[ -d "$dir" ]] || continue
  if [[ ! -f "$dir/postgres.dump" || ! -f "$dir/object-storage.tar.gz" ]]; then
    rm -rf "$dir"
  fi
done

./deploy/backup.sh "$target"

# Folder names are UTC timestamps, so a reverse sort puts the newest first.
ls -1d "$target"/*/ | sort -r | tail -n +"$((keep + 1))" | while read -r old; do
  rm -rf "$old"
done

printf '%s kept %s, %s GB free\n' "$(stamp)" \
  "$(ls -1d "$target"/*/ | wc -l | tr -d ' ')" \
  "$(df -Pk "$target" | awk 'NR == 2 { print int($4 / 1024 / 1024) }')"
