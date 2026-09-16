#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_toolchain.sh
: "${M1_SIMULATOR_ID:?Set M1_SIMULATOR_ID}"
mkdir -p evidence
# Separate test-host lifetimes. Only a synthetic record in a dedicated dev service is used.
for test in testAWriteDurableFixture testBReadAndRemoveFixture; do
  xcodebuild -project StationCatMusic.xcodeproj -scheme StationCatMusic -configuration Mock \
    -destination "platform=iOS Simulator,id=$M1_SIMULATOR_ID" -derivedDataPath .build \
    -parallel-testing-enabled NO "-only-testing:StationCatMusicTests/KeychainRelaunchTests/$test" test \
    > "evidence/keychain-$test.log" 2>&1
  echo "$test passed in a separate test invocation"
done
