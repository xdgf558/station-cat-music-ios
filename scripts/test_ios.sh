#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_toolchain.sh
: "${M1_SIMULATOR_ID:?Set M1_SIMULATOR_ID to an available iPhone simulator UUID}"
mkdir -p evidence
result_args=()
if [[ "${M1_ARCHIVE_CI_XCRESULT:-}" == 1 ]]; then
  # Result bundles contain screenshots and typed text. Only the isolated CI
  # Mock suite may opt in; real-system and probe runs retain results locally.
  [[ "${CI:-}" == true ]] || { echo 'CI result archive requires CI=true' >&2; exit 1; }
  # Reject both a prohibited variable and any failure to run the scanner.
  # Python isolated mode ignores environment-based module injection.
  if ! python3 -I -c '
import os, sys
prefixes = ("R2_", "R3_", "M2_", "M3_", "M5_", "SIMCTL_CHILD_")
exact = {"XCODE_XCCONFIG_FILE", "PRODUCTION_ENABLE_LOCAL_E2E", "STATION_PUBLIC_LINK_ACCEPTANCE"}
sys.exit(any(name.startswith(prefixes) or name in exact for name in os.environ))
'; then
    echo 'Refusing to archive: environment is prohibited or could not be inspected' >&2
    exit 1
  fi
  [[ ! -L evidence ]] || { echo 'CI evidence directory must not be a symlink' >&2; exit 1; }
  result_path="$PWD/evidence/M1-mock-tests.xcresult"
  [[ ! -e "$result_path" && ! -L "$result_path" ]] || { echo 'CI result bundle already exists' >&2; exit 1; }
  [[ "${GITHUB_OUTPUT:-}" == /* && -f "$GITHUB_OUTPUT" && ! -L "$GITHUB_OUTPUT" ]] || {
    echo 'CI result archive requires a regular GitHub step output file' >&2; exit 1;
  }
  result_args=(-resultBundlePath "$result_path")
  printf 'archive_mock_result=true\n' >> "$GITHUB_OUTPUT"
fi
xcodebuild -project StationCatMusic.xcodeproj -scheme StationCatMusic -configuration Mock \
  -destination "platform=iOS Simulator,id=$M1_SIMULATOR_ID" -derivedDataPath .build \
  -parallel-testing-enabled NO ${result_args[@]+"${result_args[@]}"} test
