#!/usr/bin/env bash
# Example outfit photos for testing item extraction in an iOS Simulator.
#
#   scripts/sim-example-photos.sh pull               # stargate -> .example-photos/
#   scripts/sim-example-photos.sh push "<sim name>"  # .example-photos/ -> sim Photos
#
# `pull` copies source photos of the owner account that produced at least one
# detection, read-only, and drops byte-identical duplicates. The photos are
# personal data and stay in the git-ignored .example-photos/ directory.
set -euo pipefail

cd "$(dirname "$0")/.."
dir=.example-photos
host="${STARGATE_HOST:-stargate}"
owner="${EXAMPLE_PHOTOS_OWNER:-nicolasklein1998@gmail.com}"

pull() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # Runs on stargate: list the keys in Postgres, fetch them through the mc
  # image on the Compose network, and stream a tarball back.
  ssh -o BatchMode=yes "$host" OWNER="$owner" bash -s <<'REMOTE' | tar -xzf - -C "$tmp"
set -euo pipefail
cd ~/dev/wardrobe-studio
set -a; source .env.production; set +a
keys="$(docker exec form-production-postgres-1 psql -U "${POSTGRES_USER:-form}" -d "${POSTGRES_DB:-form}" -At -c "
  SELECT pa.object_key
  FROM source_photos sp
  JOIN accounts a ON a.id = sp.account_id
  JOIN private_assets pa ON pa.id = sp.asset_id
  WHERE a.email = '$OWNER' AND pa.state = 'ready'
    AND EXISTS (SELECT 1 FROM detection_proposals dp WHERE dp.source_photo_id = sp.id)
  ORDER BY sp.created_at")"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
sources=()
for key in $keys; do sources+=("prod/$S3_BUCKET/$key"); done
docker run --rm --network form-production_default -v "$out:/out" \
  -e "MC_HOST_prod=http://$S3_ACCESS_KEY_ID:$S3_SECRET_ACCESS_KEY@object-storage:9000" \
  minio/mc:RELEASE.2025-08-13T08-35-41Z --quiet cp "${sources[@]}" /out/ >&2
tar -czf - -C "$out" .
REMOTE

  mkdir -p "$dir"
  local file sum ext added=0
  for file in "$tmp"/*; do
    [[ -f "$file" ]] || continue
    sum="$(shasum -a 256 "$file" | cut -c1-16)"
    case "$(file -b --mime-type "$file")" in
      image/png) ext=png ;;
      image/heic) ext=heic ;;
      *) ext=jpg ;;
    esac
    if [[ ! -e "$dir/$sum.$ext" ]]; then
      cp "$file" "$dir/$sum.$ext"
      added=$((added + 1))
    fi
  done
  printf 'Added %d new photos, %d in %s\n' "$added" "$(ls "$dir" | wc -l | tr -d ' ')" "$dir"
}

push() {
  local sim="${1:?Usage: $0 push \"<simulator name or UDID>\"}"
  local udid
  udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
want = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if want in (d["name"], d["udid"]):
            print(d["udid"]); sys.exit()
sys.exit(f"No simulator named {want!r}")' "$sim")"

  shopt -s nullglob
  local photos=("$dir"/*)
  if (( ${#photos[@]} == 0 )); then
    printf 'No photos in %s. Run "%s pull" first.\n' "$dir" "$0" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl addmedia "$udid" "${photos[@]}"
  printf 'Pushed %d photos to %s (%s)\n' "${#photos[@]}" "$sim" "$udid"
}

case "${1:-}" in
  pull) pull ;;
  push) shift; push "$@" ;;
  *) printf 'Usage: %s pull | push "<simulator name or UDID>"\n' "$0" >&2; exit 1 ;;
esac
