#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_toolchain.sh
: "${M1_SIMULATOR_ID:?Set M1_SIMULATOR_ID to an available iPhone simulator UUID}"
mkdir -p evidence
xcodebuild -project StationCatMusic.xcodeproj -scheme StationCatMusic -configuration Mock \
  -destination "platform=iOS Simulator,id=$M1_SIMULATOR_ID" -derivedDataPath .build \
  -parallel-testing-enabled NO test
