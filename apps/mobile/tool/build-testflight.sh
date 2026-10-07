#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Dart defines are embedded in the binary, including unused development secrets.
python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import urlparse

config = json.loads(Path('.env.production.json').read_text())
url = urlparse(config.get('FORM_API_BASE_URL', ''))
if url.scheme != 'https' or not url.hostname or url.username or url.password:
    raise SystemExit('TestFlight requires an HTTPS API URL without credentials.')
if config.get('DEV_MODE', False) not in (False, 'false'):
    raise SystemExit('Disable DEV_MODE before building for TestFlight.')
if any(config.get(key) for key in ('DEV_EMAIL', 'DEV_PASSWORD')):
    raise SystemExit('Remove DEV_EMAIL and DEV_PASSWORD from the release config.')
if config.get('APPLE_SIGN_IN') not in (True, 'true'):
    raise SystemExit('Enable APPLE_SIGN_IN for the production build.')
print('Production configuration checked; no development credentials embedded.')
PY

if [[ "${1:-}" == "--check-only" ]]; then
  exit 0
fi

node tool/generate-ios-icons.mjs

fvm flutter build ipa \
  --flavor production \
  --dart-define-from-file=.env.production.json \
  "$@"
