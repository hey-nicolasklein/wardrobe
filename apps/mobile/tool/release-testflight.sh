#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo 'Usage: bash tool/release-testflight.sh --build-number N [--version X.Y.Z] [--check-only]'
}

build_number=''
release_version=''
check_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number|--version)
      if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
      if [[ "$1" == '--build-number' ]]; then build_number="$2"; else release_version="$2"; fi
      shift 2 ;;
    --check-only) check_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Choose an unused positive build number from App Store Connect.' >&2
  exit 2
fi
if [[ -z "$release_version" ]]; then
  release_version=$(python3 - <<'PY'
import re
from pathlib import Path
match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$', Path('pubspec.yaml').read_text(), re.M)
if not match:
    raise SystemExit('Expected pubspec version X.Y.Z+N.')
print(match[1])
PY
)
fi
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must be X.Y.Z.' >&2
  exit 2
fi

bash tool/build-testflight.sh --check-only
python3 - <<'PY'
import re
from pathlib import Path
signing = Path('ios/Flutter/Signing.local.xcconfig').read_text()
if not re.search(r'^\s*DEVELOPMENT_TEAM\s*=\s*4KAD6BZY57\s*$', signing, re.M):
    raise SystemExit('Signing.local.xcconfig must use paid team 4KAD6BZY57.')
PY
echo "TestFlight release: ${release_version} (${build_number}), de.nicolasklein.form, team 4KAD6BZY57."
echo 'Confirm this build number is unused in App Store Connect before uploading.'
if [[ "$check_only" == true ]]; then exit 0; fi

bash tool/verify.sh
bash tool/build-testflight.sh "--build-name=$release_version" "--build-number=$build_number"

# Check the exact archive being uploaded, not an older Organizer selection.
python3 - "$release_version" "$build_number" <<'PY'
import plistlib
import subprocess
import sys
from pathlib import Path

archive = Path('build/ios/archive/Runner.xcarchive')
info = plistlib.loads((archive / 'Info.plist').read_bytes())['ApplicationProperties']
expected = {'CFBundleIdentifier': 'de.nicolasklein.form',
            'CFBundleShortVersionString': sys.argv[1], 'CFBundleVersion': sys.argv[2],
            'Team': '4KAD6BZY57'}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Archive {key} does not match this release.')
app = archive / 'Products' / info['ApplicationPath']
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
result = subprocess.run(['codesign', '-d', '--entitlements', '-', str(app)],
                        capture_output=True, check=True)
entitlements = plistlib.loads(result.stdout)
if entitlements.get('com.apple.developer.applesignin') != ['Default']:
    raise SystemExit('Archive is missing Sign in with Apple.')
if entitlements.get('com.apple.developer.team-identifier') != '4KAD6BZY57':
    raise SystemExit('Archive has the wrong signing team.')
print('Archive identity, version, signature and Apple sign-in checked.')
PY

export_options=$(mktemp -t form-testflight-export)
trap 'rm -f "$export_options"' EXIT
python3 - "$export_options" <<'PY'
import plistlib
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'method': 'app-store-connect', 'destination': 'upload',
    'signingStyle': 'automatic', 'teamID': '4KAD6BZY57',
    'uploadSymbols': True, 'manageAppVersionAndBuildNumber': False,
}))
PY
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates

echo "Uploaded ${release_version} (${build_number})."
echo 'Wait for Apple processing, set What to Test, and confirm the build and your account in FORM Internal.'
