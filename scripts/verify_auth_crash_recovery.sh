#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_toolchain.sh
: "${M1_SIMULATOR_ID:?Set the dedicated simulator UUID}"
mkdir -p evidence
xcodebuild -project StationCatMusic.xcodeproj -scheme StationCatMusic -configuration Mock \
  -destination "platform=iOS Simulator,id=$M1_SIMULATOR_ID" -derivedDataPath .build build-for-testing > evidence/M2-build-for-crash.log 2>&1
python3 - <<'PY'
from pathlib import Path
import plistlib,copy
root=Path('.build/Build/Products')
source=max(root.glob('StationCatMusic_*.xctestrun'),key=lambda p:p.stat().st_mtime)
base=plistlib.loads(source.read_bytes())
for mode in ['YES','RECOVER']:
    data=copy.deepcopy(base)
    if 'TestConfigurations' in data:
        targets=[t for c in data['TestConfigurations'] for t in c['TestTargets']]
    else:
        targets=[v for k,v in data.items() if k!='__xctestrun_metadata__']
    for t in targets:t.setdefault('EnvironmentVariables',{})['M2_CRASH_PROBE']=mode
    (root/('M2-'+mode+'.xctestrun')).write_bytes(plistlib.dumps(data))
PY
common=(-destination "platform=iOS Simulator,id=$M1_SIMULATOR_ID" -parallel-testing-enabled NO)
set +e
xcodebuild "${common[@]}" -xctestrun .build/Build/Products/M2-YES.xctestrun \
  -only-testing:StationCatMusicTests/KeychainCrashRecoveryTests/testAExitAfterDurablePendingWrite test-without-building > evidence/M2-crash-exit.log 2>&1
result=$?
set -e
if [[ $result -eq 0 ]] || ! grep -q 'M2_CRASH_POINT_REACHED' evidence/M2-crash-exit.log; then
  echo 'The intentional test-host termination was not observed.' >&2; exit 1
fi
xcodebuild "${common[@]}" -xctestrun .build/Build/Products/M2-RECOVER.xctestrun \
  -only-testing:StationCatMusicTests/KeychainCrashRecoveryTests/testBRecoverAfterProcessTermination test-without-building > evidence/M2-crash-recovery.log 2>&1
grep -q "testBRecoverAfterProcessTermination.*passed" evidence/M2-crash-recovery.log
echo 'Abrupt test-host exit followed by a separate-process Keychain recovery passed.'
