#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_toolchain.sh
mkdir -p evidence
for config in Mock Development Staging Production; do
  xcodebuild -project StationCatMusic.xcodeproj -scheme StationCatMusic -configuration "$config" \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build build \
    > "evidence/build-$config.log" 2>&1
  python3 - "$config" <<'PY'
import sys,plistlib
from pathlib import Path
config=sys.argv[1]
info=plistlib.loads((Path('.build/Build/Products')/(config+'-iphonesimulator/StationCatMusic.app/Info.plist')).read_bytes())
assert info['StationEnvironment']==config.lower(), info.get('StationEnvironment')
assert info['MinimumOSVersion']=='18.0'
assert info['StationNativeAuthEnabled']=='NO'
assert not info.get('StationNativeAuthOrigin')
assert 'NSAppTransportSecurity' not in info
print(config+': environment embedded, iOS18 minimum, no HTTP exception')
PY
done
